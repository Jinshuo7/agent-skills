#!/usr/bin/env bash
# lib/review.sh - pluggable reviewer run against an exact PR head SHA. Fail closed.
# Requires: PROJECT, TICKET_DIR, BELT_HOME, REVIEWER_CMD, LOG.

review_worktree_cleanup() { # review_worktree_cleanup <project> <path>
  local project=${1:-} rw=${2:-}
  [ -n "$rw" ] || return 0
  ensure_under_belt_home "$rw" || return 0
  git -C "$project" worktree remove --force "$rw" >/dev/null 2>&1 || true
  rm -rf "$rw"
}

review_prompt() { # review_prompt <base> <sha> <worktree>
  local base=${1:?} sha=${2:?} rw=${3:?} diff size
  if ! diff=$(git -C "$rw" diff "origin/$base...HEAD" 2>/dev/null); then
    REVIEW_ERR="could not compute diff against origin/$base"
    return 1
  fi
  size=$(printf '%s' "$diff" | wc -c | tr -d '[:space:]')
  if [ "$size" -gt 409600 ]; then
    REVIEW_ERR="diff too large for review ($size bytes)"
    return 1
  fi
  cat <<EOF
Review this diff of the checkout in the current folder (head $sha); you may read other files for context.
This PR is meant to close a GitHub issue. Look for correctness bugs, safety problems and missing tests.
Be concrete and terse.
List findings one per line using exactly the prefixes "P1: " (must fix before merge) or "P2: " (minor),
at most 12 finding lines in total. Then finish with a last line that is exactly:
VERDICT: PASS
or
VERDICT: FIX
Use VERDICT: FIX if and only if there is at least one P1 finding.

The diff:
\`\`\`diff
$diff
\`\`\`
EOF
}

review_answer() { # review_answer <out-file> <stdout-file>; prints the file holding the answer
  if [ -s "${1:-}" ]; then printf '%s\n' "$1"; return 0; fi
  if [ -s "${2:-}" ]; then printf '%s\n' "$2"; return 0; fi
  return 1
}

review_verdict_of() { # review_verdict_of <answer-file>; prints VERDICT: PASS or VERDICT: FIX, or nothing
  # The verdict must end the answer, but models wrap it: bold or code marks,
  # a closing code fence, or the verdict at the end of a sentence all count.
  grep -v '^[[:space:]]*$' "${1:?}" | tr -d '\r' | grep -v '^[[:space:]]*```[[:space:]]*$' | tail -n 1 \
    | sed -e 's/[*_`]//g' -e 's/[[:space:]]*$//' \
    | sed -En 's/^(.*[^[:alnum:]])?VERDICT:[[:space:]]*(PASS|FIX)[.!]?$/VERDICT: \2/p'
}

review_index_flags() { # review_index_flags <worktree>; entries status never shows
  # A lowercase tag means assume-unchanged, 'S' means skip-worktree. Either one
  # lets a reviewer edit a tracked file while HEAD and status stay identical.
  local rw=${1:?} tags
  tags=$(git -C "$rw" ls-files -v 2>/dev/null) || return 1
  [ -n "$tags" ] || return 0
  printf '%s\n' "$tags" | awk '$1 ~ /^(S|[[:lower:]])$/ { print }'
  return 0
}

review_content_hash() { # review_content_hash <worktree>; hash of every tracked file's content
  local rw=${1:?} hashes
  hashes=$(git -C "$rw" ls-files -z 2>/dev/null | xargs -0 git -C "$rw" hash-object 2>/dev/null) || return 1
  [ -n "$hashes" ] || return 1
  printf '%s\n' "$hashes"
}

review_pr() { # review_pr <pr> <slug> <project> <base> [reviewer-cmd]
  # sets REVIEW_OK, REVIEW_SHA, REVIEW_P1, REVIEW_LINES, REVIEW_ERR, REVIEW_RATE_LIMITED
  local pr=${1:?} slug=${2:?} project=${3:?} base=${4:?} reviewer=${5:-${REVIEWER_CMD:-}}
  local sha rw rc last findings p1 body log answer attempt
  local before_head before_status before_hash after_head after_status after_hash after_flags
  REVIEW_OK=0
  REVIEW_SHA=""
  REVIEW_P1=0
  REVIEW_LINES=""
  REVIEW_ERR=""
  REVIEW_RATE_LIMITED=0
  REVIEW_KILLED=0
  log="${TICKET_DIR:-/tmp}/review.log"
  mkdir -p "${TICKET_DIR:-/tmp}" 2>/dev/null || true
  : >"$log"

  # 1. exact, full head SHA straight from the PR
  sha=$(gh pr view "$pr" -R "$slug" --json headRefOid -q .headRefOid 2>>"$log") || {
    REVIEW_ERR="could not read PR head SHA"
    return 1
  }
  sha=$(printf '%s' "$sha" | tr -d '[:space:]')
  case "$sha" in
    ''|*[!0-9a-f]*) REVIEW_ERR="invalid head SHA"; return 1 ;;
  esac
  if [ "${#sha}" -ne 40 ]; then
    REVIEW_ERR="head SHA is not a full 40-char SHA"
    return 1
  fi

  # 2. the commit must exist locally; try to fetch it if not
  if ! git -C "$project" cat-file -e "$sha^{commit}" 2>/dev/null; then
    git -C "$project" fetch origin "$sha" >>"$log" 2>&1 || true
  fi
  if ! git -C "$project" cat-file -e "$sha^{commit}" 2>/dev/null; then
    REVIEW_ERR="unknown SHA $sha"
    return 1
  fi

  # 3. detached review worktree at exactly that SHA, outside the project
  rw="${STATE_DIR:-${BELT_HOME:-$HOME/.belt}/review}/$pr-$sha"
  if ! ensure_under_belt_home "$rw"; then
    REVIEW_ERR="review worktree outside BELT_HOME"
    return 1
  fi
  mkdir -p "$(dirname "$rw")" || { REVIEW_ERR="cannot create review dir"; return 1; }
  git -C "$project" worktree remove --force "$rw" >/dev/null 2>&1 || true
  rm -rf "$rw"
  if ! git -C "$project" worktree add --detach "$rw" "$sha" >>"$log" 2>&1; then
    REVIEW_ERR="could not create review worktree"
    return 1
  fi
  if [ "$(git -C "$rw" rev-parse HEAD 2>/dev/null)" != "$sha" ]; then
    review_worktree_cleanup "$project" "$rw"
    REVIEW_ERR="review checkout is not at $sha"
    return 1
  fi

  # 4. the full diff goes into the prompt; never truncate, fail closed instead
  if ! review_prompt "$base" "$sha" "$rw" >"$TICKET_DIR/review-prompt.txt" 2>>"$log"; then
    review_worktree_cleanup "$project" "$rw"
    return 1
  fi

  # 4b. empty diff is a review failure
  if [ "$(git -C "$rw" diff --name-only "origin/$base...HEAD" 2>/dev/null | grep -c '')" -eq 0 ]; then
    review_worktree_cleanup "$project" "$rw"
    REVIEW_ERR="empty diff against origin/$base"
    return 1
  fi

  # 5. run the reviewer slot read-only; the answer may go to BELT_OUT_FILE.
  # A reviewer that answers without a valid verdict gets one more run; the
  # read-only checks run after every attempt, and the second bad answer fails.
  before_head=$(git -C "$rw" rev-parse HEAD 2>>"$log") || {
    review_worktree_cleanup "$project" "$rw"
    REVIEW_ERR="could not read review worktree HEAD before the reviewer"
    return 1
  }
  before_head=$(printf '%s' "$before_head" | tr -d '[:space:]')
  case "$before_head" in
    ''|*[!0-9a-f]*)
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="invalid review worktree HEAD before the reviewer"
      return 1
      ;;
  esac
  if ! before_status=$(git -C "$rw" status --porcelain --untracked-files=all 2>>"$log"); then
    review_worktree_cleanup "$project" "$rw"
    REVIEW_ERR="could not read review worktree status before the reviewer"
    return 1
  fi
  if ! before_hash=$(review_content_hash "$rw" 2>>"$log"); then
    review_worktree_cleanup "$project" "$rw"
    REVIEW_ERR="could not hash review worktree tracked files before the reviewer"
    return 1
  fi
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    : >"$TICKET_DIR/verdict.txt"
    : >"$TICKET_DIR/reviewer-out.txt"
    slot_run_retry "$reviewer" "$rw" "$TICKET_DIR/review-prompt.txt" \
      "$TICKET_DIR/verdict.txt" "$TICKET_DIR/reviewer-out.txt" "$log" "" "" reviewer
    rc=$?
    REVIEW_RATE_LIMITED=${SLOT_RATE_LIMITED:-0}
    REVIEW_KILLED=${SLOT_KILLED:-0}

    # read-only guard: status hides entries flagged assume-unchanged or
    # skip-worktree, so check those flags and the tracked content itself too.
    if ! after_flags=$(review_index_flags "$rw" 2>>"$log"); then
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="could not read review worktree index flags after the reviewer"
      return 1
    fi
    if [ -n "$after_flags" ]; then
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="reviewer set assume-unchanged or skip-worktree flags"
      return 1
    fi
    # the review worktree's index lives in the common dir, which a reviewer role
    # may not write; a failed refresh must stay harmless. The flag check above and
    # the HEAD/status/content-hash checks below still catch any hidden edit.
    git -C "$rw" update-index --really-refresh >>"$log" 2>&1 ||
      printf 'note: could not refresh the review worktree index (checks still run)\n' >>"$log"
    if ! after_head=$(git -C "$rw" rev-parse HEAD 2>>"$log"); then
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="could not read review worktree HEAD after the reviewer"
      return 1
    fi
    after_head=$(printf '%s' "$after_head" | tr -d '[:space:]')
    if ! after_status=$(git -C "$rw" status --porcelain --untracked-files=all 2>>"$log"); then
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="could not read review worktree status after the reviewer"
      return 1
    fi
    if ! after_hash=$(review_content_hash "$rw" 2>>"$log"); then
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="could not hash review worktree tracked files after the reviewer"
      return 1
    fi

    # a failed reviewer run must never be accepted just because it left a file behind
    if [ "$rc" -ne 0 ]; then
      review_worktree_cleanup "$project" "$rw"
      if [ "$REVIEW_RATE_LIMITED" = "1" ]; then
        REVIEW_ERR="reviewer was rate limited for more than 6 hours"
      else
        REVIEW_ERR="reviewer exited with status $rc"
      fi
      return 1
    fi
    if [ "$after_head" != "$before_head" ] || [ "$after_status" != "$before_status" ] \
      || [ "$after_hash" != "$before_hash" ]; then
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="reviewer changed files"
      return 1
    fi

    # BELT_OUT_FILE wins when non-empty; otherwise the captured stdout is the answer
    answer=$(review_answer "$TICKET_DIR/verdict.txt" "$TICKET_DIR/reviewer-out.txt") || {
      if [ "$attempt" -lt 2 ]; then
        log "reviewer produced no verdict (exit $rc); rerunning the reviewer once"
        continue
      fi
      review_worktree_cleanup "$project" "$rw"
      REVIEW_ERR="reviewer produced no verdict (exit $rc)"
      return 1
    }

    # 6. the answer must end with a verdict; one bad answer gets one rerun
    last=$(review_verdict_of "$answer")
    case "$last" in
      "VERDICT: PASS"|"VERDICT: FIX") ;;
      *)
        if [ "$attempt" -lt 2 ]; then
          log "reviewer last line is not a VERDICT line; rerunning the reviewer once"
          continue
        fi
        review_worktree_cleanup "$project" "$rw"
        REVIEW_ERR="last line is not a VERDICT line"
        return 1
        ;;
    esac
    break
  done
  review_worktree_cleanup "$project" "$rw"

  # Count every P1 in the full verdict before trimming the display copy. A P1
  # beyond the 12-line cap must still block the merge gate.
  all_findings=$(grep -v '^[[:space:]]*$' "$answer" | sed -e '$d' | tr -d '\r')
  p1=$(count_p1_findings "$answer")
  findings=$(printf '%s\n' "$all_findings" | head -n 12)
  if [ "$last" = "VERDICT: FIX" ] && [ "$p1" -eq 0 ]; then
    # a FIX verdict without a P1 is inconsistent: fail closed
    REVIEW_ERR="VERDICT: FIX without any P1 finding"
    return 1
  fi

  # 7. post the review (never on failure), at most 15 lines
  body="### Review of $sha"
  if [ -n "$findings" ]; then
    body="$body

$findings"
  fi
  body="$body
$last"
  body=$(printf '%s\n' "$body" | head -n 15)
  if ! gh pr comment "$pr" -R "$slug" --body "$body" >>"$log" 2>&1; then
    REVIEW_ERR="could not post review comment"
    return 1
  fi

  # keep every finding for the fix round, even those beyond the posted 12
  printf '%s\n' "$all_findings" >"$TICKET_DIR/findings.txt"
  # persist what the merge gate needs when watch resumes it without a model call
  printf '%s\n' "$sha" >"$TICKET_DIR/review-sha" 2>/dev/null || true
  printf '%s\n' "$p1" >"$TICKET_DIR/review-p1" 2>/dev/null || true
  REVIEW_SHA=$sha
  REVIEW_P1=$p1
  REVIEW_LINES=$findings
  REVIEW_OK=1
  log "review of $sha: $p1 P1 finding(s)"
  return 0
}

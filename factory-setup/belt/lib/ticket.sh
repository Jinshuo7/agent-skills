#!/usr/bin/env bash
# lib/ticket.sh - one issue through stations 1-10. Bash 3.2 compatible.

# ------------------------------------------------------------------ setup ---

ticket_run() { # ticket_run <issue-number>
  local issue=${1:-} rc
  case "$issue" in
    ''|*[!0-9]*) warn "usage: belt run <issue-number>"; return 2 ;;
  esac
  N=$issue
  load_config || { warn "could not load config"; return 1; }
  require_slots || return 1
  SLUG=$(repo_slug) || { warn "cannot determine repo slug (set REPO in belt.conf)"; return 1; }
  STATE_DIR=$(state_dir_for "$SLUG")
  TICKET_DIR="$STATE_DIR/$N"
  OUT_DIR="$TICKET_DIR/out"
  LOG="$TICKET_DIR/log"
  WORKTREE="$STATE_DIR/worktrees/$N"
  BRANCH=$(belt_branch_for "$N")
  PR=""
  BASE=""
  ISSUE_TITLE=""
  ISSUE_BODY=""
  REVIEW_SHA=""
  REVIEW_P1=0
  CHECK_TABLE=""
  CHECK_FAILED=""
  RESUME_PR=0
  FIX_ROUND=0
  TICKET_FINISHED=0
  NOCHANGE=0
  NOCHANGE_TEXT=""
  TERMINAL_RELABEL_FAILED=0
  MERGED=0
  RISKY_FILE=""

  mkdir -p "$TICKET_DIR" "$OUT_DIR" "$STATE_DIR/worktrees" "$STATE_DIR/review" || {
    warn "could not create state dirs under $STATE_DIR"
    return 1
  }
  if ! ensure_under_belt_home "$WORKTREE"; then return 1; fi
  # One run per ticket: two runs would share the worktree, index, logs and
  # review files. Refuse (fail closed) instead of racing.
  if ! acquire_lock "$TICKET_DIR/ticket.lock" 0; then
    warn "ticket #$N is already running for $SLUG (lock $TICKET_DIR/ticket.lock)"
    return 3
  fi
  printf '\n=== belt %s ticket #%s (%s) ===\n' "$(belt_now)" "$N" "$SLUG" >>"$LOG"

  stamp ticket start
  ticket_flow
  rc=$?
  if [ "$rc" -eq 0 ]; then stamp ticket end; else stamp ticket stuck; fi
  release_lock "$TICKET_DIR/ticket.lock"
  return $rc
}

load_issue() {
  local json
  json=$(gh issue view "$N" -R "$SLUG" --json title,body 2>>"$LOG") || {
    STATUS_REASON="could not read issue #$N"
    return 1
  }
  ISSUE_TITLE=$(printf '%s' "$json" | jq -r '.title // ""')
  ISSUE_BODY=$(printf '%s' "$json" | jq -r '.body // ""')
  return 0
}

# --------------------------------------------------------------- stations ---

station_claim() { # station 1
  ensure_labels "$SLUG" || true
  if ! gh issue edit "$N" -R "$SLUG" --add-label "$(claim_label)" >>"$LOG" 2>&1; then
    STATUS_REASON="could not add $(claim_label)"
    return 1
  fi
  gh issue comment "$N" -R "$SLUG" --body "belt picked this up." >>"$LOG" 2>&1 \
    || warn "could not comment on issue #$N"
  log "claimed issue #$N in $SLUG"
  return 0
}

reset_worktree_to_base() { # discard unreviewed commits left by an earlier failed run
  local count
  if ! git -C "$WORKTREE" fetch origin "$BASE" >>"$LOG" 2>&1; then
    STATUS_REASON="git fetch origin $BASE failed"
    return 1
  fi
  if ! git -C "$WORKTREE" rev-parse --verify -q "origin/$BASE^{commit}" >/dev/null 2>&1; then
    STATUS_REASON="origin/$BASE does not exist"
    return 1
  fi
  count=$(git -C "$WORKTREE" rev-list --count "origin/$BASE..HEAD" 2>/dev/null) || count="?"
  case "$count" in
    0) ;;
    *)
      log "discarding $count unreviewed commit(s) on $BRANCH left by an earlier run"
      ;;
  esac
  if ! git -C "$WORKTREE" reset --hard "origin/$BASE" >>"$LOG" 2>&1; then
    STATUS_REASON="could not reset the worktree to origin/$BASE"
    return 1
  fi
  if ! git -C "$WORKTREE" clean -fd >>"$LOG" 2>&1; then
    STATUS_REASON="could not clean the worktree"
    return 1
  fi
  return 0
}

station_worktree() { # station 2
  local cur head dirty prhead prbase
  BASE=$(base_branch)
  RESUME_PR=0
  if ! git -C "$PROJECT" remote get-url origin >/dev/null 2>&1; then
    STATUS_REASON="no origin remote in $PROJECT"
    return 1
  fi
  log "git fetch origin"
  if ! git -C "$PROJECT" fetch origin >>"$LOG" 2>&1; then
    STATUS_REASON="git fetch origin failed"
    return 1
  fi
  # drop metadata for worktrees whose directory disappeared (e.g. BELT_HOME moved)
  git -C "$PROJECT" worktree prune >>"$LOG" 2>&1 || true

  if [ -e "$WORKTREE/.git" ]; then
    log "reusing worktree $WORKTREE"
    cur=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
      STATUS_REASON="existing worktree is broken"
      return 1
    }
    if [ "$cur" != "$BRANCH" ]; then
      STATUS_REASON="worktree is on '$cur', expected '$BRANCH'"
      return 1
    fi
  elif [ -e "$WORKTREE" ]; then
    STATUS_REASON="worktree path exists but is not a git worktree"
    return 1
  else
    if git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git -C "$PROJECT" worktree add "$WORKTREE" "$BRANCH" >>"$LOG" 2>&1 || {
        STATUS_REASON="git worktree add failed (branch $BRANCH)"
        return 1
      }
    elif git -C "$PROJECT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      git -C "$PROJECT" worktree add -b "$BRANCH" "$WORKTREE" "origin/$BRANCH" >>"$LOG" 2>&1 || {
        STATUS_REASON="git worktree add -b failed ($BRANCH from origin)"
        return 1
      }
    else
      git -C "$PROJECT" worktree add -b "$BRANCH" "$WORKTREE" "origin/$BASE" >>"$LOG" 2>&1 || {
        STATUS_REASON="git worktree add -b failed (from origin/$BASE)"
        return 1
      }
    fi
  fi

  if ! PR=$(gh pr list -R "$SLUG" --head "$BRANCH" --state open --json number -q '.[0].number // empty' 2>>"$LOG"); then
    STATUS_REASON="could not list PRs for $BRANCH"
    return 1
  fi
  if [ -n "$PR" ]; then
    RESUME_PR=1
    log "PR #$PR already exists for $BRANCH; resuming at review"
    if ! prbase=$(gh pr view "$PR" -R "$SLUG" --json baseRefName -q .baseRefName 2>>"$LOG"); then
      STATUS_REASON="could not read the base branch of PR #$PR"
      return 1
    fi
    prbase=$(printf '%s' "$prbase" | tr -d '[:space:]')
    if [ -z "$prbase" ] || [ "$prbase" != "$BASE" ]; then
      STATUS_REASON="PR #$PR targets '${prbase:-unknown}', expected '$BASE'; refusing to review or merge it"
      return 1
    fi
    if ! prhead=$(gh pr view "$PR" -R "$SLUG" --json headRefOid -q .headRefOid 2>>"$LOG"); then
      STATUS_REASON="could not read the head SHA of PR #$PR"
      return 1
    fi
    prhead=$(printf '%s' "$prhead" | tr -d '[:space:]')
    case "$prhead" in
      ''|*[!0-9a-f]*) STATUS_REASON="invalid head SHA for PR #$PR"; return 1 ;;
    esac
    if [ "${#prhead}" -ne 40 ]; then
      STATUS_REASON="PR #$PR head is not a full 40-char SHA"
      return 1
    fi
    if ! git -C "$PROJECT" cat-file -e "$prhead^{commit}" 2>/dev/null; then
      git -C "$PROJECT" fetch origin "$prhead" >>"$LOG" 2>&1 || true
    fi
    if ! git -C "$WORKTREE" fetch origin "$BRANCH" >>"$LOG" 2>&1; then
      STATUS_REASON="git fetch origin $BRANCH failed"
      return 1
    fi
    if ! git -C "$WORKTREE" merge --ff-only FETCH_HEAD >>"$LOG" 2>&1; then
      warn "could not fast-forward the worktree to the PR head"
    fi
    head=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null) || {
      STATUS_REASON="cannot read worktree HEAD"
      return 1
    }
    if [ "$head" != "$prhead" ]; then
      STATUS_REASON="worktree HEAD ${head:-?} does not match PR #$PR head $prhead"
      return 1
    fi
    # checks and merge must describe the exact committed PR head, never a dirty tree
    if ! dirty=$(git -C "$WORKTREE" status --porcelain --untracked-files=all 2>>"$LOG"); then
      STATUS_REASON="could not inspect the resumed worktree"
      return 1
    fi
    if [ -n "$dirty" ]; then
      STATUS_REASON="resumed worktree has uncommitted changes at $prhead; refusing to check or merge"
      return 1
    fi
  else
    # No PR for this branch: any commits or files here are unreviewed leftovers
    # from an earlier failed run. Rebuild from origin/$BASE so a later push can
    # never publish them (including secrets a worker committed by mistake).
    reset_worktree_to_base || return 1
  fi
  return 0
}

station_implement() { # station 3; $1 = extra text for a retry/fix round
  local extra=${1:-} before after rc prompt comments json rules
  json=$(gh issue view "$N" -R "$SLUG" --json title,body,comments 2>>"$LOG") || {
    STATUS_REASON="could not read issue #$N"
    return 1
  }
  ISSUE_TITLE=$(printf '%s' "$json" | jq -r '.title // ""')
  ISSUE_BODY=$(printf '%s' "$json" | jq -r '.body // ""')
  comments=$(printf '%s' "$json" | jq -r '(.comments // []) | .[-5:] | .[] | "- " + ((.body // "") | tostring)' 2>/dev/null)
  rules=$(cat "$BELT_ROOT/worker-rules.md" 2>/dev/null) || rules=""

  prompt="$rules

## Ticket #$N: $ISSUE_TITLE

$ISSUE_BODY

### Last comments
${comments:-none}

## Your output directory
$OUT_DIR
Write commit.txt, title.txt, receipt.md, optional owner-steps.txt, or nochange.txt there as described.
Read AGENTS.md / CLAUDE.md in the repo first if present.
"
  if [ -n "$extra" ]; then
    prompt="$prompt

## This is a retry; fix the following
$extra
"
  fi
  printf '%s\n' "$prompt" >"$TICKET_DIR/prompt.txt"
  : >"$TICKET_DIR/worker-out.txt"

  before=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null) || {
    STATUS_REASON="cannot read worktree HEAD"
    return 1
  }
  log "worker start"
  stamp impl start
  slot_run_retry "$WORKER_CMD" "$WORKTREE" "$TICKET_DIR/prompt.txt" \
    "$TICKET_DIR/worker-out.txt" "$TICKET_DIR/worker.log" "" "" "" worker
  rc=$?
  tail -n 40 "$TICKET_DIR/worker.log" >>"$LOG" 2>/dev/null || true

  if [ "$rc" -ne 0 ]; then
    stamp impl stuck
    if [ "${SLOT_KILLED:-0}" = "1" ]; then
      STATUS_REASON="worker ${SLOT_FAIL_TEXT:-was killed as hung}"
    elif [ "${SLOT_RATE_LIMITED:-0}" = "1" ]; then
      STATUS_REASON="worker was rate limited for more than 6 hours"
    else
      STATUS_REASON="worker exited with status $rc"
    fi
    return 1
  fi
  after=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null) || { stamp impl stuck; return 1; }
  if [ "$after" != "$before" ]; then
    stamp impl stuck
    STATUS_REASON="worker committed changes (HEAD moved from $before to $after)"
    return 1
  fi
  stamp impl end
  log "worker finished"
  return 0
}

station_checks() { # station 4
  local name cmd out rc
  CHECK_TABLE=""
  CHECK_FAILED=""
  for name in build test lint; do
    case "$name" in
      build) cmd=$CHECK_BUILD ;;
      test) cmd=$CHECK_TEST ;;
      lint) cmd=$CHECK_LINT ;;
    esac
    if [ -z "$cmd" ]; then
      CHECK_TABLE="$CHECK_TABLE
$name|SKIPPED"
      continue
    fi
    if [ -n "$CHECK_FAILED" ]; then
      CHECK_TABLE="$CHECK_TABLE
$name|SKIPPED (not reached)"
      continue
    fi
    out="$TICKET_DIR/check-$name.log"
    log "check $name"
    (
      cd "$WORKTREE" || exit 1
      run_check_command "$name" "$cmd"
    ) >"$out" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      CHECK_TABLE="$CHECK_TABLE
$name|PASS"
    else
      CHECK_FAILED=$name
      CHECK_TABLE="$CHECK_TABLE
$name|FAIL (exit $rc)"
      STATUS_REASON="check '$name' failed with exit $rc"
      tail -n 20 "$out" >>"$LOG" 2>/dev/null || true
    fi
  done
  printf '%s\n' "$CHECK_TABLE" | sed '/^[[:space:]]*$/d' >"$TICKET_DIR/checks.tsv" 2>/dev/null || true
  [ -z "$CHECK_FAILED" ]
}

station_receipt() { # station 5
  local src="$OUT_DIR/receipt.md" final="$TICKET_DIR/receipt.md"
  local table tlines room body
  if [ ! -s "$src" ]; then
    {
      printf '# %s\n\n' "${ISSUE_TITLE:-Issue #$N}"
      printf 'Issue: #%s\n\n' "$N"
      printf 'Branch: `%s`\n\n' "$BRANCH"
      printf '## Files changed\n\n'
      git -C "$WORKTREE" status --porcelain 2>/dev/null | sed 's/^/    /'
      printf '\n## Doubts\n\nNone recorded by the worker.\n'
    } >"$src"
  fi

  # belt builds the Checks table from real results, never from worker claims
  table="## Checks
| Check | Result |
| --- | --- |
$(printf '%s\n' "$CHECK_TABLE" | sed '/^[[:space:]]*$/d' | awk -F'|' '{printf "| %s | %s |\n", $1, $2}')"
  tlines=$(printf '%s\n' "$table" | grep -c '')
  room=$((40 - tlines - 1))
  [ "$room" -lt 5 ] && room=5
  body=$(awk '/^## Checks[[:space:]]*$/{exit} {print}' "$src" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')
  {
    printf '%s\n' "$body" | head -n "$room"
    printf '\n%s\n' "$table"
  } >"$final"
  if [ "$(line_count "$final")" -gt 40 ]; then
    head -n 40 "$final" >"$final.tmp" && mv "$final.tmp" "$final"
  fi
  return 0
}

collect_files() { # collect_files <outfile>; NUL-separated changed *files* (never directories)
  local out=${1:?} tmp subtmp entry xy path _old subpath rc=0
  tmp="${TICKET_DIR:-${TMPDIR:-/tmp}}/.belt-status.$$.$RANDOM"
  subtmp="$tmp.sub"
  : >"$out" || return 1
  if ! git -C "$WORKTREE" status --porcelain -z --untracked-files=all >"$tmp" 2>>"$LOG"; then
    rm -f "$tmp" "$subtmp"
    warn "git status failed in $WORKTREE"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    [ -n "$entry" ] || continue
    xy=${entry:0:2}
    path=${entry:3}
    case "$xy" in
      R*|C*)
        # rename/copy: the old path is the next NUL-separated record
        IFS= read -r -d '' _old || true
        ;;
    esac
    [ -n "$path" ] || continue
    if [ -d "$WORKTREE/$path" ]; then
      # -uall should already prevent this, but never let git add recurse into a directory
      if ! GIT_LITERAL_PATHSPECS=1 git -C "$WORKTREE" ls-files --others --exclude-standard -z -- "$path" >"$subtmp" 2>>"$LOG"; then
        warn "could not expand untracked directory '$path'"
        rc=1
        break
      fi
      while IFS= read -r -d '' subpath; do
        [ -n "$subpath" ] || continue
        printf '%s\0' "$subpath" >>"$out"
      done <"$subtmp"
      : >"$subtmp"
    else
      printf '%s\0' "$path" >>"$out"
    fi
  done <"$tmp"
  rm -f "$tmp" "$subtmp"
  return $rc
}

git_add_explicit() { # git_add_explicit <worktree> <path>; a filename is never a pathspec glob
  GIT_LITERAL_PATHSPECS=1 git -C "${1:?}" add -- "${2:?}"
}

station_commit_push_pr() { # station 6; returns 2 when there is nothing to commit
  local list path staged=0 msg title prbody leftover
  list="$TICKET_DIR/changed-files.nul"

  # Unstage first, then list. Only the explicit, filtered files below may be
  # committed; nothing a worker or an interrupted run left in the index leaks in.
  if ! git -C "$WORKTREE" reset -q >>"$LOG" 2>&1; then
    STATUS_REASON="git reset (unstage) failed in the worktree"
    return 1
  fi
  if ! collect_files "$list"; then
    STATUS_REASON="could not list changed files in the worktree"
    return 1
  fi
  if [ ! -s "$list" ]; then
    NOCHANGE_TEXT="The worker left no changes in the worktree."
    return 2
  fi

  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    if path_is_ignored "$path"; then
      log "not staging ignored path: $path"
      continue
    fi
    if [ -d "$WORKTREE/$path" ]; then
      STATUS_REASON="refusing to stage directory '$path'"
      return 1
    fi
    if ! git_add_explicit "$WORKTREE" "$path" >>"$LOG" 2>&1; then
      STATUS_REASON="git add failed for '$path'"
      return 1
    fi
    staged=1
  done <"$list"

  # A tracked file changed outside the staged set (e.g. a tracked .env that the
  # exclusion filter refuses to commit) would make the commit differ from the
  # tree the checks ran on. Never commit in that state.
  if ! leftover=$(git -C "$WORKTREE" diff --name-only 2>>"$LOG"); then
    STATUS_REASON="could not inspect uncommitted tracked changes"
    return 1
  fi
  if [ -n "$leftover" ]; then
    STATUS_REASON="tracked changes would be left out of the commit (checks ran on a different tree): $(printf '%s' "$leftover" | head -n 5 | tr '\n' ' ')"
    return 1
  fi

  if [ "$staged" -eq 0 ] || git -C "$WORKTREE" diff --cached --quiet 2>/dev/null; then
    NOCHANGE_TEXT="Only ignored files or no changes to commit."
    return 2
  fi

  msg=""
  if [ -s "$OUT_DIR/commit.txt" ]; then
    msg=$(head -n 1 "$OUT_DIR/commit.txt" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  fi
  [ -n "$msg" ] || msg="Fix #$N: $ISSUE_TITLE"
  if ! git -C "$WORKTREE" commit -m "$msg" >>"$LOG" 2>&1; then
    STATUS_REASON="git commit failed"
    return 1
  fi
  # the committed tree must be exactly the tree that was checked
  if [ -n "$(git -C "$WORKTREE" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    STATUS_REASON="worktree is dirty after commit; the committed tree is not what was checked"
    return 1
  fi

  title=""
  if [ -s "$OUT_DIR/title.txt" ]; then
    title=$(head -n 1 "$OUT_DIR/title.txt" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  fi
  [ -n "$title" ] || title="$msg"

  log "git push -u origin $BRANCH"
  if ! git -C "$WORKTREE" push -u origin "$BRANCH" >>"$LOG" 2>&1; then
    STATUS_REASON="git push was rejected or failed (never force-pushed)"
    return 1
  fi

  if [ -z "$PR" ]; then
    prbody="$TICKET_DIR/pr-body.md"
    {
      cat "$TICKET_DIR/receipt.md"
      printf '\nCloses #%s\n' "$N"
    } >"$prbody"
    if ! gh pr create -R "$SLUG" --base "$BASE" --head "$BRANCH" \
      --title "$title" --body-file "$prbody" >>"$LOG" 2>&1; then
      STATUS_REASON="gh pr create failed"
      return 1
    fi
    if ! PR=$(gh pr list -R "$SLUG" --head "$BRANCH" --state open --json number -q '.[0].number // empty' 2>>"$LOG"); then
      STATUS_REASON="could not look up the PR after create"
      return 1
    fi
    if [ -z "$PR" ]; then
      STATUS_REASON="PR was not found after create"
      return 1
    fi
    log "opened PR #$PR"
  else
    log "pushed to existing PR #$PR"
  fi
  return 0
}

station_review() { # station 7: one retry, then station 10 via return 1
  local reviewer
  choose_reviewer
  reviewer=$REVIEWER_CHOICE_CMD
  log "reviewer: $REVIEWER_CHOICE_LABEL"
  stamp review start
  if review_pr "$PR" "$SLUG" "$PROJECT" "$BASE" "$reviewer"; then
    stamp review end
    return 0
  fi
  if [ "${REVIEW_RATE_LIMITED:-0}" = "1" ]; then
    stamp review stuck
    STATUS_REASON="reviewer was rate limited for more than 6 hours"
    return 1
  fi
  warn "review failed: $REVIEW_ERR; retrying once"
  sleep 5
  if review_pr "$PR" "$SLUG" "$PROJECT" "$BASE" "$reviewer"; then
    stamp review end
    return 0
  fi
  stamp review stuck
  if [ "${REVIEW_KILLED:-0}" = "1" ]; then
    STATUS_REASON="reviewer ${SLOT_FAIL_TEXT:-was killed as hung}"
    return 1
  fi
  STATUS_REASON="review failed: $REVIEW_ERR"
  return 1
}

choose_reviewer() { # sets REVIEWER_CHOICE_CMD/LABEL; risk is computed first, fail closed
  if ticket_is_risky; then
    if [ -n "${RISKY_REVIEWER_CMD:-}" ]; then
      REVIEWER_CHOICE_CMD=$RISKY_REVIEWER_CMD
      REVIEWER_CHOICE_LABEL="risky ($RISKY_FILE); RISKY_REVIEWER_CMD"
    else
      REVIEWER_CHOICE_CMD=$REVIEWER_CMD
      REVIEWER_CHOICE_LABEL="risky ($RISKY_FILE); RISKY_REVIEWER_CMD unset, REVIEWER_CMD"
    fi
  else
    REVIEWER_CHOICE_CMD=$REVIEWER_CMD
    REVIEWER_CHOICE_LABEL="routine; REVIEWER_CMD"
  fi
  return 0
}

ticket_is_risky() { # station 9 test; any failed git call means risky
  local tmp path risky=1
  if printf '%s\n' "$ISSUE_BODY" | grep -qiE '^[[:space:]]*Risky:[[:space:]]*yes[[:space:]]*$'; then
    RISKY_FILE="issue body says Risky: yes"
    return 0
  fi
  tmp="${TICKET_DIR:-${TMPDIR:-/tmp}}/.belt-risk.$$.$RANDOM"
  # -z keeps raw, unquoted names, so Unicode/control characters cannot hide
  if ! git -C "$WORKTREE" diff --name-only -z --no-renames "origin/$BASE...HEAD" >"$tmp" 2>>"$LOG"; then
    rm -f "$tmp"
    RISKY_FILE="could not compute changed files (git diff failed)"
    return 0
  fi
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    if is_risky_path "$path"; then
      RISKY_FILE="risky path $path"
      risky=0
      break
    fi
  done <"$tmp"
  rm -f "$tmp"
  return $risky
}

ci_state_of() { # ci_state_of <pr>; pass|fail|pending|none|unknown
  local out rc
  out=$(gh pr checks "$1" -R "$SLUG" --json bucket 2>&1)
  rc=$?
  ci_state_from_output "$out" "$rc"
}

ci_state() { ci_state_of "${PR:-}"; }

ci_gate() { # 0 = green/none, 2 = failed, 3 = still pending
  local waited=0 max status
  max=$((CHECK_WAIT_MIN * 60))
  while :; do
    status=$(ci_state) || status="unknown"
    case "$status" in
      pass|none) return 0 ;;
      fail) CI_REASON="remote CI is failing"; return 2 ;;
      unknown) CI_REASON="could not read remote CI status"; return 2 ;;
      pending) : ;;
    esac
    if [ "$waited" -ge "$max" ]; then
      CI_REASON="remote CI still pending after ${CHECK_WAIT_MIN}m"
      return 3
    fi
    sleep 30
    waited=$((waited + 30))
  done
}

station_merge() { # station 8
  local head cur ci_rc
  # local checks: all PASS or SKIPPED
  case "$CHECK_TABLE" in
    *'|FAIL'*)
      STATUS_REASON="local checks are not green"
      return 1
      ;;
  esac
  if [ -z "$REVIEW_SHA" ] || [ "$REVIEW_P1" -ne 0 ]; then
    STATUS_REASON="no clean review for the current head"
    return 1
  fi
  # the review must name the PR's current full head SHA, and the worktree must be that commit
  head=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null) || head=""
  cur=$(gh pr view "$PR" -R "$SLUG" --json headRefOid -q .headRefOid 2>/dev/null) || cur=""
  if [ "$head" != "$REVIEW_SHA" ] || [ "$cur" != "$REVIEW_SHA" ]; then
    STATUS_REASON="head moved since review (review $REVIEW_SHA, worktree ${head:-?}, PR ${cur:-?})"
    return 1
  fi

  ci_gate
  ci_rc=$?
  case "$ci_rc" in
    0) stamp ci end ;;
    *) stamp ci stuck ;;
  esac
  case $ci_rc in
    0) : ;;
    3)
      ticket_handoff "PR #$PR is green locally but remote CI is still pending after ${CHECK_WAIT_MIN}m."
      return $?
      ;;
    *)
      ticket_handoff "PR #$PR has red or unreadable remote CI (${CI_REASON:-unknown}); not merging."
      return $?
      ;;
  esac

  log "gh pr merge $PR --squash --match-head-commit $REVIEW_SHA"
  if ! gh pr merge "$PR" -R "$SLUG" --squash --match-head-commit "$REVIEW_SHA" >>"$LOG" 2>&1; then
    sleep 5
    if ! gh pr merge "$PR" -R "$SLUG" --squash --match-head-commit "$REVIEW_SHA" >>"$LOG" 2>&1; then
      STATUS_REASON="gh pr merge failed"
      return 1
    fi
  fi
  MERGED=1
  if ! issue_relabel "" "$(claim_label)" "remove $(claim_label) after merge"; then
    return 1
  fi
  gh issue comment "$N" -R "$SLUG" --body "Merged in PR #$PR." >>"$LOG" 2>&1 \
    || warn "could not comment merge"
  TICKET_FINISHED=1
  log "ticket #$N merged in PR #$PR"
  return 0
}

ticket_ship() { # stations 9 + 8 after a clean review
  process_owner_steps || warn "some owner steps could not be opened"
  if ticket_is_risky; then
    ticket_risky_stop
    return $?
  fi
  station_merge
}

# --------------------------------------------------------------- outcomes ---

issue_relabel() { # issue_relabel <add-label|''> <remove-label|''> <context>; retries, then loud
  local add=${1:-} remove=${2:-} ctx=${3:-relabel} attempt=0 rc=0
  if [ -z "$add" ] && [ -z "$remove" ]; then return 0; fi
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    if [ -n "$add" ] && [ -n "$remove" ]; then
      gh issue edit "$N" -R "$SLUG" --add-label "$add" --remove-label "$remove" >>"$LOG" 2>&1 && return 0
    elif [ -n "$add" ]; then
      gh issue edit "$N" -R "$SLUG" --add-label "$add" >>"$LOG" 2>&1 && return 0
    else
      gh issue edit "$N" -R "$SLUG" --remove-label "$remove" >>"$LOG" 2>&1 && return 0
    fi
    rc=$?
    [ "$attempt" -lt 3 ] && sleep 2
  done
  TERMINAL_RELABEL_FAILED=1
  warn "CRITICAL: could not relabel issue #$N ($ctx) after 3 attempts (last exit $rc); it may still be $(claim_label)"
  create_owner_issue "$SLUG" "Fix labels on issue #$N ($ctx)" "Needed for #$N" \
    || warn "CRITICAL: could not open a needs-owner issue for the relabel failure on #$N"
  return 1
}

process_owner_steps() {
  local line title seen rc=0
  [ -f "$OUT_DIR/owner-steps.txt" ] || return 0
  seen="$TICKET_DIR/owner-steps.done"
  touch "$seen" 2>/dev/null || true
  while IFS= read -r line || [ -n "$line" ]; do
    title=$(truncate_str "$(trim_str "$line")" 80)
    [ -n "$title" ] || continue
    if grep -Fxq -- "$title" "$seen" 2>/dev/null; then continue; fi
    if create_owner_issue "$SLUG" "$title" "Needed for #$N"; then
      printf '%s\n' "$title" >>"$seen" 2>/dev/null \
        || warn "could not record owner step: $title"
    else
      # leave it unmarked so a later run can retry the creation
      warn "owner step not recorded after creation failure: $title"
      rc=1
    fi
  done <"$OUT_DIR/owner-steps.txt"
  return $rc
}

ticket_nochange() { # stop after nochange.txt / nothing to stage
  local text=${1:-No change needed.}
  log "nochange for #$N: $text"
  process_owner_steps || true
  gh issue comment "$N" -R "$SLUG" --body "$(printf '%s\n' "$text" | head -n 5)" >>"$LOG" 2>&1 \
    || warn "could not comment nochange"
  NOCHANGE=1
  if issue_relabel stuck "$(claim_label)" "mark stuck after nochange"; then
    TICKET_FINISHED=1
    return 0
  fi
  return 1
}

ticket_risky_stop() { # station 9
  log "risky PR #$PR: $RISKY_FILE; handing to lead"
  process_owner_steps || true
  gh pr comment "$PR" -R "$SLUG" --body "Not merging: $RISKY_FILE." >>"$LOG" 2>&1 \
    || warn "could not comment on PR #$PR"
  gh pr edit "$PR" -R "$SLUG" --add-label needs-lead >>"$LOG" 2>&1 \
    || warn "could not label PR #$PR"
  gh issue comment "$N" -R "$SLUG" --body "Needs a human: $RISKY_FILE. PR #$PR is left open for review." >>"$LOG" 2>&1 \
    || warn "could not comment on issue #$N"
  if issue_relabel needs-lead "$(claim_label)" "hand risky work to the lead"; then
    TICKET_FINISHED=1
    return 0
  fi
  return 1
}

ticket_handoff() { # needs-lead, PR stays open
  local why=${1:-needs a lead}
  log "handoff #$N: $why"
  process_owner_steps || true
  gh pr edit "$PR" -R "$SLUG" --add-label needs-lead >>"$LOG" 2>&1 || true
  gh issue comment "$N" -R "$SLUG" --body "$why" >>"$LOG" 2>&1 || warn "could not comment"
  if issue_relabel needs-lead "$(claim_label)" "hand off to the lead"; then
    TICKET_FINISHED=1
    return 0
  fi
  return 1
}

maybe_owner_issue_for_auth() {
  if tail -n 60 "$LOG" 2>/dev/null | grep -qiE 'gh auth login|not logged in|authentication failed|HTTP 401'; then
    create_owner_issue "$SLUG" "Authenticate gh CLI for $SLUG" "Needed for #$N" || true
  fi
}

ticket_fail() { # station 10
  local reason=${1:-unknown failure} body
  log "FAILED #$N: $reason"
  process_owner_steps || true
  maybe_owner_issue_for_auth
  body="belt stopped: $reason
Log: $LOG"
  [ -n "${STATUS_REASON:-}" ] && body="$body
Detail: $STATUS_REASON"
  gh issue comment "$N" -R "$SLUG" --body "$(printf '%s\n' "$body" | head -n 5)" >>"$LOG" 2>&1 \
    || warn "could not comment failure"
  if issue_relabel stuck "$(claim_label)" "mark stuck after failure"; then
    TICKET_FINISHED=1
  fi
  return 1
}

# ------------------------------------------------------------------- flow ---

work_and_check() { # station 3+4, one retry of station 3 on a check failure
  local extra=$1 check_extra
  station_implement "$extra" || return 1
  [ -f "$OUT_DIR/nochange.txt" ] && return 0
  station_checks && return 0
  check_extra="The check '$CHECK_FAILED' failed. Last 30 log lines:
$(tail -n 30 "$TICKET_DIR/check-$CHECK_FAILED.log" 2>/dev/null)"
  warn "checks failed ($CHECK_FAILED); retrying the worker once"
  station_implement "$check_extra" || return 1
  [ -f "$OUT_DIR/nochange.txt" ] && return 0
  station_checks
}

push_pr_or_stop() { # 0 continue, 3 ticket finished (nochange), 1 stop/failed
  station_commit_push_pr
  case $? in
    0) return 0 ;;
    2) ticket_nochange "${NOCHANGE_TEXT:-No change needed.}" || return 1; return 3 ;;
    *) ticket_fail "${STATUS_REASON:-commit/push/PR failed}"; return 1 ;;
  esac
}

push_and_decide() { # 0 = continue to review, 1 = ticket finished, 2 = failed
  local rc
  push_pr_or_stop
  rc=$?
  case "$rc" in
    0) return 0 ;;
    3) return 1 ;;
    *) return 2 ;;
  esac
}

review_or_stop() {
  station_review || { ticket_fail "${STATUS_REASON:-review failed}"; return 1; }
  return 0
}

ticket_flow() {
  local extra fixrc
  station_claim || { ticket_fail "could not claim issue"; return 1; }
  load_issue || { ticket_fail "${STATUS_REASON:-could not read issue}"; return 1; }
  station_worktree || { ticket_fail "${STATUS_REASON:-worktree setup failed}"; return 1; }

  if [ "$RESUME_PR" = "1" ]; then
    # station 2 said skip to 7, but the merge gate needs real local results.
    if ! station_checks; then
      extra="The check '$CHECK_FAILED' failed. Last 30 log lines:
$(tail -n 30 "$TICKET_DIR/check-$CHECK_FAILED.log" 2>/dev/null)"
      work_and_check "$extra" || { ticket_fail "${STATUS_REASON:-checks failed on resume}"; return 1; }
      [ -f "$OUT_DIR/nochange.txt" ] && { ticket_nochange "$(cat "$OUT_DIR/nochange.txt")"; return $?; }
      station_receipt
      push_and_decide
      case $? in
        0) ;;
        1) return 0 ;;
        *) return 1 ;;
      esac
    fi
  else
    work_and_check "" || { ticket_fail "${STATUS_REASON:-worker failed}"; return 1; }
    [ -f "$OUT_DIR/nochange.txt" ] && { ticket_nochange "$(cat "$OUT_DIR/nochange.txt")"; return $?; }
    station_receipt
    push_and_decide
    case $? in
      0) ;;
      1) return 0 ;;
      *) return 1 ;;
    esac
  fi

  review_or_stop || return 1

  # one fix round for P1 findings, then re-run 4-7
  if [ "$REVIEW_P1" -gt 0 ]; then
    FIX_ROUND=1
    log "review has $REVIEW_P1 P1 finding(s); one fix round"
    extra=$(cat "$TICKET_DIR/findings.txt" 2>/dev/null)
    stamp fix start
    work_and_check "$extra" || { stamp fix stuck; ticket_fail "${STATUS_REASON:-fix round failed}"; return 1; }
    [ -f "$OUT_DIR/nochange.txt" ] && { stamp fix end; ticket_nochange "$(cat "$OUT_DIR/nochange.txt")"; return $?; }
    station_receipt
    push_and_decide
    fixrc=$?
    case "$fixrc" in
      0) stamp fix end ;;
      1) stamp fix end; return 0 ;;
      *) stamp fix stuck; return 1 ;;
    esac
    review_or_stop || return 1
    if [ "$REVIEW_P1" -gt 0 ]; then
      ticket_fail "review still reports P1 findings after one fix round"
      return 1
    fi
  fi

  ticket_ship || {
    # a merged PR or a loud terminal-relabel failure must not be relabelled again
    if [ "${TERMINAL_RELABEL_FAILED:-0}" = "1" ] || [ "${MERGED:-0}" = "1" ]; then
      return 1
    fi
    ticket_fail "${STATUS_REASON:-merge gate failed}"
    return 1
  }
  return 0
}

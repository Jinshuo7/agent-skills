#!/usr/bin/env bash
# lib/suite.sh - the full project suite on the base branch, once per batch.
# Requires: PROJECT, SLUG, FULL_SUITE_CMD, SUITE_TIMEOUT_MIN, BELT_HOME.

if [ -z "${BELT_ROOT:-}" ]; then
  BELT_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd) || BELT_ROOT=""
fi

suite_state_dir() { state_dir_for "${SLUG:?}"; }
suite_state_file() { printf '%s/suite.state\n' "$(suite_state_dir)"; }
suite_log_path() { printf '%s/suite.log\n' "$(suite_state_dir)"; }

suite_state_read() { # sets SUITE_RESULT SUITE_SHA SUITE_GREEN SUITE_UNKNOWN
  SUITE_RESULT=""
  SUITE_SHA=""
  SUITE_GREEN=""
  SUITE_UNKNOWN=0
  local f line k v
  f=$(suite_state_file)
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    k=${line%%=*}
    v=${line#*=}
    case "$k" in
      result) SUITE_RESULT=$v ;;
      sha) SUITE_SHA=$v ;;
      green) SUITE_GREEN=$v ;;
      unknown)
        case "$v" in ''|*[!0-9]*) v=0 ;; esac
        SUITE_UNKNOWN=$v
        ;;
    esac
  done <"$f"
  return 0
}

suite_state_write() { # <result> <sha> <unknown> <last-green-sha>
  local f tmp
  f=$(suite_state_file)
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 1
  tmp="$f.tmp.$$"
  {
    printf 'result=%s\n' "${1:-}"
    printf 'sha=%s\n' "${2:-}"
    printf 'unknown=%s\n' "${3:-0}"
    printf 'green=%s\n' "${4:-}"
  } >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null
}

suite_issue_number() { # the issue opened for the current red SHA, if any
  local f
  f="$(suite_state_dir)/suite.issue"
  [ -f "$f" ] || return 0
  tr -d '[:space:]' <"$f" 2>/dev/null || true
}

suite_base_sha() { # current origin/<base>, no fetch
  local base
  base=$(base_branch)
  git -C "${PROJECT:?}" rev-parse --verify "origin/$base^{commit}" 2>/dev/null
}

suite_must_pass() { # releases: 0 only when the current base SHA is green
  local basesha
  [ -n "${FULL_SUITE_CMD:-}" ] || return 0
  basesha=$(suite_base_sha) || return 1
  suite_state_read
  [ "$SUITE_RESULT" = "green" ] && [ "$SUITE_SHA" = "$basesha" ]
}

suite_report_red() { # <sha> <log>; opens one stuck issue per red SHA
  local redsha=${1:?} log=${2:?} state reported title body out num
  state=$(suite_state_dir)
  mkdir -p "$state" 2>/dev/null || true
  reported="$state/suite.reported"
  if [ -f "$reported" ] && grep -Fqx -- "$redsha" "$reported" 2>/dev/null; then
    return 0
  fi
  title="Base branch red since $redsha: full suite failed"
  body=$(printf 'The full suite failed on `%s` (log: %s).\n\nLog tail:\n```\n' "$redsha" "$log"
    tail -n 40 "$log" 2>/dev/null
    printf '```\n')
  if out=$(gh issue create -R "$SLUG" --title "$title" --label stuck --body "$body" 2>>"$log"); then
    printf '%s\n' "$redsha" >>"$reported" 2>/dev/null || true
    num=$(printf '%s' "$out" | sed -n 's#.*/issues/\([0-9][0-9]*\).*#\1#p' | tail -n 1)
    if [ -n "$num" ]; then
      printf '%s\n' "$num" >"$state/suite.issue" 2>/dev/null || true
    fi
    log "opened issue ${num:-?} for the red base $redsha"
  else
    warn "could not open the red-base issue for $redsha"
  fi
  return 0
}

suite_run() { # one foreground suite run; owns suite.lock while it runs
  local state log swt base basesha rc tested prev unknown
  [ -n "${FULL_SUITE_CMD:-}" ] || return 0
  state=$(suite_state_dir)
  mkdir -p "$state" 2>/dev/null || return 1
  log=$(suite_log_path)
  if ! acquire_lock "$state/suite.lock" 0; then
    log_file "suite: another run is already live"
    return 0
  fi
  : >"$log" 2>/dev/null || true
  base=$(base_branch)
  if ! git -C "$PROJECT" fetch origin "$base" >>"$log" 2>&1; then
    warn "suite: git fetch origin $base failed"
    release_lock "$state/suite.lock"
    return 1
  fi
  if ! basesha=$(git -C "$PROJECT" rev-parse --verify "origin/$base^{commit}" 2>/dev/null); then
    warn "suite: could not read origin/$base"
    release_lock "$state/suite.lock"
    return 1
  fi
  suite_state_read
  if [ "$SUITE_SHA" = "$basesha" ] && { [ "$SUITE_RESULT" = "green" ] || [ "$SUITE_RESULT" = "red" ]; }; then
    release_lock "$state/suite.lock"
    return 0
  fi
  swt="$state/suite-worktree"
  if ! ensure_under_belt_home "$swt"; then
    release_lock "$state/suite.lock"
    return 1
  fi
  git -C "$PROJECT" worktree remove --force "$swt" >>"$log" 2>&1 || true
  rm -rf "$swt"
  if ! git -C "$PROJECT" worktree add --detach "$swt" "origin/$base" >>"$log" 2>&1; then
    warn "suite: could not create a clean worktree of origin/$base"
    release_lock "$state/suite.lock"
    return 1
  fi
  # green is recorded for the SHA the suite actually tested, never for a later one
  tested=$(git -C "$swt" rev-parse HEAD 2>/dev/null) || tested=$basesha
  local TIMINGS_DIR="$state" TIMINGS_ID="batch"
  stamp batch-ci start
  (
    cd "$swt" || exit 1
    run_with_timeout "$(belt_scaled_seconds $((SUITE_TIMEOUT_MIN * 60)))" \
      guard_exec check "$swt" "$FULL_SUITE_CMD"
  ) >>"$log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then stamp batch-ci end; else stamp batch-ci stuck; fi
  git -C "$PROJECT" worktree remove --force "$swt" >>"$log" 2>&1 || rm -rf "$swt"

  prev=${SUITE_UNKNOWN:-0}
  case "$rc" in
    0)
      suite_state_write green "$tested" 0 "$tested"
      log "full suite green at $tested"
      ;;
    124)
      unknown=$((prev + 1))
      suite_state_write unknown "$tested" "$unknown" "${SUITE_GREEN:-}"
      warn "full suite timed out after ${SUITE_TIMEOUT_MIN} min (unknown run $unknown); no red issue, no bisect"
      if [ "$unknown" -eq 2 ]; then
        owner_notify_once "$state" "suite-unknown" "belt: the full suite for $SLUG timed out twice in a row"
      fi
      ;;
    *)
      suite_state_write red "$tested" 0 "${SUITE_GREEN:-}"
      log "full suite red at $tested (exit $rc)"
      suite_report_red "$tested" "$log"
      ;;
  esac
  release_lock "$state/suite.lock"
  return 0
}

suite_start_detached() { # start if the base moved; never wait for it
  local state
  [ -n "${FULL_SUITE_CMD:-}" ] || return 0
  state=$(suite_state_dir)
  mkdir -p "$state" 2>/dev/null || return 1
  if lock_holder_alive "$state/suite.lock"; then
    log_file "suite: a run is already live"
    return 0
  fi
  if [ "${BELT_SUITE_FOREGROUND:-0}" = "1" ]; then
    suite_run
    return $?
  fi
  nohup env BELT_HOME="$BELT_HOME" bash "$BELT_ROOT/belt" __suite-run "${PROJECT:-}" >>"$state/suite.out" 2>&1 </dev/null &
  log_file "suite: started a run in the background"
  return 0
}

suite_bisect() { # <good> <bad>; prints the culprit SHA, empty if inconclusive
  local good=${1:-} bad=${2:-} state wt runner steps secs used culprit
  [ -n "$good" ] && [ -n "$bad" ] && [ "$good" != "$bad" ] || return 0
  case "$good$bad" in *[!0-9a-f]*) return 0 ;; esac
  [ "${#good}" -eq 40 ] && [ "${#bad}" -eq 40 ] || return 0
  git -C "$PROJECT" merge-base --is-ancestor "$good" "$bad" 2>/dev/null || return 0
  state=$(suite_state_dir)
  mkdir -p "$state" 2>/dev/null || return 0
  wt="$state/bisect.$$.$RANDOM"
  ensure_under_belt_home "$wt" || return 0
  steps="$state/bisect.steps.$$.$RANDOM"
  runner="$state/bisect-run.$$.$RANDOM.sh"
  : >"$steps"
  secs=$(belt_scaled_seconds $((SUITE_TIMEOUT_MIN * 60)))
  {
    printf '#!/usr/bin/env bash\n'
    printf '. "%s/lib/common.sh"\n' "$BELT_ROOT"
    printf 'n=$(cat "%s" 2>/dev/null || echo 0)\n' "$steps"
    printf 'n=$((n + 1))\n'
    printf 'printf "%%s\\n" "$n" >"%s"\n' "$steps"
    printf '[ "$n" -le 12 ] || exit 125\n'
    printf 'cd "%s" || exit 125\n' "$wt"
    printf 'run_with_timeout "%s" guard_exec check "%s" "$FULL_SUITE_CMD"\n' "$secs" "$wt"
  } >"$runner" 2>/dev/null || { rm -f "$steps"; return 0; }
  chmod +x "$runner" 2>/dev/null || true
  if ! git -C "$PROJECT" worktree add --detach "$wt" "$bad" >>"$(suite_log_path)" 2>&1; then
    rm -f "$runner" "$steps"
    return 0
  fi
  export FULL_SUITE_CMD
  (
    trap 'git -C "$wt" bisect reset >/dev/null 2>&1 || true' EXIT INT TERM HUP
    cd "$wt" || exit 1
    git bisect start "$bad" "$good" >/dev/null 2>&1 || exit 1
    git bisect run bash "$runner" >"$state/bisect.log" 2>&1
    used=$(cat "$steps" 2>/dev/null || echo 0)
    case "$used" in ''|*[!0-9]*) used=99 ;; esac
    if [ "$used" -le 12 ]; then
      git rev-parse refs/bisect/bad 2>/dev/null
    fi
  ) >"$state/bisect.out" 2>/dev/null
  rm -f "$runner" "$steps"
  git -C "$PROJECT" worktree remove --force "$wt" >>"$(suite_log_path)" 2>&1 || rm -rf "$wt"
  culprit=$(tail -n 1 "$state/bisect.out" 2>/dev/null | tr -d '[:space:]')
  case "$culprit" in ''|*[!0-9a-f]*) return 0 ;; esac
  [ "${#culprit}" -eq 40 ] || return 0
  [ "$culprit" != "$bad" ] || return 0
  printf '%s\n' "$culprit"
}

suite_culprit_pr() { # <sha>; "#N title" of the PR that introduced it, if any
  local culprit_sha=${1:-}
  [ -n "$culprit_sha" ] || return 0
  gh api "repos/$SLUG/commits/$culprit_sha/pulls" -q '.[0] | "#\(.number) \(.title)"' 2>/dev/null \
    | head -n 1 || true
}

cmd_suite() {
  local must_pass=0 dir="" a
  for a in "$@"; do
    case "$a" in
      --must-pass) must_pass=1 ;;
      *) dir=$a ;;
    esac
  done
  load_config "${dir:-}" || die "could not load config (no belt.conf and BELT_PROJECT not set?)"
  [ -n "${FULL_SUITE_CMD:-}" ] || return 0
  SLUG=$(repo_slug) || die "could not resolve the repo slug (set REPO in belt.conf)"
  if [ "$must_pass" = "1" ]; then
    suite_must_pass || die "the base branch is not green in the full suite"
    log "full suite is green at the current base"
    return 0
  fi
  suite_start_detached
  return 0
}

cmd_suite_run() { # internal: the detached worker (__suite-run <project>)
  local dir=${1:-}
  load_config "$dir" || die "could not load config for the suite run"
  SLUG=$(repo_slug) || die "could not resolve the repo slug for the suite run"
  suite_run
  return 0
}

#!/usr/bin/env bash
# lib/watch.sh - one on-call pass: find stalled work, run the fixer, ping the owner.
# `belt watch` never overlaps: one pass under a mkdir lock. It exits nonzero only
# when it cannot read belt.conf (and then it alerts the owner itself).

watch_restart_text() { # [issue] [placeholder]; TICKET_RESTART_CMD with $BELT_ISSUE filled in
  local issue=${1:-} fallback=${2:-} cmd label
  cmd=${TICKET_RESTART_CMD:-belt run \$BELT_ISSUE}
  label=${issue:-${fallback:-<n>}}
  printf '%s\n' "$cmd" \
    | sed -e "s/\${BELT_ISSUE:-[^}]*}/$label/g" \
          -e "s/\${BELT_ISSUE}/$label/g" \
          -e "s/\\\$BELT_ISSUE/$label/g"
}

watch_playbook() { # the on-call playbook, with the project's own keys
  local body claim extra
  claim=$(claim_label)
  extra=${ONCALL_EXTRA_RULES:-}
  body=$(cat <<'PLAYBOOK'
You are the belt on-call fixer. Work only inside this project checkout and belt state.
Playbook:
- A dead or hung ticket: remove the stuck label from the issue and end with `ONCALL: RESTART <n>` (n is the issue you are handling). Leave `@CLAIM@` alone and kill nothing: this sandbox cannot see processes, so belt stops the old run, clears the label and restarts the ticket outside it. Never run a restart command yourself.
- A conflicted PR (conflict:): merge the base branch into the PR branch (never rebase or force-push), resolve the conflicts, push, then let the run continue; OWNER only if it cannot resolve.
- A remote CI failure: re-run it only when it is an infrastructure failure (runner lost, cancelled, timed out, no test-failure line). Never re-run a real test failure.
- A stale `@CLAIM@` label with no live run (stale:): clear it.
- A red base branch (red:): belt bisects it in the background and comments the culprit; do not run a bisect yourself.
- A normal wait (CI queued or running): change nothing.
@EXTRA@Never merge a risky PR, never force-push, never touch secrets.
Finish with one last line, exactly one of:
ONCALL: FIXED
ONCALL: WAITING
ONCALL: RESTART <n>
ONCALL: OWNER <one sentence>
PLAYBOOK
)
  body=${body//@CLAIM@/$claim}
  if [ -n "$extra" ]; then
    body=${body//@EXTRA@/$extra$'\n'}
  else
    body=${body//@EXTRA@/}
  fi
  printf '%s\n' "$body"
}

watch_state_dir() { state_dir_for "${SLUG:?}"; }
watch_log_path() { printf '%s/watch.log\n' "$(watch_state_dir)"; }
watch_baseline_path() { printf '%s/watch.baseline\n' "$(watch_state_dir)"; }

watch_unloaded_state_dir() { # <project-dir>; state dir a pass uses when belt.conf is unreadable
  local dir=${1:-${BELT_PROJECT:-$PWD}} p home
  p=$(cd -P "$dir" 2>/dev/null && pwd) || p=$dir
  p=$(printf '%s' "$p" | sed -e 's|^/*||' -e 's|/|__|g' -e 's|[^A-Za-z0-9._-]|_|g')
  home=${BELT_HOME:-$HOME/.belt}
  printf '%s/watch-config/%s\n' "${home%/}" "$p"
}

watch_alert_config() { # <project-dir>; osascript directly, at most once an hour
  # OWNER_NOTIFY_CMD lives in belt.conf, which is exactly what could not be read
  local dir=${1:-} state marker now old
  state=$(watch_unloaded_state_dir "$dir")
  marker="$state/config-alert.stamp"
  now=$(date '+%s' 2>/dev/null) || now=0
  old=$(cat "$marker" 2>/dev/null) || old=""
  case "$old" in ''|*[!0-9]*) old=0 ;; esac
  if [ "$now" -gt 0 ] && [ "$old" -gt 0 ] && [ $((now - old)) -lt 3600 ]; then
    return 0
  fi
  mkdir -p "$state" 2>/dev/null || true
  printf '%s\n' "$now" >"$marker" 2>/dev/null || true
  osascript -e "display notification \"belt: watch cannot read belt.conf in $dir\" with title \"belt\"" \
    </dev/null >/dev/null 2>&1 || true
  return 0
}

watch_baselined() { # <n>; 0 = this issue predates the watcher: ignore it for good
  local f
  f=$(watch_baseline_path)
  [ -f "$f" ] || return 1
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  grep -Fxq -- "$1" "$f" 2>/dev/null
}

watch_baseline_write() { # <slug>; snapshot open stuck + needs-owner numbers, prints the count
  local slug=${1:?} f out n l
  f=$(state_dir_for "$slug")/watch.baseline
  mkdir -p "$(dirname "$f")" || return 1
  out=$(
    for l in stuck needs-owner; do
      gh issue list -R "$slug" --state open --label "$l" --limit 200 --json number \
        -q '.[].number' 2>/dev/null || exit 1
    done
  ) || { warn "could not read the open stuck/needs-owner issues of $slug"; return 1; }
  printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | sort -n -u >"$f.tmp" 2>/dev/null \
    && mv -f "$f.tmp" "$f" || { warn "could not write $f"; return 1; }
  n=$(grep -c '' "$f" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

watch_drop_baselined() { # <problems-file>; drop every problem of a baselined issue
  local f b
  f=${1:?} b=$(watch_baseline_path)
  [ -f "$b" ] && [ -s "$b" ] || return 0
  awk -F'\t' -v bf="$b" 'FILENAME == bf { skip[$1] = 1; next } !($2 in skip)' "$b" "$f" \
    >"$f.base" 2>/dev/null && mv -f "$f.base" "$f" 2>/dev/null
  return 0
}

watch_problem_text() { # <key> <issue> <kind>
  local key=${1:-} issue=${2:-} kind=${3:-} rest n stage start
  case "$kind" in
    stuck)
      printf 'Issue #%s is labelled stuck and needs a fix or a clean handoff.\n' "$issue"
      ;;
    lead)
      printf 'Issue #%s has a non-risky PR labelled needs-lead and its CI has not completed green.\n' "$issue"
      ;;
    budget)
      rest=${key#budget:}
      n=${rest%%:*}
      rest=${rest#*:}
      stage=${rest%%:*}
      start=${rest#*:}
      printf 'Issue #%s stage %s has been open since %s, over its BUDGETS budget.\n' \
        "$n" "$stage" "$(belt_fmt_epoch "$start" 2>/dev/null)"
      ;;
    silent)
      printf 'Ticket #%s is live but hung: its process is running (belt checked; `run active` below covers only belt'"'"'s own queue), with no output, no file change and almost no CPU for %s minutes, and its PR has no CI run in progress or queued.\n' \
        "$issue" "${SILENT_MIN:-45}"
      ;;
    stale)
      printf 'Issue #%s is still labelled %s but its ticket has no live holder and nothing touched it for %s minutes: the recovery chain dead-ended. Clear the label if it is done, or end with `ONCALL: RESTART %s` so belt restarts it outside the sandbox.\n' \
        "$issue" "$(claim_label)" "${SILENT_MIN:-45}" "$issue"
      ;;
    conflict)
      printf 'The open belt PR for issue #%s is merge-conflicted and has had no CI run for over %s minutes. GitHub does not start pull_request CI on a conflicted PR, so this is not a wait: merge the base branch into the PR branch, resolve, and push (never rebase or force-push).\n' \
        "$issue" "${CONFLICT_MIN:-10}"
      ;;
    red)
      printf 'The base branch full suite is red at %s (last green %s).\n' "${key#red:}" "${SUITE_GREEN:-unknown}"
      if [ -f "$(watch_state_dir)/bisect.culprit" ]; then
        printf 'Bisect result: %s\n' "$(tr '\n' ' ' <"$(watch_state_dir)/bisect.culprit" 2>/dev/null)"
      fi
      ;;
    *)
      printf 'Problem %s.\n' "$key"
      ;;
  esac
  return 0
}

watch_log_tail() { # <key> <issue> <kind>
  local key=${1:-} issue=${2:-} kind=${3:-} f
  case "$kind" in
    red) f=$(suite_log_path) ;;
    *)
      case "$issue" in ''|0) f="" ;; *) f=$(watch_ticket_log "$issue") || f="" ;; esac
      ;;
  esac
  [ -n "$f" ] && [ -f "$f" ] || return 0
  tail -n 40 "$f" 2>/dev/null || true
}

watch_ticket_log() { # <n>; TICKET_LOG_CMD's path, else belt's own ticket log
  local issue=${1:-} out
  if [ -n "${TICKET_LOG_CMD:-}" ]; then
    out=$(BELT_ISSUE=$issue bash -c "$TICKET_LOG_CMD" </dev/null 2>/dev/null) || return 1
    out=$(printf '%s\n' "$out" | head -n 1)
    case "$out" in
      '~/'*) out="$HOME/${out#\~/}" ;;
    esac
    [ -n "$out" ] || return 1
    printf '%s\n' "$out"
    return 0
  fi
  printf '%s/%s/log\n' "$(watch_state_dir)" "$issue"
}

watch_budget() { # <stage>; minutes from BUDGETS, empty when unset
  local w s v
  for w in ${BUDGETS:-}; do
    s=${w%%=*}
    v=${w#*=}
    [ "$s" = "$1" ] || continue
    case "$v" in ''|*[!0-9]*) return 0 ;; esac
    [ "$v" -gt 0 ] || return 0
    printf '%s\n' "$v"
    return 0
  done
  return 0
}

timings_open_stages() { # <timings-file>; 'stage<TAB>start' for starts with no end/stuck
  awk -F'\t' '
    $3 != "" && ($4 == "start" || $4 == "end" || $4 == "stuck") {
      if ($4 == "start") { start[$3] = $1; open[$3] = 1 }
      else { open[$3] = 0 }
    }
    END { for (s in open) if (open[s]) print s "\t" start[s] }
  ' "${1:-}" 2>/dev/null
}

watch_ticket_probe() { # <n>; 0 when the ticket is alive; sets WATCH_TICKET_PID when known
  local issue=${1:-} out rc pid
  WATCH_TICKET_PID=""
  WATCH_TICKET_PID_FROM=""
  if [ -n "${TICKET_ALIVE_CMD:-}" ]; then
    out=$(BELT_ISSUE=$issue bash -c "$TICKET_ALIVE_CMD" </dev/null 2>/dev/null)
    rc=$?
    [ "$rc" -eq 0 ] || return 1
    # an optional numeric first line is the process tree's root, for CPU sampling
    pid=$(printf '%s\n' "$out" | head -n 1 | tr -d '[:space:]')
    case "$pid" in ''|*[!0-9]*) pid="" ;; esac
    [ -n "$pid" ] && WATCH_TICKET_PID_FROM=cmd
    if [ -z "$pid" ]; then
      pid=$(cat "$(watch_state_dir)/$issue/ticket.lock/pid" 2>/dev/null) || pid=""
      case "$pid" in ''|*[!0-9]*) pid="" ;; esac
    fi
    WATCH_TICKET_PID=$pid
    return 0
  fi
  pid=$(cat "$(watch_state_dir)/$issue/ticket.lock/pid" 2>/dev/null) || return 1
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  WATCH_TICKET_PID=$pid
  WATCH_TICKET_PID_FROM=lock
  return 0
}

watch_ticket_live() { # <n>; TICKET_ALIVE_CMD, else belt's ticket.lock holder test
  watch_ticket_probe "$1"
}

watch_cpu_used() { # <n> <min-gap-secs>; 1 only when two samples show the tree under SILENT_CPU_CS_MIN
  # A hang, not impatience: a hung worker still ticks over (#420 used about 7 cs
  # a minute), so any CPU at all is not proof of work. Only samples at least
  # <gap> old are compared. With nothing to compare there is no evidence of a
  # hang, so the ticket counts as busy and this pass just records a sample.
  local issue=${1:-} gap=${2:-60} dir sample pid cpu prev_pid="" prev_cpu="" prev_epoch="" now
  dir=$(watch_state_dir)
  sample="$dir/watch-cpu.$issue"
  pid=${WATCH_TICKET_PID:-}
  if [ -z "$pid" ]; then
    pid=$(cat "$dir/$issue/ticket.lock/pid" 2>/dev/null) || pid=""
  fi
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  cpu=$(slot_cpu_cs "$pid")
  now=$(date '+%s' 2>/dev/null) || now=0
  if [ -f "$sample" ]; then
    IFS=: read -r prev_pid prev_cpu prev_epoch <"$sample" 2>/dev/null || true
  fi
  printf '%s:%s:%s\n' "$pid" "$cpu" "$now" >"$sample.tmp" 2>/dev/null \
    && mv -f "$sample.tmp" "$sample" 2>/dev/null
  [ "$prev_pid" = "$pid" ] || return 0
  case "$prev_cpu" in ''|*[!0-9]*) return 0 ;; esac
  case "$prev_epoch" in ''|*[!0-9]*) return 0 ;; esac
  [ "$now" -ge "$prev_epoch" ] || return 0
  [ $((now - prev_epoch)) -ge "$gap" ] || return 0
  # the total drops when a child exits, and a child finishing is activity
  [ "$cpu" -ge "$prev_cpu" ] || return 0
  [ $(( (cpu - prev_cpu) * 60 )) -ge $(( ${SILENT_CPU_CS_MIN:-20} * (now - prev_epoch) )) ]
}

watch_run_folders() { # <pid>; the working folders of the run's processes that are inside the project
  local list
  list=$(watch_tree_pids "${1:?}" | paste -sd, -)
  lsof -a -d cwd -Fn -p "$list" 2>/dev/null | sed -n 's/^n//p' | sort -u \
    | while IFS= read -r wd; do
        case "$wd" in "${PROJECT:-/nonexistent}"/*) printf '%s\n' "$wd" ;; esac
      done
}

watch_silent_key() { # <n>; prints silent:<n> or nothing
  # Silent means a hang: the log has not changed for SILENT_MIN, no output file
  # grew, nothing in the work folder changed and the process tree used no CPU
  # since the last pass. Elapsed time alone is never enough.
  local issue=${1:?} dir logf mt now idle wpr wci wd
  dir=$(watch_state_dir)
  watch_ticket_live "$issue" || return 0
  logf=$(watch_ticket_log "$issue") || return 0
  mt=$(file_mtime "$logf") || return 0
  now=$(date '+%s' 2>/dev/null) || return 0
  [ "$now" -ge "$mt" ] || return 0
  idle=$(belt_scaled_seconds $(( ${SILENT_MIN:-45} * 60 )))
  [ $((now - mt)) -ge "$idle" ] || return 0
  [ "$(slot_out_newest_mtime "$dir/$issue")" -le $((now - idle)) ] || return 0
  if [ -n "${TICKET_ALIVE_CMD:-}" ]; then
    # a custom runner's work folder is the log's own folder
    wd=$(dirname "$logf")
  else
    wd="$dir/worktrees/$issue"
  fi
  [ "$(slot_newest_mtime "$wd")" -le $((now - idle)) ] || return 0
  # a custom runner that exposes no pid gives no CPU evidence at all: CPU is
  # unknown, not idle, so treat the ticket as busy instead of guessing silence
  if [ -n "${TICKET_ALIVE_CMD:-}" ] && [ -z "${WATCH_TICKET_PID:-}" ]; then
    return 0
  fi
  # a custom runner's worktree is wherever its processes are working
  if [ -n "${TICKET_ALIVE_CMD:-}" ]; then
    while IFS= read -r wd; do
      [ -n "$wd" ] || continue
      [ "$(slot_newest_mtime "$wd")" -le $((now - idle)) ] || return 0
    done <<EOF
$(watch_run_folders "$WATCH_TICKET_PID")
EOF
  fi
  watch_cpu_used "$issue" "$(belt_scaled_seconds 60)" && return 0
  wpr=$(gh pr list -R "$SLUG" --head "$(belt_branch_for "$issue")" --state open --json number -q '.[0].number // empty' 2>/dev/null) || wpr=""
  if [ -n "$wpr" ]; then
    wci=$(ci_state_of "$wpr" 2>/dev/null) || wci="unknown"
    [ "$wci" = "pending" ] && return 0
    # one key per problem: a conflicted PR is conflict:, never also silent:
    watch_pr_conflicted "$wpr" && return 0
  fi
  printf 'silent:%s\n' "$issue"
}

watch_pr_mergeable_state() { # <pr>; GitHub's mergeable_state, empty when unreadable
  local st
  st=$(gh api "repos/$SLUG/pulls/$1" -q .mergeable_state 2>/dev/null) || return 1
  printf '%s\n' "$st"
}

watch_pr_conflicted() { # <pr>; 0 = dirty (merge-conflicted)
  [ "$(watch_pr_mergeable_state "$1")" = "dirty" ]
}

watch_conflict_key() { # <issue> <pr> <head-sha> [now]; conflict:<n> after CONFLICT_MIN without CI
  # A conflicted PR gets no pull_request CI at all, so "no checks" here is not a
  # wait. Track the first pass that saw this head dirty with no CI, then hand it
  # to the on-call after CONFLICT_MIN so an ordinary just-pushed PR is not flagged.
  local wn=${1:?} pr=${2:?} sha=${3:-} now=${4:-} state dir f old_sha old_epoch
  [ -n "$sha" ] || return 0
  state=$(watch_state_dir)
  dir="$state/conflict-wait"
  f="$dir/$pr"
  if ! watch_pr_conflicted "$pr"; then
    rm -f "$f" 2>/dev/null || true
    return 0
  fi
  [ "$(ci_state_of "$pr" 2>/dev/null)" = "none" ] || {
    rm -f "$f" 2>/dev/null || true
    return 0
  }
  [ -n "$now" ] || now=$(date '+%s' 2>/dev/null) || return 0
  old_sha=""; old_epoch=""
  if [ -f "$f" ]; then
    IFS=$'\t' read -r old_sha old_epoch <"$f" 2>/dev/null || true
  fi
  if [ "$old_sha" != "$sha" ]; then
    mkdir -p "$dir" 2>/dev/null || return 0
    printf '%s\t%s\n' "$sha" "$now" >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" 2>/dev/null
    return 0
  fi
  case "$old_epoch" in ''|*[!0-9]*) return 0 ;; esac
  [ $((now - old_epoch)) -ge "$(belt_scaled_seconds $(( ${CONFLICT_MIN:-10} * 60 )))" ] || return 0
  printf 'conflict:%s\n' "$wn"
}

watch_clear_dead_claim() { # <issue>; a restart of a dead holder must free the issue and its PR
  local issue=${1:-} pr claim
  case "$issue" in ''|*[!0-9]*) return 0 ;; esac
  claim=$(claim_label)
  watch_ticket_live "$issue" && return 0
  issue_is_claimed "$issue" || return 0
  if gh issue edit "$issue" -R "$SLUG" --remove-label "$claim" >>"$(watch_log_path)" 2>&1; then
    log "cleared $claim from issue #$issue before restart"
  else
    warn "could not clear $claim from issue #$issue before restart"
    return 1
  fi
  pr=$(gh pr list -R "$SLUG" --head "$(belt_branch_for "$issue")" --state open --json number -q '.[0].number // empty' 2>/dev/null) || pr=""
  [ -n "$pr" ] || return 0
  # only remove a label the PR actually has: restarting must not fail on a no-op
  if gh pr view "$pr" -R "$SLUG" --json labels -q '.labels[].name' 2>/dev/null \
    | grep -qx -- "$claim"; then
    if gh pr edit "$pr" -R "$SLUG" --remove-label "$claim" >>"$(watch_log_path)" 2>&1; then
      log "cleared $claim from PR #$pr before restarting #$issue"
    else
      warn "could not clear $claim from PR #$pr before restarting #$issue"
      return 1
    fi
  fi
  return 0
}

watch_stale_key() { # <n> [now]; stale:<n> when a claimed ticket has no live holder past SILENT_MIN
  # The dead-end case: the on-call killed a hung holder but the restart failed
  # (or it only said FIXED), so silent: clears while the label stays. Without
  # this key such a ticket would be invisible to the watchdog forever.
  local issue=${1:?} now=${2:-} state lf f mt newest="" idle wd
  state=$(watch_state_dir)
  watch_ticket_live "$issue" && return 0
  [ -n "$now" ] || now=$(date '+%s' 2>/dev/null) || return 0
  if [ -n "${TICKET_ALIVE_CMD:-}" ]; then
    # no ticket.lock needed: the log's mtime and its work folder are the clock
    f=$(watch_ticket_log "$issue") || return 0
    mt=$(file_mtime "$f") || return 0
    newest=$mt
    wd=$(dirname "$f")
    for f in "$wd" "$state/worktrees/$issue"; do
      [ -d "$f" ] || continue
      mt=$(slot_newest_mtime "$f")
      [ "$mt" -gt "$newest" ] && newest=$mt
    done
  else
    lf="$state/$issue/ticket.lock"
    for f in "$lf" "$state/$issue/log"; do
      mt=$(file_mtime "$f") || continue
      [ "$mt" -gt "${newest:-0}" ] && newest=$mt
    done
  fi
  case "$newest" in ''|*[!0-9]*) return 0 ;; esac
  idle=$(belt_scaled_seconds $(( ${SILENT_MIN:-45} * 60 )))
  [ $((now - newest)) -ge "$idle" ] || return 0
  printf 'stale:%s\n' "$issue"
}

watch_issue_is_risky() { # <n>; fail closed
  local body
  body=$(gh issue view "$1" -R "$SLUG" --json body -q .body 2>/dev/null) || return 0
  printf '%s\n' "$body" | grep -qiE '^[[:space:]]*Risky:[[:space:]]*yes[[:space:]]*$'
}

watch_pr_is_risky() { # <issue> <sha>; 0 = risky (uncomputable risk is risky)
  local wn=${1:?} whead=${2:-} base tmp p
  watch_issue_is_risky "$wn" && return 0
  [ -n "$whead" ] || return 0
  base=$(base_branch)
  git -C "$PROJECT" cat-file -e "$whead^{commit}" 2>/dev/null \
    || git -C "$PROJECT" fetch origin "$whead" >/dev/null 2>&1 || true
  git -C "$PROJECT" cat-file -e "$whead^{commit}" 2>/dev/null || return 0
  tmp="${TMPDIR:-/tmp}/belt-watch-risk.$$.$RANDOM"
  if ! git -C "$PROJECT" diff --name-only -z --no-renames "origin/$base...$whead" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    if is_risky_path "$p"; then
      rm -f "$tmp"
      return 0
    fi
  done <"$tmp"
  rm -f "$tmp"
  return 1
}

watch_pr_for_issue() { # <n>; prints "pr<TAB>sha" for an open ticket branch PR
  local wn=${1:?} out
  out=$(gh pr list -R "$SLUG" --head "$(belt_branch_for "$wn")" --state open --json number,headRefOid \
    -q '.[0] | "\(.number)\t\(.headRefOid)"' 2>/dev/null) || out=""
  printf '%s\n' "$out" | head -n 1
}

watch_runner_tickets() { # "number<TAB>labels": claimed issues, and runs still alive that lost the label
  # The label can go while the run lives (on-call removed it from #420, and the
  # hung worker went unseen for 7 hours), so a ticket stays on this list until
  # its run has ended.
  local f claimed n keep
  f="$(watch_state_dir)/watch.tracked"
  claimed=$(watch_claimed_issues)
  [ -z "$claimed" ] || printf '%s\n' "$claimed"
  keep=$(printf '%s\n' "$claimed" | cut -f1)
  if [ -f "$f" ]; then
    while IFS= read -r n || [ -n "$n" ]; do
      case "$n" in ''|*[!0-9]*) continue ;; esac
      printf '%s\n' "$keep" | grep -Fxq -- "$n" && continue
      watch_ticket_live "$n" || continue
      printf '%s\t\n' "$n"
      keep=$(printf '%s\n%s' "$keep" "$n")
    done <"$f"
  fi
  printf '%s\n' "$keep" | sed '/^$/d' >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f" 2>/dev/null
  return 0
}

watch_claimed_issues() { # open issues with CLAIM_LABEL: "number<TAB>labels"
  gh issue list -R "$SLUG" --state open --label "$(claim_label)" --limit 100 --json number,labels 2>/dev/null \
    | jq -r '.[] | "\(.number)\t\([.labels[].name] | join(","))"' 2>/dev/null
}

watch_ensure_labels() { # create the labels watch reads, so install is not required
  local l
  [ -n "${SLUG:-}" ] || return 0
  for l in "$(claim_label)" stuck needs-lead needs-owner; do
    gh label create "$l" -R "$SLUG" --color ededed --description "managed by belt" --force \
      >/dev/null 2>&1 || true
  done
  return 0
}

watch_collect() { # <outfile>; key<TAB>issue<TAB>kind lines
  local out=${1:?} state wn wpr whead tf stage start budget now key lf
  state=$(watch_state_dir)
  : >"$out" 2>/dev/null || return 1
  now=$(date '+%s' 2>/dev/null) || now=0

  # issues labelled stuck
  gh issue list -R "$SLUG" --state open --label stuck --limit 100 --json number 2>/dev/null \
    | jq -r '.[] | "stuck:\(.number)\t\(.number)\tstuck"' 2>/dev/null >>"$out" || true

  # needs-lead on a NON-risky PR
  gh issue list -R "$SLUG" --state open --label needs-lead --limit 100 --json number 2>/dev/null \
    | jq -r '.[].number' 2>/dev/null | while IFS= read -r wn || [ -n "$wn" ]; do
        [ -n "$wn" ] || continue
        wpr=$(watch_pr_for_issue "$wn")
        [ -n "$wpr" ] || continue
        whead=${wpr#*$'\t'}
        wpr=${wpr%%$'\t'*}
        watch_pr_is_risky "$wn" "$whead" && continue
        printf 'lead:%s\t%s\tlead\n' "$wn" "$wn" >>"$out"
      done

  # an open stage over its BUDGETS budget
  for tf in "$state"/*/timings.tsv; do
    [ -f "$tf" ] || continue
    wn=$(basename "$(dirname "$tf")")
    case "$wn" in ''|*[!0-9]*) continue ;; esac
    timings_open_stages "$tf" | while IFS=$'\t' read -r stage start || [ -n "$stage" ]; do
      [ -n "$stage" ] || continue
      budget=$(watch_budget "$stage")
      case "$budget" in ''|*[!0-9]*) continue ;; esac
      start=${start%%.*}
      case "$start" in ''|*[!0-9]*) continue ;; esac
      [ $((now - start)) -gt $((budget * 60)) ] || continue
      printf 'budget:%s:%s:%s\t%s\tbudget\n' "$wn" "$stage" "$start" "$wn" >>"$out"
    done
  done

  # a live ticket whose log went quiet while no CI run is in progress or queued
  if [ -n "${TICKET_ALIVE_CMD:-}" ]; then
    # a project with its own runner may have no ticket.lock: its claimed issues
    # are the ticket list
    watch_runner_tickets \
      | while IFS=$'\t' read -r wn wlabels || [ -n "$wn" ]; do
          [ -n "$wn" ] || continue
          case ",$wlabels," in
            *,stuck,*|*,needs-lead,*|*,needs-owner,*) continue ;;
          esac
          key=$(watch_silent_key "$wn")
          [ -n "$key" ] && printf '%s\t%s\tsilent\n' "$key" "$wn" >>"$out"
        done
  else
    for lf in "$state"/*/ticket.lock; do
      [ -e "$lf" ] || continue
      wn=$(basename "$(dirname "$lf")")
      case "$wn" in ''|*[!0-9]*) continue ;; esac
      key=$(watch_silent_key "$wn")
      [ -n "$key" ] && printf '%s\t%s\tsilent\n' "$key" "$wn" >>"$out"
    done
  fi

  # a claimed ticket with no live holder past SILENT_MIN: the dead-end where a
  # kill or restart went wrong and belt's own failure path never ran
  watch_claimed_issues \
    | while IFS=$'\t' read -r wn wlabels || [ -n "$wn" ]; do
        [ -n "$wn" ] || continue
        # a terminal label means belt already handed this one off
        case ",$wlabels," in
          *,stuck,*|*,needs-lead,*|*,needs-owner,*) continue ;;
        esac
        key=$(watch_stale_key "$wn" "$now")
        [ -n "$key" ] && printf '%s\t%s\tstale\n' "$key" "$wn" >>"$out"
      done

  # a conflicted PR whose head has had no CI run past CONFLICT_MIN: not a wait
  gh pr list -R "$SLUG" --state open --limit 100 --json number,headRefName,headRefOid 2>/dev/null \
    | jq -r --arg p "$(branch_prefix)" '.[] | select(.headRefName | startswith($p)) | "\(.number)\t\(.headRefName | ltrimstr($p))\t\(.headRefOid)"' 2>/dev/null \
    | while IFS=$'\t' read -r wpr wn whead || [ -n "$wpr" ]; do
        [ -n "$wpr" ] || continue
        case "$wn" in ''|*[!0-9]*) continue ;; esac
        key=$(watch_conflict_key "$wn" "$wpr" "$whead" "$now")
        [ -n "$key" ] && printf '%s\t%s\tconflict\n' "$key" "$wn" >>"$out"
      done

  # a red base branch
  suite_state_read
  if [ "$SUITE_RESULT" = "red" ] && [ -n "$SUITE_SHA" ]; then
    printf 'red:%s\t0\tred\n' "$SUITE_SHA" >>"$out"
  fi
  sort -u "$out" -o "$out" 2>/dev/null || true
  return 0
}

oncall_attempt_file() { printf '%s/oncall-attempts/%s\n' "$(watch_state_dir)" "${1:?}"; }

oncall_dir() { # <key>; per-problem directory under the state dir
  printf '%s/oncall/%s\n' "$(watch_state_dir)" "$(printf '%s' "${1:?}" | tr ':/ ' '___')"
}

oncall_restart_issue() { # <answer-file>; the n of a last-line ONCALL: RESTART <n>, empty otherwise
  local last n
  last=$(last_nonempty_line "${1:-}")
  case "$last" in
    "ONCALL: RESTART "*) n=${last#ONCALL: RESTART } ;;
    *) return 0 ;;
  esac
  n=$(trim_str "$n")
  case "$n" in
    ''|*[!0-9]*) return 0 ;;
  esac
  printf '%s\n' "$n"
}

oncall_verdict_of() { # <answer-file>; fixed|waiting|restart|owner|none
  local last n
  last=$(last_nonempty_line "${1:-}")
  case "$last" in
    "ONCALL: FIXED") printf 'fixed\n' ;;
    "ONCALL: WAITING") printf 'waiting\n' ;;
    "ONCALL: RESTART "*)
      n=$(oncall_restart_issue "${1:-}")
      [ -n "$n" ] && printf 'restart\n' || printf 'none\n'
      ;;
    "ONCALL: OWNER "*) printf 'owner\n' ;;
    *) printf 'none\n' ;;
  esac
}

oncall_attempts() { # <issue>; how many on-call restarts ran for it
  local f n
  f=$(oncall_attempt_file "$1")
  [ -f "$f" ] || { printf '0\n'; return 0; }
  n=$(grep -c '' "$f" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

oncall_attempt_add() { # <issue>
  local f
  f=$(oncall_attempt_file "$1")
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  printf '%s\n' "$(date '+%s' 2>/dev/null || echo 0)" >>"$f" 2>/dev/null || true
}

oncall_run_problem() { # <key> <issue> <kind>; one fixer call, one at a time
  local key=${1:?} issue=${2:-} kind=${3:-} state dir prompt out stdoutf answer last rc
  local problem logtail status verdict sentence title tries reason restart_issue
  state=$(watch_state_dir)
  dir=$(oncall_dir "$key")
  mkdir -p "$dir" 2>/dev/null || return 0
  problem=$(watch_problem_text "$key" "$issue" "$kind")
  logtail=$(watch_log_tail "$key" "$issue" "$kind")

  # at most two restarts per issue; the third time the owner takes over.
  # The call that decides a restart is counted before it runs, so every
  # executed restart is bounded by this same per-issue cap.
  if [ -n "$issue" ] && [ "$issue" != "0" ]; then
    tries=$(oncall_attempts "$issue")
    if [ "$tries" -ge 2 ]; then
      reason=$(printf '%s' "$problem" | head -n 1)
      title=$(truncate_str "$(trim_str "#$issue keeps failing: $reason")" 80)
      create_owner_issue "$SLUG" "$title" "Needed for #$issue" || true
      owner_notify_once "$state" "owner:$title" "belt: #$issue keeps failing; it needs an owner"
      return 0
    fi
    oncall_attempt_add "$issue"
  fi

  BELT_PROJECT=$PROJECT
  status=$(cmd_status 2>/dev/null) || status=""
  prompt="$dir/prompt.txt"
  {
    printf '%s\n\n' "$problem"
    printf 'Log tail (last 40 lines):\n%s\n\n' "${logtail:-none}"
    printf 'belt status:\n%s\n\n' "${status:-unavailable}"
    [ -n "${BELT_DRILL_NOTE:-}" ] && printf '%s\n\n' "$BELT_DRILL_NOTE"
    printf '%s\n' "$(watch_playbook)"
  } >"$prompt" 2>/dev/null || return 0
  out="$dir/verdict.txt"
  stdoutf="$dir/oncall.out"
  : >"$out" 2>/dev/null || true
  : >"$stdoutf" 2>/dev/null || true
  slot_run_retry "${ONCALL_CMD:?}" "$PROJECT" "$prompt" "$out" "$stdoutf" "$dir/oncall.err" \
    "$(belt_scaled_seconds $((ONCALL_TIMEOUT_MIN * 60)))" "$ONCALL_TIMEOUT_MIN" oncall
  rc=$?
  printf 'on-call %s: exit %s\n' "$key" "$rc" >>"$(watch_log_path)" 2>/dev/null || true

  if [ -s "$out" ]; then answer=$out; else answer=$stdoutf; fi
  last=$(last_nonempty_line "$answer")
  verdict=$(oncall_verdict_of "$answer")
  restart_issue=""
  if [ "$verdict" = "restart" ]; then
    restart_issue=$(oncall_restart_issue "$answer")
    if [ -z "$issue" ] || [ "$issue" = "0" ] || [ "$restart_issue" != "$issue" ]; then
      # a restart for another issue is not a verdict for this one
      warn "on-call asked to restart #${restart_issue:-?} while handling #${issue:-none}; ignoring it"
      verdict=none
      restart_issue=""
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    # a killed or failed call never counts as fixed or as a restart
    case "$verdict" in
      fixed|restart) verdict=none ;;
    esac
  fi

  # belt posts the on-call's last 5 lines on the issue
  if [ -n "$issue" ] && [ "$issue" != "0" ] && [ -s "$answer" ]; then
    gh issue comment "$issue" -R "$SLUG" --body "$(tail -n 5 "$answer")" \
      >>"$(watch_log_path)" 2>&1 || true
  fi

  case "$verdict" in
    owner)
      sentence=$(trim_str "${last#ONCALL: OWNER }")
      [ -n "$sentence" ] || sentence="issue #$issue needs an owner"
      if [ -n "$issue" ] && [ "$issue" != "0" ]; then
        title="#$issue needs an owner: $sentence"
      else
        title="On-call needs an owner: $sentence"
      fi
      title=$(truncate_str "$(trim_str "$title")" 80)
      create_owner_issue "$SLUG" "$title" "Needed for issue #${issue:-?}" || true
      owner_notify_once "$state" "owner:$title" "belt: $sentence"
      ;;
    restart)
      # belt, never the on-call, restarts the ticket: the child must not inherit
      # the slot's sandbox. This runs from the watch pass, outside any sandbox.
      if [ -n "${BELT_DRILL_NOTE:-}" ]; then
        log_file "on-call: drill, not restarting #$restart_issue"
      elif [ "$kind" != "silent" ] && watch_ticket_live "$restart_issue"; then
        # only a run shown to be hung is killed; a slow or stuck one may be working
        log_file "on-call asked to restart #$restart_issue on $key, but its run is alive and not hung; not restarting it"
      elif ! watch_kill_ticket "$restart_issue"; then
        # a holder that survives would make the restart exit at once on its lock
        warn "could not stop the old run of #$restart_issue; not restarting it"
        create_owner_issue "$SLUG" "#$restart_issue is hung and could not be stopped" "belt watch" || true
        owner_notify_once "$state" "unkillable:$restart_issue" "belt: #$restart_issue is hung and its old run could not be stopped"
      elif watch_clear_dead_claim "$restart_issue"; then
        log_file "on-call restart: $(watch_restart_text "$restart_issue")"
        printf '%s %s\n' "$(date '+%s' 2>/dev/null)" "$(watch_pr_for_issue "$restart_issue" | cut -f2)" \
          >"$state/restart-verify.$restart_issue" 2>/dev/null || true
        nohup env BELT_ISSUE="$restart_issue" BELT_PROJECT="${PROJECT:-}" \
          BELT_HOME="${BELT_HOME:-}" bash -c "${TICKET_RESTART_CMD:-belt run \$BELT_ISSUE}" \
          </dev/null >>"$state/restart.out" 2>&1 &
      else
        warn "could not clear $(claim_label) from #$restart_issue; not restarting it"
      fi
      ;;
    none)
      if [ -n "$issue" ] && [ "$issue" != "0" ]; then
        title="#$issue needs an owner: on-call ended without a verdict"
      else
        title="On-call ended without a verdict ($kind)"
      fi
      title=$(truncate_str "$(trim_str "$title")" 80)
      create_owner_issue "$SLUG" "$title" "belt watch" || true
      owner_notify_once "$state" "owner:$title" "belt: on-call ended without a verdict on $key"
      ;;
  esac
  return 0
}

watch_tree_pids() { # <root>; the root and every descendant
  ps -axo pid=,ppid= 2>/dev/null | awk -v r="${1:?}" '{p[NR]=$1;q[NR]=$2} END{s[r]=1;do{c=0;for(i=1;i<=NR;i++)if((q[i] in s)&&!(p[i] in s)){s[p[i]]=1;c=1}}while(c);for(k in s)print k}'
}

watch_kill_ticket() { # <n>; stops every live holder of the ticket; 0 when none is left
  local issue=${1:?} try pids
  for try in 1 2 3 4 5; do
    watch_ticket_probe "$issue" || return 0
    case "${WATCH_TICKET_PID:-}" in ''|0|1) return 1 ;; esac
    # a pid read from a lock file may be stale and now belong to something else
    case "${WATCH_TICKET_PID_FROM:-}" in
      cmd) ;;
      lock)
        [ -z "${TICKET_ALIVE_CMD:-}" ] || return 1
        ps -o command= -p "$WATCH_TICKET_PID" 2>/dev/null | grep -q 'belt' || return 1
        ;;
      *) return 1 ;;
    esac
    pids=$(watch_tree_pids "$WATCH_TICKET_PID")
    printf '%s\n' "$pids" | grep -Fxq -- "$$" && return 1
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null
    sleep "$(belt_scaled_seconds 3)"
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null
    log_file "stopped the old run of #$issue (root pid $WATCH_TICKET_PID)"
  done
  watch_ticket_probe "$issue" && return 1
  return 0
}

watch_restart_finished() { # <n> <head-at-restart>; 0 when a run that has ended left real work behind
  local issue=${1:?} head=${2:-} now_head
  [ "$(gh issue view "$issue" -R "$SLUG" --json state -q .state 2>/dev/null)" = "CLOSED" ] && return 0
  now_head=$(watch_pr_for_issue "$issue" | cut -f2)
  [ -n "$now_head" ] && [ "$now_head" != "$head" ]
}

watch_verify_restarts() { # a restart counts only when a new run is alive and logging, or left new work
  local state f issue at head now logf mt wait_secs title
  state=$(watch_state_dir)
  now=$(date '+%s' 2>/dev/null) || return 0
  wait_secs=$(belt_scaled_seconds 300)
  for f in "$state"/restart-verify.*; do
    [ -f "$f" ] || continue
    issue=${f##*.}
    at=0; head=""
    read -r at head <"$f" 2>/dev/null || true
    case "$at" in ''|*[!0-9]*) rm -f "$f"; continue ;; esac
    [ $((now - at)) -ge "$wait_secs" ] || continue
    rm -f "$f"
    logf=$(watch_ticket_log "$issue") || logf=""
    mt=$(file_mtime "$logf" 2>/dev/null) || mt=0
    # the new run can log in the same second the restart was recorded
    if [ "${mt:-0}" -lt "$at" ]; then
      title="#$issue did not restart: its log has not moved since the restart"
    elif watch_ticket_live "$issue" || watch_restart_finished "$issue" "$head"; then
      title=""
    else
      title="#$issue did not restart: the new run ended and left no new work"
    fi
    if [ -z "$title" ]; then
      log_file "restart of #$issue verified"
    else
      log_file "$title"
      create_owner_issue "$SLUG" "$title" "belt watch" || true
      owner_notify_once "$state" "norestart:$issue:$at" "belt: $title"
    fi
  done
  return 0
}

bisect_worker_file() { # <sha>; the pid of the last detached worker for this SHA
  printf '%s/bisect.worker.%s\n' "$(watch_state_dir)" "${1:?}"
}

bisect_retry_file() { # <sha>; one line per re-dispatch after a dead worker
  printf '%s/bisect.retries.%s\n' "$(watch_state_dir)" "${1:?}"
}

watch_bisect_retries() { # <sha>; re-dispatches already made for this SHA
  local f n
  f=$(bisect_retry_file "$1")
  [ -f "$f" ] || { printf '0\n'; return 0; }
  n=$(grep -c '' "$f" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

watch_bisect_retry_add() { # <sha>
  printf '%s\n' "$(date '+%s' 2>/dev/null || echo 0)" >>"$(bisect_retry_file "$1")" 2>/dev/null || true
}

watch_bisect_worker_live() { # <sha>; the lock holder or the dispatched worker is alive
  # The marker alone never proves a worker is running: the detached process can
  # die before it takes bisect.lock. A recorded pid is the other live signal.
  local state pid
  state=$(watch_state_dir)
  lock_holder_alive "$state/bisect.lock" && return 0
  pid=$(cat "$(bisect_worker_file "$1")" 2>/dev/null) || return 1
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null
}

watch_bisect_escalate() { # <sha>; the worker keeps dying: needs-owner + one ping
  local redsha=${1:?} state=${2:-} short title
  [ -n "$state" ] || state=$(watch_state_dir)
  short=$(printf '%s' "$redsha" | cut -c1-12)
  title="Bisect keeps dying at $short: needs an owner"
  create_owner_issue "$SLUG" "$title" \
    "The detached bisect for the red base $redsha died 2 retries in a row and left no culprit." || true
  owner_notify_once "$state" "owner:bisect:$redsha" \
    "belt: the bisect for $short keeps dying; it needs an owner"
  log_file "bisect: $redsha has no culprit after 2 retries; handed it to the owner"
  return 0
}

watch_bisect_start() { # <red-sha>; dispatch the bisect detached, at most 3 starts per SHA
  # Never bisect in the watch pass: one red base would hold watch.lock for up to
  # 12 suite runs, freezing every other recovery for hours. The started marker
  # is not final: a later pass re-dispatches a SHA whose worker died (no done
  # marker, no innocent lock holder), twice, then hands it to the owner.
  local state redsha marker retries redispatch=0
  state=$(watch_state_dir)
  redsha=${1:-}
  [ -n "$redsha" ] || return 0
  suite_state_read
  [ "$SUITE_RESULT" = "red" ] && [ "$SUITE_SHA" = "$redsha" ] || return 0
  [ -n "${SUITE_GREEN:-}" ] || return 0
  # this dispatch already produced its answer (culprit or a clean miss)
  [ -e "$state/bisect.done.$redsha" ] && return 0
  # a live worker owns this SHA: never start a second one on top of it
  watch_bisect_worker_live "$redsha" && return 0
  marker="$state/bisect.started.$redsha"
  if [ -e "$marker" ]; then
    retries=$(watch_bisect_retries "$redsha")
    if [ "$retries" -ge 2 ]; then
      watch_bisect_escalate "$redsha" "$state"
      return 0
    fi
    watch_bisect_retry_add "$redsha"
    redispatch=1
  fi
  : >"$marker" 2>/dev/null || return 0
  nohup env BELT_HOME="$BELT_HOME" bash "$BELT_ROOT/belt" __bisect "${PROJECT:-}" "$redsha" \
    >>"$state/bisect.out" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$(bisect_worker_file "$redsha").tmp" 2>/dev/null \
    && mv -f "$(bisect_worker_file "$redsha").tmp" "$(bisect_worker_file "$redsha")" 2>/dev/null
  if [ "$redispatch" = "1" ]; then
    log_file "bisect: re-dispatched the dead bisect for $redsha"
  else
    log_file "bisect: started a detached bisect for $redsha"
  fi
  return 0
}

watch_bisect_run() { # [red-sha]; the detached worker: bisect under bisect.lock
  local state redsha green culprit wpr
  state=$(watch_state_dir)
  suite_state_read
  redsha=${1:-${SUITE_SHA:-}}
  [ -n "$redsha" ] || return 1
  [ "$SUITE_RESULT" = "red" ] && [ "$SUITE_SHA" = "$redsha" ] || return 1
  green=${SUITE_GREEN:-}
  [ -n "$green" ] || return 1
  mkdir -p "$state" 2>/dev/null || return 1
  if ! acquire_lock "$state/bisect.lock" 0; then
    log_file "bisect: another bisect is already live"
    return 0
  fi
  culprit=$(suite_bisect "$green" "$redsha") || culprit=""
  if [ -n "$culprit" ]; then
    wpr=$(suite_culprit_pr "$culprit")
    printf '%s\n%s\n' "$culprit" "${wpr:-no PR found}" >"$state/bisect.culprit" 2>/dev/null || true
  fi
  # this SHA's worker finished: a later pass must not re-dispatch it
  : >"$state/bisect.done.$redsha" 2>/dev/null || true
  release_lock "$state/bisect.lock"
  return 0
}

watch_bisect_report() { # comment a finished bisect on the red-base issue, once
  local state culprit wpr issue marker
  state=$(watch_state_dir)
  [ -f "$state/bisect.culprit" ] || return 0
  culprit=$(sed -n 1p "$state/bisect.culprit" 2>/dev/null) || return 0
  case "$culprit" in ''|*[!0-9a-f]*) return 0 ;; esac
  marker="$state/bisect.reported.$culprit"
  [ -e "$marker" ] && return 0
  issue=$(suite_issue_number)
  [ -n "$issue" ] || return 0
  wpr=$(sed -n 2p "$state/bisect.culprit" 2>/dev/null) || wpr=""
  if gh issue comment "$issue" -R "$SLUG" \
    --body "Bisect: the first bad commit is $culprit. Culprit PR: ${wpr:-not found}." \
    >>"$(watch_log_path)" 2>&1; then
    : >"$marker" 2>/dev/null || true
  fi
  return 0
}

cmd_bisect_run() { # internal: the detached worker (__bisect <project> [red-sha])
  local dir=${1:-} redsha=${2:-}
  load_config "$dir" || die "could not load config for the bisect run"
  SLUG=$(repo_slug) || die "could not resolve the repo slug for the bisect run"
  LOG="$(watch_log_path)"
  watch_bisect_run "$redsha"
  return 0
}

resume_merge_gate() { # <n> <pr>; re-enter station 8 with the stored clean review
  local wn=${1:?} wpr=${2:?} head
  N=$wn
  PR=$wpr
  BASE=$(base_branch)
  TICKET_DIR="$(watch_state_dir)/$wn"
  OUT_DIR="$TICKET_DIR/out"
  LOG="$TICKET_DIR/log"
  WORKTREE="$(watch_state_dir)/worktrees/$wn"
  BRANCH=$(belt_branch_for "$wn")
  [ -e "$WORKTREE" ] || return 1
  [ -f "$TICKET_DIR/review-sha" ] || return 1
  REVIEW_SHA=$(tr -d '[:space:]' <"$TICKET_DIR/review-sha" 2>/dev/null) || return 1
  case "$REVIEW_SHA" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#REVIEW_SHA}" -eq 40 ] || return 1
  REVIEW_P1=$(tr -d '[:space:]' <"$TICKET_DIR/review-p1" 2>/dev/null) || return 1
  case "$REVIEW_P1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$REVIEW_P1" -eq 0 ] || return 1
  if [ ! -f "$TICKET_DIR/checks.tsv" ]; then
    # local checks are deterministic and free; re-run them rather than merge blind
    station_checks || return 1
  fi
  [ -f "$TICKET_DIR/checks.tsv" ] || return 1
  CHECK_TABLE=$(cat "$TICKET_DIR/checks.tsv" 2>/dev/null) || return 1
  case "$CHECK_TABLE" in *'|FAIL'*) return 1 ;; esac
  head=$(gh pr view "$wpr" -R "$SLUG" --json headRefOid -q .headRefOid 2>/dev/null) || return 1
  head=$(printf '%s' "$head" | tr -d '[:space:]')
  [ "$head" = "$REVIEW_SHA" ] || return 1
  STATUS_REASON=""
  MERGED=0
  TICKET_FINISHED=0
  TERMINAL_RELABEL_FAILED=0
  if station_merge; then
    gh pr edit "$wpr" -R "$SLUG" --remove-label needs-lead >>"$LOG" 2>&1 || true
    issue_relabel "" "needs-lead" "clear needs-lead after resuming the merge" || true
    log "watch: resumed PR #$wpr and merged it"
    return 0
  fi
  return 1
}

watch_resume_green_lead() { # <n>; CI completed green -> drop needs-lead, resume merge gate
  local wn=${1:?} wpr whead wci
  wpr=$(watch_pr_for_issue "$wn")
  [ -n "$wpr" ] || return 1
  whead=${wpr#*$'\t'}
  wpr=${wpr%%$'\t'*}
  [ -n "$wpr" ] && [ -n "$whead" ] || return 1
  watch_pr_is_risky "$wn" "$whead" && return 1
  wci=$(ci_state_of "$wpr" 2>/dev/null) || return 1
  [ "$wci" = "pass" ] || return 1
  resume_merge_gate "$wn" "$wpr"
}

watch_ping_owner_issues() { # a new needs-owner issue (title), once, unless baselined
  local state wn title
  state=$(watch_state_dir)
  gh issue list -R "$SLUG" --state open --label needs-owner --limit 200 --json number,title 2>/dev/null \
    | jq -r '.[] | "\(.number)\t\(.title)"' 2>/dev/null \
    | while IFS=$'\t' read -r wn title || [ -n "$wn" ]; do
        [ -n "$wn" ] || continue
        watch_baselined "$wn" && continue
        [ -n "$title" ] || continue
        owner_notify_once "$state" "owner:$title" "belt: needs owner: $title"
      done
  return 0
}

watch_epoch() { # <ISO time>; epoch seconds, empty when unreadable
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${1:-}" '+%s' 2>/dev/null \
    || date -u -d "${1:-}" '+%s' 2>/dev/null
}

watch_batch_ci() { # a batch run that fails or overruns must not wait for a session to notice it
  # Run 41283939107 lost its runner and nobody saw for 4.5 hours, because the only
  # waiter was a Claude session whose gh calls failed during a network drop.
  local state stamp now prs runs branch line id status conclusion started attempt since age jobs marker
  state=$(watch_state_dir)
  stamp="$state/batch-ci.unread"
  now=$(date '+%s' 2>/dev/null) || return 0
  if ! prs=$(gh pr list -R "$SLUG" --state open --limit 100 --json headRefName -q '.[].headRefName' 2>/dev/null) \
    || ! runs=$(gh run list -R "$SLUG" --workflow "$BATCH_CI_WORKFLOW" --limit 50 \
      --json databaseId,headBranch,status,conclusion,startedAt,attempt 2>/dev/null); then
    [ -f "$stamp" ] || printf '%s\n' "$now" >"$stamp" 2>/dev/null
    since=$(cat "$stamp" 2>/dev/null) || since=$now
    case "$since" in ''|*[!0-9]*) since=$now ;; esac
    log_file "batch CI: GitHub could not be read"
    if [ $((now - since)) -ge "$(belt_scaled_seconds 3600)" ]; then
      owner_notify_once "$state" "batch-unread:$since" "belt: batch CI has been unreadable for an hour; GitHub or the network may be down"
    fi
    return 0
  fi
  rm -f "$stamp" 2>/dev/null
  while IFS= read -r branch || [ -n "$branch" ]; do
    case "$branch" in "$BATCH_BRANCH_PREFIX"*) ;; *) continue ;; esac
    line=$(printf '%s' "$runs" | jq -r --arg b "$branch" \
      'map(select(.headBranch == $b)) | sort_by(.databaseId) | last // empty
       | "\(.databaseId)\t\(.status)\t\(if (.conclusion // "") == "" then "none" else .conclusion end)\t\(.startedAt)\t\(.attempt)"' 2>/dev/null) || continue
    [ -n "$line" ] || continue
    IFS=$'\t' read -r id status conclusion started attempt <<EOF
$line
EOF
    case "$id" in ''|*[!0-9]*) continue ;; esac
    if [ "$status" != "completed" ]; then
      since=$(watch_epoch "$started")
      case "$since" in ''|*[!0-9]*) continue ;; esac
      age=$((now - since))
      if [ "$age" -ge "$(belt_scaled_seconds $((BATCH_CI_MAX_MIN * 60)))" ]; then
        owner_notify_once "$state" "batch-overdue:$id:$attempt" "belt: batch CI on $branch has been running $((age / 60)) minutes (run $id)"
      fi
      continue
    fi
    case "$conclusion" in
      success|skipped|neutral) continue ;;
      cancelled)
        # someone chose to cancel it, so it is reported and never re-run
        owner_notify_once "$state" "batch-cancelled:$id:$attempt" "belt: batch CI on $branch was cancelled (run $id)"
        continue
        ;;
    esac
    # a failed job with no failed step never reached a test: the runner or the service broke
    jobs=$(gh run view "$id" -R "$SLUG" --json jobs 2>/dev/null) || continue
    marker="$state/batch-rerun.$id"
    if printf '%s' "$jobs" | jq -e '[.jobs[] | select(.conclusion == "failure")] as $f
      | ($f | length) > 0 and ([$f[].steps[]? | select(.conclusion == "failure")] | length) == 0' >/dev/null 2>&1 \
      || [ "$conclusion" = "timed_out" ] || [ "$conclusion" = "startup_failure" ]; then
      if [ -e "$marker" ]; then
        owner_notify_once "$state" "batch-infra:$id:$attempt" "belt: batch CI on $branch hit an infrastructure failure again after one re-run (run $id)"
      else
        : >"$marker" 2>/dev/null || continue
        if gh run rerun "$id" -R "$SLUG" --failed >/dev/null 2>&1; then
          log_file "batch CI: re-ran run $id on $branch once after an infrastructure failure"
        else
          owner_notify_once "$state" "batch-rerun-failed:$id" "belt: batch CI on $branch hit an infrastructure failure and could not be re-run (run $id)"
        fi
      fi
    else
      owner_notify_once "$state" "batch-failed:$id:$attempt" "belt: batch CI failed on $branch (run $id)"
    fi
  done <<EOF
$prs
EOF
  return 0
}

watch_ping_lead_waits() { # a risky PR waiting on the lead longer than LEAD_WAIT_MIN
  local state dir f now first wpr wbranch whead wnum prefix
  state=$(watch_state_dir)
  dir="$state/lead-wait"
  mkdir -p "$dir" 2>/dev/null || true
  gh pr list -R "$SLUG" --state open --label needs-lead --limit 100 --json number,headRefName,headRefOid 2>/dev/null \
    | jq -r '.[] | "\(.number)\t\(.headRefName)\t\(.headRefOid)"' 2>/dev/null \
    | while IFS=$'\t' read -r wpr wbranch whead || [ -n "$wpr" ]; do
        [ -n "$wpr" ] || continue
        prefix=$(branch_prefix)
        case "$wbranch" in "$prefix"*) wnum=${wbranch#"$prefix"} ;; *) continue ;; esac
        watch_baselined "$wnum" && continue
        watch_pr_is_risky "$wnum" "$whead" || continue
        f="$dir/$wpr"
        now=$(date '+%s' 2>/dev/null) || now=0
        if [ ! -f "$f" ]; then
          printf '%s\n' "$now" >"$f" 2>/dev/null || true
          continue
        fi
        first=$(cat "$f" 2>/dev/null) || first=""
        case "$first" in ''|*[!0-9]*) continue ;; esac
        [ $((now - first)) -ge "$(belt_scaled_seconds $((LEAD_WAIT_MIN * 60)))" ] || continue
        owner_notify_once "$state" "lead-wait:$wpr" \
          "belt: risky PR #$wpr has waited on the lead for more than $LEAD_WAIT_MIN min"
      done
  return 0
}

cmd_watch() {
  local dir="" baseline=0 a ignored
  for a in "$@"; do
    case "$a" in
      --baseline) baseline=1 ;;
      *) dir=$a ;;
    esac
  done
  local state problems seen key issue kind count=0 oncall=0 cfgdir
  cfgdir=${dir:-${BELT_PROJECT:-$PWD}}
  if [ -d "$cfgdir" ]; then
    cfgdir=$(cd -P "$cfgdir" 2>/dev/null && pwd) || cfgdir=$cfgdir
    # a privacy denial makes belt.conf look absent or unreadable; never run blind
    if [ ! -f "$cfgdir/belt.conf" ] || [ ! -r "$cfgdir/belt.conf" ]; then
      watch_alert_config "$cfgdir"
      warn "watch: cannot read $cfgdir/belt.conf; the owner was notified"
      return 1
    fi
  fi
  if ! load_config "${dir:-}"; then
    watch_alert_config "$cfgdir"
    warn "watch: could not load config; the owner was notified"
    return 1
  fi
  BELT_PROJECT=$PROJECT
  SLUG=$(repo_slug) || { warn "watch: could not resolve the repo slug"; return 0; }
  # proof for `belt install --watch`: before the lock, so a busy pass still shows
  # that this pass read its config
  LOG="$(watch_log_path)"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  log "watch: config loaded"
  if [ "$baseline" = "1" ]; then
    # adding the watcher to an existing project: its old open stuck and
    # needs-owner issues are not new problems and must never page on-call
    if [ -z "${SLUG:-}" ]; then
      warn "watch --baseline: could not resolve the repo slug"
      return 1
    fi
    ignored=$(watch_baseline_write "$SLUG") || return 1
    printf 'baseline: %s issue(s) ignored by watch (%s)\n' "$ignored" "$(watch_baseline_path)"
    return 0
  fi
  watch_ensure_labels
  if [ -z "${ONCALL_CMD:-}" ]; then
    warn "watch: ONCALL_CMD is not set in belt.conf; nothing was run"
    return 0
  fi
  state=$(watch_state_dir)
  mkdir -p "$state" 2>/dev/null || { warn "watch: cannot create $state"; return 0; }
  if ! acquire_lock "$state/watch.lock" 0; then
    log "watch: another pass is already running"
    return 0
  fi
  trap 'release_lock "$state/watch.lock"' EXIT INT TERM HUP
  LOG="$(watch_log_path)"
  # drill hook: this file proves the scoped pass really got the lock and ran
  if [ -n "${BELT_WATCH_PASS_MARK:-}" ]; then
    : >"$BELT_WATCH_PASS_MARK" 2>/dev/null || true
  fi

  # a drill pass touches one issue only: no suite run, no unrelated owner pings
  if [ -z "${BELT_WATCH_ONLY:-}" ]; then
    suite_start_detached >/dev/null 2>&1 || true
  fi

  problems="$state/watch.problems"
  watch_collect "$problems" >/dev/null 2>&1 || { : >"$problems"; }
  watch_drop_baselined "$problems"
  if [ -n "${BELT_WATCH_ONLY:-}" ]; then
    awk -F'\t' -v want="$BELT_WATCH_ONLY" '$2 == want' "$problems" >"$problems.only" 2>/dev/null \
      && mv -f "$problems.only" "$problems" 2>/dev/null || true
  fi
  seen="$state/watch.seen"
  touch "$seen" 2>/dev/null || true

  while IFS=$'\t' read -r key issue kind || [ -n "$key" ]; do
    [ -n "$key" ] || continue
    count=$((count + 1))
    if [ "$kind" = "red" ]; then
      # dispatch is idempotent (one marker per SHA) and never blocks the pass
      watch_bisect_start "${key#red:}" >>"$LOG" 2>&1 || true
    fi
    case "$kind" in
      stuck|silent|budget|stale|conflict)
        # a persistent condition keeps retrying the on-call every pass: the
        # per-issue attempt cap, not watch.seen, decides when the owner takes over
        ;;
      *)
        grep -Fxq -- "$key" "$seen" 2>/dev/null && continue
        ;;
    esac
    if [ "$kind" = "lead" ] && watch_resume_green_lead "$issue" >>"$LOG" 2>&1; then
      continue
    fi
    oncall_run_problem "$key" "$issue" "$kind" >>"$LOG" 2>&1 || true
    oncall=$((oncall + 1))
  done <"$problems"

  # watch.seen is "currently being handled": cleared problems re-arm
  {
    cut -f1 "$problems" 2>/dev/null | sed '/^[[:space:]]*$/d'
  } >"$seen.tmp" 2>/dev/null && mv -f "$seen.tmp" "$seen" 2>/dev/null || true

  watch_bisect_report >>"$LOG" 2>&1 || true
  watch_verify_restarts >>"$LOG" 2>&1 || true
  if [ -z "${BELT_WATCH_ONLY:-}" ]; then
    # belt itself backs up, outside the sandbox: no model, at most once a day
    backup_maybe >>"$LOG" 2>&1 || true
    watch_ping_owner_issues >/dev/null 2>&1 || true
    watch_ping_lead_waits >/dev/null 2>&1 || true
    watch_batch_ci >>"$LOG" 2>&1 || true
  fi

  log "watch: $count problem(s), $oncall on-call run(s)"
  release_lock "$state/watch.lock"
  trap - EXIT INT TERM HUP
  return 0
}

drill_wait_lock() { # <lockdir> <budget-secs>; 0 when no live pass holds the lock
  local lock=${1:?} budget=${2:-0} waited=0
  while lock_holder_alive "$lock"; do
    [ "$waited" -ge "$budget" ] && return 1
    sleep 2
    waited=$((waited + 2))
  done
  return 0
}

drill_watch_pass() { # <state> <budget-secs>; 0 only when the scoped pass really ran
  # The pass writes its mark right after taking watch.lock; a busy lock never
  # writes one, so a drill can tell "did not run" from "ran without a verdict".
  local state=${1:?} budget=${2:-0} waited=0 mark
  mark="$state/drill/watch-pass.$$"
  while :; do
    while lock_holder_alive "$state/watch.lock"; do
      [ "$waited" -ge "$budget" ] && return 1
      sleep 2
      waited=$((waited + 2))
    done
    rm -f "$mark" 2>/dev/null || true
    BELT_WATCH_PASS_MARK=$mark
    export BELT_WATCH_PASS_MARK
    ( cmd_watch "$PROJECT" ) >>"${DRILL_LOG:-/dev/null}" 2>&1 || true
    if [ -e "$mark" ]; then
      rm -f "$mark" 2>/dev/null || true
      unset BELT_WATCH_PASS_MARK
      return 0
    fi
    [ "$waited" -ge "$budget" ] && return 1
    sleep 2
    waited=$((waited + 2))
  done
}

cmd_drill() { # [project-dir]; prove the repair chain on a throwaway stuck issue
  local dir=${1:-} state title body out n odir answer last verdict notifies reason=""
  local drill_log notifylog wait_budget seen_file seen_before seen_had=0
  local opened owner_issues num leftover=""
  local note='This is a drill: change nothing, reply ONCALL: OWNER drill reached the owner'
  load_config "${dir:-}" || die "could not load config (no belt.conf and BELT_PROJECT not set?)"
  SLUG=$(repo_slug) || die "could not resolve the repo slug (set REPO in belt.conf)"
  watch_ensure_labels
  state=$(state_dir_for "$SLUG")
  drill_log="$state/drill/log"
  notifylog="$state/drill/notify.log"
  if [ -z "${ONCALL_CMD:-}" ]; then
    printf 'FAIL: ONCALL_CMD is not set in belt.conf\n'
    return 1
  fi
  mkdir -p "$state/drill" 2>/dev/null || { printf 'FAIL: cannot create %s/drill\n' "$state"; return 1; }
  : >"$notifylog" 2>/dev/null || true
  : >>"$drill_log" 2>/dev/null || true

  # wait (bounded by ONCALL_TIMEOUT_MIN) for a free pass lock: a drill that
  # never runs must say so, not report a missing verdict as a slot failure
  wait_budget=$(belt_scaled_seconds $((ONCALL_TIMEOUT_MIN * 60)))
  if ! drill_wait_lock "$state/watch.lock" "$wait_budget"; then
    printf 'FAIL: watch.lock busy, the drill did not run\n'
    return 1
  fi

  title="belt drill $(date '+%Y%m%d-%H%M%S') (safe to close)"
  body='This is a belt drill issue opened by `belt drill`: it proves the repair chain end to end. Nothing to fix; safe to close.'
  gh label create belt-drill -R "$SLUG" --color ededed --description "belt drill" --force \
    >>"$drill_log" 2>&1 || true
  if ! out=$(gh issue create -R "$SLUG" --title "$title" --label stuck --label belt-drill \
    --body "$body" 2>>"$drill_log"); then
    printf 'FAIL: could not open the drill issue in %s\n' "$SLUG"
    return 1
  fi
  n=$(printf '%s' "$out" | sed -n 's#.*/issues/\([0-9][0-9]*\).*#\1#p' | tail -n 1)
  case "$n" in
    ''|*[!0-9]*) printf 'FAIL: could not read the drill issue number from %s\n' "$out"; return 1 ;;
  esac

  # always close the drill issue and drop its key, pass or fail
  DRILL_ISSUE=$n DRILL_STATE=$state DRILL_LOG=$drill_log
  # what the drill must give back: other issues' keys and the owner issues its
  # own pass opens (create_owner_issue records the number gh prints)
  seen_file="$state/watch.seen"
  seen_before="$state/drill/seen.before.$$"
  if [ -f "$seen_file" ] && cp "$seen_file" "$seen_before" 2>/dev/null; then
    seen_had=1
  else
    seen_had=0
    rm -f "$seen_before" 2>/dev/null || true
  fi
  opened="$state/drill/owners.opened.$$"
  : >"$opened" 2>/dev/null || true
  DRILL_SEEN=$seen_file DRILL_SEEN_BEFORE=$seen_before DRILL_SEEN_HAD=$seen_had
  DRILL_OWNERS_OPENED=$opened
  export BELT_OWNER_CREATED_LOG=$opened
  drill_cleanup() {
    local issue=${DRILL_ISSUE:-} state=${DRILL_STATE:-} drill_log=${DRILL_LOG:-}
    local seen=${DRILL_SEEN:-} before=${DRILL_SEEN_BEFORE:-} had=${DRILL_SEEN_HAD:-0}
    local opened=${DRILL_OWNERS_OPENED:-} num
    [ -n "$issue" ] || return 0
    [ "${DRILL_CLEANED:-0}" = "1" ] && return 0
    DRILL_CLEANED=1
    # close only the needs-owner issue(s) this drill's OWNER verdict opened, by
    # the number gh printed when it created them: an issue list is search
    # indexed and can miss an issue created a second ago, so a before/after
    # diff silently closes nothing
    if [ -n "$opened" ] && [ -s "$opened" ]; then
      while IFS= read -r num || [ -n "$num" ]; do
        case "$num" in ''|*[!0-9]*) continue ;; esac
        gh issue comment "$num" -R "$SLUG" \
          --body 'belt drill opened this; closing it again.' >>"$drill_log" 2>&1 || true
        gh issue close "$num" -R "$SLUG" >>"$drill_log" 2>&1 || true
      done <"$opened"
    fi
    rm -f "$opened" 2>/dev/null || true
    gh issue comment "$issue" -R "$SLUG" --body 'belt drill finished; closing the drill issue.' \
      >>"$drill_log" 2>&1 || true
    gh issue close "$issue" -R "$SLUG" >>"$drill_log" 2>&1 || true
    # put every other issue's keys back instead of keeping the filtered subset
    if [ -n "$seen" ]; then
      if [ "$had" = "1" ] && [ -f "$before" ]; then
        { grep -Fxv -- "stuck:$issue" "$before" 2>/dev/null || true; } >"$seen.drill"
        mv -f "$seen.drill" "$seen" 2>/dev/null || true
      else
        { grep -Fxv -- "stuck:$issue" "$seen" 2>/dev/null || true; } >"$seen.drill"
        mv -f "$seen.drill" "$seen" 2>/dev/null || true
      fi
    fi
    rm -f "$before" 2>/dev/null || true
    # the drill's own leftover state goes too: its on-call dir, attempt record
    # and owner ping, so the next pass sees the state exactly as before
    rm -rf "$(oncall_dir "stuck:$issue")" 2>/dev/null || true
    rm -f "$(oncall_attempt_file "$issue")" 2>/dev/null || true
    if [ -n "$state" ] && [ -f "$state/ping.seen" ]; then
      awk -v p="owner:#$issue " 'index($0, p) != 1' "$state/ping.seen" \
        >"$state/ping.seen.drill" 2>/dev/null \
        && mv -f "$state/ping.seen.drill" "$state/ping.seen" 2>/dev/null || true
    fi
  }
  trap drill_cleanup EXIT INT TERM HUP

  # one real watch pass, scoped to the drill issue, with the real notifier recorded
  export BELT_WATCH_ONLY=$n BELT_DRILL_NOTE=$note
  export BELT_DRILL_NOTIFY_LOG=$notifylog BELT_REAL_OWNER_NOTIFY=$OWNER_NOTIFY_CMD
  export BELT_OWNER_NOTIFY_CMD='printf "%s\n" "$BELT_MESSAGE" >>"$BELT_DRILL_NOTIFY_LOG"; BELT_MESSAGE=$BELT_MESSAGE bash -c "$BELT_REAL_OWNER_NOTIFY"'
  if ! drill_watch_pass "$state" 0; then
    printf 'FAIL: watch.lock busy, the drill did not run (issue #%s closed; log: %s)\n' "$n" "$drill_log"
    return 1
  fi

  odir=$(oncall_dir "stuck:$n")
  answer="$odir/verdict.txt"
  [ -s "$answer" ] || answer="$odir/oncall.out"
  last=$(last_nonempty_line "$answer")
  verdict=$(oncall_verdict_of "$answer")
  notifies=$(grep -c '' "$notifylog" 2>/dev/null) || notifies=0
  case "$notifies" in ''|*[!0-9]*) notifies=0 ;; esac
  owner_issues=$(sed '/^[[:space:]]*$/d' "$opened" 2>/dev/null) || owner_issues=""

  # clean up here, not only in the trap, so the drill can verify its own work;
  # the trap stays as the crash path and no-ops once this has run
  drill_cleanup
  trap - EXIT INT TERM HUP

  # its own needs-owner issue must really be closed: a leftover one is a FAIL
  leftover=""
  for num in $owner_issues; do
    case "$num" in ''|*[!0-9]*) continue ;; esac
    [ "$(gh issue view "$num" -R "$SLUG" --json state -q .state 2>/dev/null)" = "OPEN" ] \
      && leftover="$leftover #$num"
  done

  if [ -n "$leftover" ]; then
    reason="its own needs-owner issue(s)$leftover are still open after cleanup"
  elif [ "$verdict" = "none" ]; then
    reason="the on-call ended without a verdict line${last:+ (last line: $last)}"
  elif [ "$notifies" -ne 1 ]; then
    reason="expected exactly one owner notify, saw $notifies"
  fi
  if [ -n "$reason" ]; then
    printf 'FAIL: %s (issue #%s closed; log: %s)\n' "$reason" "$n" "$drill_log"
    return 1
  fi
  printf 'PASS: on-call answered "%s" and exactly one owner notify fired (issue #%s closed)\n' \
    "$last" "$n"
  return 0
}

#!/usr/bin/env bash
# lib/common.sh - config, logging, labels, locks and small pure helpers.
# Sourced by belt, lib/ticket.sh and lib/review.sh. Bash 3.2 only.

if [ -n "${BELT_COMMON_LOADED:-}" ]; then
  return 0
fi
BELT_COMMON_LOADED=1
BELT_LIB_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd) || BELT_LIB_DIR=""

# ---------------------------------------------------------------- logging ---

belt_ts() { date '+%H:%M:%S'; }

belt_log_ts() { date '+%Y-%m-%d %H:%M:%S'; } # log timestamps use the machine's local time

log() { # log <message...>
  printf '[%s] %s\n' "$(belt_ts)" "$*"
  if [ -n "${LOG:-}" ]; then
    printf '[%s] %s\n' "$(belt_log_ts)" "$*" >>"$LOG" 2>/dev/null || true
  fi
}

warn() { # warn <message...>
  printf '[%s] WARN: %s\n' "$(belt_ts)" "$*" >&2
  if [ -n "${LOG:-}" ]; then
    printf '[%s] WARN: %s\n' "$(belt_log_ts)" "$*" >>"$LOG" 2>/dev/null || true
  fi
}

log_file() { # log_file <message...>; write to the log only, not stdout
  if [ -n "${LOG:-}" ]; then
    printf '[%s] %s\n' "$(belt_log_ts)" "$*" >>"$LOG" 2>/dev/null || true
  fi
}

die() { warn "$*"; exit 1; }

# ---------------------------------------------------------------- strings ---

trim_str() { # trim leading/trailing whitespace
  printf '%s' "${1:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

truncate_str() { # truncate_str <string> <max-chars>
  local s=${1:-} max=${2:-80}
  if [ "${#s}" -le "$max" ]; then
    printf '%s\n' "$s"
  else
    printf '%.*s\n' "$max" "$s"
  fi
}

status_trim_line() { # one plain status line, trimmed and bounded
  local line
  line=$(trim_str "${1:-}")
  truncate_str "$line" "${2:-120}"
}

line_count() { # line_count <file>
  [ -f "${1:-}" ] || { echo 0; return 0; }
  grep -c '' "$1" 2>/dev/null || echo 0
}

count_p1_findings() { # count_p1_findings <verdict-file>; count every P1 line, never a truncated view
  local f=${1:-} n
  [ -f "$f" ] || { printf '0\n'; return 0; }
  n=$(grep -c '^P1:' "$f" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

ci_state_from_output() { # ci_state_from_output <gh-output> <exit-code> -> pass|fail|pending|none|unknown
  local out=${1:-} rc=${2:-0} fail pending
  if [ -z "$out" ]; then
    # an empty answer is only "no checks" when gh itself succeeded
    if [ "$rc" -eq 0 ]; then printf 'none\n'; else printf 'unknown\n'; fi
    return 0
  fi
  if ! printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
    # gh's no-checks message is the one benign non-JSON answer
    if printf '%s' "$out" | grep -qi 'no checks reported'; then
      printf 'none\n'
    else
      printf 'unknown\n'
    fi
    return 0
  fi
  fail=$(printf '%s' "$out" | jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length' 2>/dev/null) || {
    printf 'unknown\n'; return 0; }
  pending=$(printf '%s' "$out" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null) || {
    printf 'unknown\n'; return 0; }
  case "$fail" in ''|*[!0-9]*) printf 'unknown\n'; return 0 ;; esac
  case "$pending" in ''|*[!0-9]*) printf 'unknown\n'; return 0 ;; esac
  if [ "$fail" -gt 0 ]; then
    printf 'fail\n'
  elif [ "$pending" -gt 0 ]; then
    printf 'pending\n'
  else
    printf 'pass\n'
  fi
  return 0
}

# -------------------------------------------------------------- time/pause ---

belt_date() { # belt_date <date-args...>; PAUSE_TZ when set, else machine local time
  if [ -n "${PAUSE_TZ:-}" ]; then
    TZ="$PAUSE_TZ" date "$@"
  else
    date "$@"
  fi
}

belt_now() { # current time in PAUSE_TZ; BELT_NOW overrides (already in PAUSE_TZ)
  if [ -n "${BELT_NOW:-}" ]; then
    printf '%s\n' "$BELT_NOW"
  else
    belt_date '+%Y-%m-%d %H:%M'
  fi
}

belt_dow() { # belt_dow YYYY-MM-DD -> 1..7 (Mon=1, Sun=7)
  awk -v d="${1:-1970-01-01}" 'BEGIN {
    split(d, a, "-"); y = a[1] + 0; m = a[2] + 0; day = a[3] + 0
    if (m < 3) { m += 12; y -= 1 }
    K = y % 100; J = int(y / 100)
    h = (day + int(13 * (m + 1) / 5) + K + int(K / 4) + int(J / 4) + 5 * J) % 7
    if (h == 0) w = 6; else if (h == 1) w = 7; else w = h - 1
    print w
  }'
}

belt_minutes() { # belt_minutes "HH:MM" -> minutes since midnight
  local t=${1:-00:00} hh mm
  hh=${t%%:*}
  mm=${t#*:}
  mm=${mm%%:*}
  printf '%s\n' $((10#$hh * 60 + 10#$mm))
}

pause_dow() { # pause_dow <Mon|mon|...> -> 1..7; fails on an unknown name
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    mon) printf '1\n' ;;
    tue) printf '2\n' ;;
    wed) printf '3\n' ;;
    thu) printf '4\n' ;;
    fri) printf '5\n' ;;
    sat) printf '6\n' ;;
    sun) printf '7\n' ;;
    *) return 1 ;;
  esac
}

pause_day_range_valid() { # <Mon|Mon-Fri>; a known day name, or two in a range
  local days=${1:-} a b
  case "$days" in
    ''|*@*) return 1 ;;
    *-*)
      a=${days%%-*}
      b=${days#*-}
      pause_dow "$a" >/dev/null || return 1
      pause_dow "$b" >/dev/null || return 1
      ;;
    *)
      pause_dow "$days" >/dev/null || return 1
      ;;
  esac
  return 0
}

pause_windows_valid() ( # every entry is Day[-Day]@HH:MM-HH:MM with start < end
  local w days times start end
  set -f # PAUSE_WINDOWS is data, never a glob
  [ -n "${PAUSE_WINDOWS:-}" ] || return 0
  for w in $PAUSE_WINDOWS; do
    case "$w" in
      *@*-*) ;;
      *) return 1 ;;
    esac
    days=${w%%@*}
    times=${w#*@}
    start=${times%-*}
    end=${times#*-}
    pause_day_range_valid "$days" || return 1
    case "$start" in
      [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
      *) return 1 ;;
    esac
    case "$end" in
      [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
      *) return 1 ;;
    esac
    [ "$(belt_minutes "$start")" -lt "$(belt_minutes "$end")" ] || return 1
  done
  return 0
)

pause_window_active() { # pause_window_active <dow> <mins> <entry>; end is exclusive
  local dow=${1:?} mins=${2:?} w=${3:-} days times start end a b smins emins
  days=${w%%@*}
  times=${w#*@}
  start=${times%-*}
  end=${times#*-}
  case "$days" in
    *-*)
      a=$(pause_dow "${days%%-*}")
      b=$(pause_dow "${days#*-}")
      ;;
    *)
      a=$(pause_dow "$days")
      b=$a
      ;;
  esac
  if [ "$a" -le "$b" ]; then
    [ "$dow" -ge "$a" ] && [ "$dow" -le "$b" ] || return 1
  else
    [ "$dow" -ge "$a" ] || [ "$dow" -le "$b" ] || return 1
  fi
  smins=$(belt_minutes "$start")
  emins=$(belt_minutes "$end")
  [ "$mins" -ge "$smins" ] && [ "$mins" -lt "$emins" ]
}

in_pause_window() { # in_pause_window ["YYYY-MM-DD HH:MM"]; empty PAUSE_WINDOWS never pauses
  local dt datepart timepart dow mins w
  [ -n "${PAUSE_WINDOWS:-}" ] || return 1
  dt=${1:-$(belt_now)}
  case "$dt" in
    *' '*) ;;
    *) return 1 ;;
  esac
  datepart=${dt%% *}
  timepart=${dt#* }
  dow=$(belt_dow "$datepart")
  mins=$(belt_minutes "$timepart")
  for w in $PAUSE_WINDOWS; do
    pause_window_active "$dow" "$mins" "$w" && return 0
  done
  return 1
}

pause_wait_label() { # latest end HH:MM of the windows covering now; empty = no pause
  local dt datepart timepart dow mins w times end emins best=""
  [ -n "${PAUSE_WINDOWS:-}" ] || return 0
  dt=${1:-$(belt_now)}
  datepart=${dt%% *}
  timepart=${dt#* }
  dow=$(belt_dow "$datepart")
  mins=$(belt_minutes "$timepart")
  for w in $PAUSE_WINDOWS; do
    pause_window_active "$dow" "$mins" "$w" || continue
    times=${w#*@}
    end=${times#*-}
    emins=$(belt_minutes "$end")
    if [ -z "$best" ] || [ "$emins" -gt "$best" ]; then best=$emins; fi
  done
  [ -n "$best" ] || return 0
  printf '%02d:%02d\n' $((best / 60)) $((best % 60))
}

belt_epoch() { # belt_epoch "YYYY-MM-DD HH:MM" (in PAUSE_TZ) -> epoch seconds
  local t=${1:-}
  [ -n "$t" ] || { echo 0; return 0; }
  if belt_date -j -f "%Y-%m-%d %H:%M" "$t" '+%s' >/dev/null 2>&1; then
    belt_date -j -f "%Y-%m-%d %H:%M" "$t" '+%s'
  else
    belt_date -d "$t" '+%s' 2>/dev/null || echo 0
  fi
}

belt_fmt_epoch() { # epoch -> "YYYY-MM-DD HH:MM" (in PAUSE_TZ)
  if belt_date -r "${1:-0}" '+%Y-%m-%d %H:%M' >/dev/null 2>&1; then
    belt_date -r "${1:-0}" '+%Y-%m-%d %H:%M'
  else
    belt_date -d "@${1:-0}" '+%Y-%m-%d %H:%M' 2>/dev/null
  fi
}

pause_wait() { # queue mode: wait out a window; BELT_NO_SLEEP / BELT_NOW return
  [ -n "${PAUSE_WINDOWS:-}" ] || return 0
  in_pause_window "$(belt_now)" || return 0
  local label now target epoch_now epoch_target secs
  label=$(pause_wait_label)
  [ -n "$label" ] || return 0
  printf 'paused, waiting until %s\n' "$label"
  log_file "paused, waiting until $label"
  if [ "${BELT_NO_SLEEP:-0}" = "1" ] || [ -n "${BELT_NOW:-}" ]; then
    return 0
  fi
  now=$(belt_now)
  target="${now%% *} $label"
  epoch_now=$(belt_epoch "$now")
  epoch_target=$(belt_epoch "$target")
  secs=$((epoch_target - epoch_now))
  [ "$secs" -gt 0 ] || secs=60
  sleep "$secs"
}

next_pause_label() { # first future pause start, plain "YYYY-MM-DD HH:MM"
  local now datepart base dayoff cand cdate dow w days times start a b tw best=""
  [ -n "${PAUSE_WINDOWS:-}" ] || return 0
  now=$(belt_now)
  datepart=${now%% *}
  base=$(belt_epoch "$datepart 00:00")
  [ "${base:-0}" -gt 0 ] || return 0
  dayoff=0
  while [ "$dayoff" -le 8 ]; do
    cand=$(belt_fmt_epoch $((base + dayoff * 86400)))
    cdate=${cand%% *}
    dow=$(belt_dow "$cdate")
    best=""
    for w in $PAUSE_WINDOWS; do
      days=${w%%@*}
      times=${w#*@}
      start=${times%-*}
      case "$days" in
        *-*)
          a=$(pause_dow "${days%%-*}")
          b=$(pause_dow "${days#*-}")
          ;;
        *)
          a=$(pause_dow "$days")
          b=$a
          ;;
      esac
      if [ "$a" -le "$b" ]; then
        [ "$dow" -ge "$a" ] && [ "$dow" -le "$b" ] || continue
      else
        [ "$dow" -ge "$a" ] || [ "$dow" -le "$b" ] || continue
      fi
      tw="$cdate $start"
      if [[ "$tw" > "$now" ]]; then
        if [ -z "$best" ] || [[ "$tw" < "$best" ]]; then best=$tw; fi
      fi
    done
    [ -n "$best" ] && { printf '%s\n' "$best"; return 0; }
    dayoff=$((dayoff + 1))
  done
  return 0
}

# ------------------------------------------------------------------ config ---

load_config() { # load_config [project-dir]; resets then sources belt.conf
  local dir
  dir=${1:-${BELT_PROJECT:-$PWD}}
  [ -d "$dir" ] || { warn "project directory not found: $dir"; return 1; }
  PROJECT=$(cd -P "$dir" 2>/dev/null && pwd) || return 1
  CONFIG_FILE="$PROJECT/belt.conf"

  # every key optional: reset so a stale value can never leak between loads
  BASE_BRANCH=""
  CHECK_BUILD=""
  CHECK_TEST=""
  CHECK_LINT=""
  RISKY_PATHS=""
  MAX_PARALLEL=""
  CHECK_SLOTS=""
  DEVICE_LOCK=""
  WORKER_CMD=""
  REVIEWER_CMD=""
  RISKY_REVIEWER_CMD=""
  PAUSE_WINDOWS=""
  PAUSE_TZ=""
  CHECK_WAIT_MIN=""
  REPO=""
  FULL_SUITE_CMD=""
  SUITE_TIMEOUT_MIN=""
  SLOT_IDLE_MIN=""
  SLOT_MAX_MIN=""
  ONCALL_CMD=""
  ONCALL_TIMEOUT_MIN=""
  SILENT_MIN=""
  SILENT_CPU_CS_MIN=""
  BATCH_BRANCH_PREFIX=""
  BATCH_CI_WORKFLOW=""
  BATCH_CI_MAX_MIN=""
  CONFLICT_MIN=""
  LEAD_WAIT_MIN=""
  OWNER_NOTIFY_CMD=""
  BUDGETS=""
  CLAIM_LABEL=""
  BRANCH_PREFIX=""
  TICKET_LOG_CMD=""
  TICKET_ALIVE_CMD=""
  TICKET_RESTART_CMD=""
  ONCALL_EXTRA_RULES=""
  SLOT_WRITE_ALLOW=""
  TOOLS_DIR=""
  BACKUP_DIR=""
  CHECKS_UNSANDBOXED=""
  CHECK_START_GAP_SEC=""

  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE" || { warn "could not read $CONFIG_FILE"; return 1; }
  fi

  MAX_PARALLEL=${MAX_PARALLEL:-0}
  local slots_set=${CHECK_SLOTS:+1}
  CHECK_SLOTS=${CHECK_SLOTS:-$(cpu_count)}
  # the slots have no defaults: a project must name its worker and reviewer
  WORKER_CMD=${WORKER_CMD:-}
  REVIEWER_CMD=${REVIEWER_CMD:-}
  RISKY_REVIEWER_CMD=${RISKY_REVIEWER_CMD:-}
  PAUSE_WINDOWS=${PAUSE_WINDOWS:-}
  PAUSE_TZ=${PAUSE_TZ:-}
  CHECK_WAIT_MIN=${CHECK_WAIT_MIN:-15}
  FULL_SUITE_CMD=${FULL_SUITE_CMD:-}
  SUITE_TIMEOUT_MIN=${SUITE_TIMEOUT_MIN:-120}
  SLOT_IDLE_MIN=${SLOT_IDLE_MIN:-20}
  SLOT_MAX_MIN=${SLOT_MAX_MIN:-180}
  ONCALL_CMD=${ONCALL_CMD:-}
  ONCALL_TIMEOUT_MIN=${ONCALL_TIMEOUT_MIN:-30}
  SILENT_MIN=${SILENT_MIN:-45}
  CONFLICT_MIN=${CONFLICT_MIN:-10}
  LEAD_WAIT_MIN=${LEAD_WAIT_MIN:-120}
  BUDGETS=${BUDGETS:-}
  # projects with their own ticket runner: these keys change only belt's
  # watch/on-call view, never the default belt workflow
  CLAIM_LABEL=${CLAIM_LABEL:-claimed:belt}
  BRANCH_PREFIX=${BRANCH_PREFIX:-belt/}
  TICKET_LOG_CMD=${TICKET_LOG_CMD:-}
  TICKET_ALIVE_CMD=${TICKET_ALIVE_CMD:-}
  TICKET_RESTART_CMD=${TICKET_RESTART_CMD:-belt run \$BELT_ISSUE}
  ONCALL_EXTRA_RULES=${ONCALL_EXTRA_RULES:-}
  SLOT_WRITE_ALLOW=${SLOT_WRITE_ALLOW:-}
  TOOLS_DIR=${TOOLS_DIR:-}
  BACKUP_DIR=${BACKUP_DIR:-}
  # a project whose build tool truly cannot nest may drop only the sandbox
  SILENT_CPU_CS_MIN=${SILENT_CPU_CS_MIN:-20}
  BATCH_BRANCH_PREFIX=${BATCH_BRANCH_PREFIX:-batch/}
  BATCH_CI_WORKFLOW=${BATCH_CI_WORKFLOW:-CI}
  BATCH_CI_MAX_MIN=${BATCH_CI_MAX_MIN:-240}
  CHECKS_UNSANDBOXED=${CHECKS_UNSANDBOXED:-0}
  case "$CHECKS_UNSANDBOXED" in 1) ;; *) CHECKS_UNSANDBOXED=0 ;; esac
  # Xcode projects (the only ones that set CHECKS_UNSANDBOXED) boot simulators:
  # several at once beside CI timed out CI, and boots in the same second
  # crashed test runners. One check at a time unless belt.conf says more,
  # and starts at least CHECK_START_GAP_SEC apart.
  if [ "$CHECKS_UNSANDBOXED" = "1" ]; then
    [ -n "$slots_set" ] || CHECK_SLOTS=1
    CHECK_START_GAP_SEC=${CHECK_START_GAP_SEC:-20}
  fi
  CHECK_START_GAP_SEC=${CHECK_START_GAP_SEC:-0}
  case "$CHECK_START_GAP_SEC" in ''|*[!0-9]*) CHECK_START_GAP_SEC=0 ;; esac
  # Apple's tools need full Xcode; xcode-select often points at the Command
  # Line Tools, where xcodebuild and simctl fail
  if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    case "$(xcode-select -p 2>/dev/null)" in
      */CommandLineTools*) DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; export DEVELOPER_DIR ;;
    esac
  fi
  OWNER_NOTIFY_CMD=${OWNER_NOTIFY_CMD:-'osascript -e "display notification \"$BELT_MESSAGE\" with title \"belt\""'}
  # drill/test hook: a wrapper around the real notify command (the drill
  # records every ping in its own state dir before calling the real one)
  OWNER_NOTIFY_CMD=${BELT_OWNER_NOTIFY_CMD:-$OWNER_NOTIFY_CMD}
  BELT_HOME=${BELT_HOME:-$HOME/.belt}
  case "$BELT_HOME" in "") BELT_HOME="$HOME/.belt" ;; esac
  case "$BELT_HOME" in /*) ;; *) BELT_HOME="$PWD/$BELT_HOME" ;; esac

  # 0 means no parallel cap; anything non-numeric also means no cap
  case "$MAX_PARALLEL" in ''|*[!0-9]*) MAX_PARALLEL=0 ;; esac
  case "$CHECK_SLOTS" in ''|*[!0-9]*) CHECK_SLOTS=$(cpu_count) ;; esac
  [ "$CHECK_SLOTS" -ge 1 ] 2>/dev/null || CHECK_SLOTS=$(cpu_count)
  case "$CHECK_WAIT_MIN" in ''|*[!0-9]*) CHECK_WAIT_MIN=15 ;; esac
  case "$SUITE_TIMEOUT_MIN" in ''|*[!0-9]*) SUITE_TIMEOUT_MIN=120 ;; esac
  case "$SLOT_IDLE_MIN" in ''|*[!0-9]*) SLOT_IDLE_MIN=20 ;; esac
  case "$SLOT_MAX_MIN" in ''|*[!0-9]*) SLOT_MAX_MIN=180 ;; esac
  case "$ONCALL_TIMEOUT_MIN" in ''|*[!0-9]*) ONCALL_TIMEOUT_MIN=30 ;; esac
  case "$SILENT_MIN" in ''|*[!0-9]*) SILENT_MIN=45 ;; esac
  case "$SILENT_CPU_CS_MIN" in ''|*[!0-9]*) SILENT_CPU_CS_MIN=20 ;; esac
  case "$BATCH_CI_MAX_MIN" in ''|*[!0-9]*) BATCH_CI_MAX_MIN=240 ;; esac
  case "$CONFLICT_MIN" in ''|*[!0-9]*) CONFLICT_MIN=10 ;; esac
  case "$LEAD_WAIT_MIN" in ''|*[!0-9]*) LEAD_WAIT_MIN=120 ;; esac
  if ! pause_windows_valid; then
    warn "invalid PAUSE_WINDOWS in belt.conf: '$PAUSE_WINDOWS' (expected e.g. 'Mon-Fri@09:00-12:00')"
    return 1
  fi
  return 0
}

cpu_count() { # usable CPU count: sysctl (macOS), nproc (Linux), else 2
  local n
  n=$(sysctl -n hw.ncpu 2>/dev/null) || n=""
  case "$n" in ''|*[!0-9]*) n="" ;; esac
  if [ -z "$n" ]; then
    n=$(nproc 2>/dev/null) || n=""
    case "$n" in ''|*[!0-9]*) n="" ;; esac
  fi
  [ -n "$n" ] && [ "$n" -ge 1 ] 2>/dev/null || n=2
  printf '%s\n' "$n"
}

belt_scaled_seconds() { # belt_scaled_seconds <seconds>; BELT_TIME_SCALE divides (tests)
  local s=${1:-0} scale=${BELT_TIME_SCALE:-1}
  case "$s" in ''|*[!0-9]*) s=0 ;; esac
  case "$scale" in ''|*[!0-9]*|0) scale=1 ;; esac
  s=$((s / scale))
  [ "$s" -ge 1 ] || s=1
  printf '%s\n' "$s"
}

slot_idle_seconds() { # SLOT_IDLE_MIN in real seconds (scaled for tests)
  belt_scaled_seconds $(( ${SLOT_IDLE_MIN:-20} * 60 ))
}

slot_max_seconds() { # SLOT_MAX_MIN, the last-resort ceiling, in real seconds
  belt_scaled_seconds $(( ${SLOT_MAX_MIN:-180} * 60 ))
}

file_mtime() { # file_mtime <file>; epoch mtime, 1 when unreadable
  local f=${1:-} m
  [ -f "$f" ] || return 1
  if m=$(stat -c '%Y' "$f" 2>/dev/null); then :
  elif m=$(stat -f '%m' "$f" 2>/dev/null); then :
  else return 1
  fi
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$m"
}

stamp() { # stamp <stage> <start|end|stuck>; one line in <ticket dir>/timings.tsv
  local stage=${1:-} event=${2:-} dir id
  [ -n "$stage" ] && [ -n "$event" ] || return 0
  dir=${TIMINGS_DIR:-${TICKET_DIR:-}}
  [ -n "$dir" ] || return 0
  id=${TIMINGS_ID:-${N:-}}
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date '+%s' 2>/dev/null || echo 0)" "$id" "$stage" "$event" \
    >>"$dir/timings.tsv" 2>/dev/null || true
  return 0
}

owner_notify() { # owner_notify <message>; OWNER_NOTIFY_CMD runs with $BELT_MESSAGE
  local msg=${1:-}
  [ -n "${OWNER_NOTIFY_CMD:-}" ] || return 0
  BELT_MESSAGE=$msg bash -c "$OWNER_NOTIFY_CMD" </dev/null >/dev/null 2>&1 || true
  return 0
}

owner_notify_once() { # owner_notify_once <state-dir> <key> <message>; one ping per key
  local dir=${1:-} key=${2:-} msg=${3:-} seen
  [ -n "$dir" ] && [ -n "$key" ] || return 0
  seen="$dir/ping.seen"
  mkdir -p "$dir" 2>/dev/null || true
  if [ -f "$seen" ] && grep -Fxq -- "$key" "$seen" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$key" >>"$seen" 2>/dev/null || true
  owner_notify "$msg"
  return 0
}

require_slots() { # both slots must be set before any ticket is claimed
  local missing=""
  [ -n "${WORKER_CMD:-}" ] || missing="WORKER_CMD"
  if [ -z "${REVIEWER_CMD:-}" ]; then
    missing=${missing:+"$missing and "}REVIEWER_CMD
  fi
  [ -n "$missing" ] || return 0
  warn "belt.conf is missing $missing; nothing was run (see templates/belt.conf)"
  return 1
}

# ------------------------------------------------------------------ slots ---

slot_run() { # slot_run <cmd> <dir> <prompt-file> <out-file> <stdout-file> [stderr-file] [role]
  # One pluggable worker/reviewer: a shell line run with bash -c inside <dir>,
  # stdin from /dev/null, BELT_PROMPT_FILE and BELT_OUT_FILE exported. Every
  # call goes through guard_exec: throwaway HOME, no write outside its own work.
  local cmd=${1:?} dir=${2:?} prompt=${3:?} out=${4:?} stdoutf=${5:?} stderrf=${6:-}
  local role=${7:-worker}
  (
    cd "$dir" || exit 1
    export BELT_PROMPT_FILE="$prompt"
    export BELT_OUT_FILE="$out"
    if [ -n "$stderrf" ]; then
      guard_exec "$role" "$dir" "$cmd" </dev/null 2>>"$stderrf"
    else
      guard_exec "$role" "$dir" "$cmd" </dev/null 2>&1
    fi
  ) >"$stdoutf"
}

slot_rate_limited() { # slot_rate_limited <file...>; rate/usage-limit wording in any output file
  local f
  for f in "$@"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if grep -qiE '429|rate[ _-]?limit|too many requests|usage limit|quota|try again later|limit reached' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

slot_start_sha() { # slot_start_sha <dir>; HEAD of a git worktree, empty for a non-repo; 1 if unreadable
  local dir=${1:-} sha
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    return 0
  fi
  sha=$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null) || return 1
  printf '%s\n' "$sha"
  return 0
}

slot_retry_reset() { # slot_retry_reset <dir> <start-sha>; every retry starts identical
  local dir=${1:-} start=${2:-} proj target
  if [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && [ -d "$dir" ]; then
    proj=$(physical_path "$PROJECT") || proj=""
    target=$(physical_path "$dir") || target=""
    if [ -n "$proj" ]; then
      case "$target" in
        "$proj"|"$proj"/*)
          warn "refusing to reset the project checkout: $dir"
          return 1
          ;;
      esac
    fi
  fi
  if [ -n "$start" ]; then
    git -C "$dir" reset --hard "$start" >/dev/null 2>&1 || return 1
    git -C "$dir" clean -fd >/dev/null 2>&1 || return 1
  fi
  if [ -n "${OUT_DIR:-}" ] && [ "${WORKTREE:-}" = "$dir" ] && [ -d "$OUT_DIR" ]; then
    # stale nochange.txt or partial output must not leak into the next attempt
    find "$OUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + >/dev/null 2>&1 || return 1
  fi
  return 0
}

slot_run_retry() { # slot_run_retry <cmd> <dir> <prompt> <out> <stdout> [stderr] [max-secs] [max-min] [role]
  # Same contract as slot_run, but every attempt is watched by slot_run_guarded:
  # a call that makes no progress for SLOT_IDLE_MIN minutes is hung and killed,
  # SLOT_MAX_MIN is the last-resort ceiling (worker/reviewer; the on-call call
  # passes its own ONCALL_TIMEOUT_MIN), and either counts as one failed call with
  # a single retry. A rate/usage-limit failure waits with exponential backoff and
  # retries the same call from an identical tree. BELT_NO_SLEEP=1 makes the waits
  # instant for tests. Sets SLOT_RATE_LIMITED=1 when the 6h budget ran out,
  # SLOT_KILLED=1 when the call gave up after its single kill retry, and
  # SLOT_FAIL_TEXT to the human reason (hung or hard ceiling).
  local cmd=${1:?} dir=${2:?} prompt=${3:?} out=${4:?} stdoutf=${5:?} stderrf=${6:-}
  local max_secs=${7:-} max_label=${8:-} role=${9:-worker} idle_secs
  local rc attempt_err="" start now elapsed remaining delay=60 max=21600 start_sha="" timeouts=0
  idle_secs=$(slot_idle_seconds)
  [ -n "$max_secs" ] || max_secs=$(slot_max_seconds)
  [ -n "$max_label" ] || max_label=${SLOT_MAX_MIN:-180}
  SLOT_RATE_LIMITED=0
  SLOT_KILLED=0
  SLOT_FAIL_TEXT=""
  SLOT_KILL_REASON=""
  if ! start_sha=$(slot_start_sha "$dir"); then
    warn "could not read the starting commit of $dir; refusing to run the slot"
    return 1
  fi
  if [ -n "$stderrf" ]; then
    attempt_err=$(mktemp "${TMPDIR:-/tmp}/belt-slot-err.XXXXXX" 2>/dev/null) \
      || attempt_err="${TMPDIR:-/tmp}/belt-slot-err.$$.$RANDOM"
    : >"$attempt_err" 2>/dev/null || true
  fi
  start=$(date '+%s' 2>/dev/null) || start=0
  while :; do
    : >"$out" 2>/dev/null || true
    if [ -n "$stderrf" ]; then
      : >"$attempt_err" 2>/dev/null || true
      slot_run_guarded "$dir" "$out" "$stdoutf" "$attempt_err" "$idle_secs" "$max_secs" \
        slot_run "$cmd" "$dir" "$prompt" "$out" "$stdoutf" "$attempt_err" "$role"
      rc=$?
      cat "$attempt_err" >>"$stderrf" 2>/dev/null || true
    else
      slot_run_guarded "$dir" "$out" "$stdoutf" "" "$idle_secs" "$max_secs" \
        slot_run "$cmd" "$dir" "$prompt" "$out" "$stdoutf" "" "$role"
      rc=$?
    fi
    [ "$rc" -eq 0 ] && break
    if [ "$rc" -eq 124 ]; then
      case "${SLOT_KILL_REASON:-}" in
        hung) SLOT_FAIL_TEXT="hung: no output, no file change, no CPU for ${SLOT_IDLE_MIN:-20} min" ;;
        *) SLOT_FAIL_TEXT="hit the hard ceiling of ${max_label} min" ;;
      esac
      warn "slot ${SLOT_FAIL_TEXT}"
      log_file "slot ${SLOT_FAIL_TEXT}"
      if [ "$timeouts" -lt 1 ]; then
        timeouts=$((timeouts + 1))
        if ! slot_retry_reset "$dir" "$start_sha"; then
          warn "could not restore a clean worktree after the kill; giving up"
          SLOT_KILLED=1
          break
        fi
        continue
      fi
      SLOT_KILLED=1
      break
    fi
    if [ -n "$stderrf" ]; then
      slot_rate_limited "$out" "$stdoutf" "$attempt_err" || break
    else
      slot_rate_limited "$out" "$stdoutf" || break
    fi
    now=$(date '+%s' 2>/dev/null) || now=0
    elapsed=0
    if [ "$now" -gt 0 ] && [ "$now" -ge "$start" ]; then
      elapsed=$((now - start))
    fi
    remaining=$((max - elapsed))
    if [ "$remaining" -le 0 ]; then
      SLOT_RATE_LIMITED=1
      warn "still rate limited after 6 hours; giving up"
      break
    fi
    if [ "$delay" -ge "$remaining" ]; then
      # never wait past the deadline, and never start another attempt after it
      warn "rate limited; waiting ${remaining}s until the 6-hour deadline, then giving up"
      if [ "${BELT_NO_SLEEP:-0}" != "1" ]; then sleep "$remaining"; fi
      SLOT_RATE_LIMITED=1
      break
    fi
    if ! slot_retry_reset "$dir" "$start_sha"; then
      warn "could not restore a clean worktree before retrying; giving up"
      break
    fi
    warn "rate limited; retrying the same call in ${delay}s"
    if [ "${BELT_NO_SLEEP:-0}" != "1" ]; then sleep "$delay"; fi
    delay=$((delay * 2))
    [ "$delay" -le 1800 ] || delay=1800
  done
  rm -f "$attempt_err" 2>/dev/null || true
  return $rc
}

descendant_pids() { # descendant_pids <pid>; every process below pid, deepest first
  local pid=${1:?} child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    descendant_pids "$child"
  done
  printf '%s\n' "$pid"
}

kill_tree() { # kill_tree <pid>; TERM then KILL the whole process tree
  # macOS has no setsid: the slot's own children must be found by walking the
  # tree. Killing only the wrapper leaves agents running after the timeout.
  local pid=${1:?} pids p c
  pids=$(descendant_pids "$pid")
  [ -n "$pids" ] || pids=$pid
  # deepest first, so a parent cannot spawn a replacement after its children die
  for p in $pids; do kill -TERM "$p" 2>/dev/null || true; done
  sleep 1
  for p in $pids; do
    if kill -0 "$p" 2>/dev/null; then
      # include anything this survivor spawned after the TERM pass
      for c in $(descendant_pids "$p"); do kill -KILL "$c" 2>/dev/null || true; done
    fi
  done
  return 0
}

run_with_timeout() { # run_with_timeout <seconds> <command...>; 124 on timeout
  # macOS has no 'timeout': run in the background and kill the whole tree when
  # time is up, never just the wrapper process. Elapsed-time caps are fine for
  # short, deterministic work (checks, the full suite, slot-test); live model
  # calls are watched by slot_run_guarded instead, which kills on idleness.
  local secs=${1:?} pid waited=0 rc
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill_tree "$pid"
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
  rc=$?
  return $rc
}

# ------------------------------------------------------ slot progress/idle ---

slot_cpu_cs() { # slot_cpu_cs <pid>; CPU time of the whole tree in centiseconds
  local pid=${1:-} p t total=0
  case "$pid" in ''|*[!0-9]*) printf '0\n'; return 0 ;; esac
  for p in $(descendant_pids "$pid"); do
    t=$(ps -o time= -p "$p" 2>/dev/null | tr -d ' \n') || continue
    [ -n "$t" ] || continue
    t=$(printf '%s\n' "$t" | awk -F'[:.]' '
      NF == 3 { printf "%d\n", $1 * 6000 + $2 * 100 + $3; next }
      NF == 4 { printf "%d\n", $1 * 360000 + $2 * 6000 + $3 * 100 + $4; next }
      { print 0 }')
    case "$t" in ''|*[!0-9]*) t=0 ;; esac
    total=$((total + t))
  done
  printf '%s\n' "$total"
}

slot_output_bytes() { # slot_output_bytes <file...>; total bytes of the slot's output files
  local f n total=0
  for f in "$@"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    n=$(wc -c <"$f" 2>/dev/null | tr -d ' ') || n=0
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    total=$((total + n))
  done
  printf '%s\n' "$total"
}

slot_progress_sig() { # slot_progress_sig <pid> <out> <stdout> <stderr>; sizes + CPU time
  printf '%s:%s\n' "$(slot_output_bytes "$2" "$3" "$4")" "$(slot_cpu_cs "$1")"
}

slot_dir_changed_since() { # slot_dir_changed_since <dir> <stamp-file>; 0 when a file changed after the stamp
  # Cheap form of "newest mtime under the dir": find stops at the first file
  # newer than the stamp, and .git is pruned (an agent's own git bookkeeping is
  # not progress in the work). Called once a second, so it must stay cheap.
  local dir=${1:-} stamp=${2:-}
  [ -d "$dir" ] && [ -f "$stamp" ] || return 1
  find "$dir" -name .git -prune -o -newer "$stamp" -print 2>/dev/null | head -n 1 | grep -q .
}

slot_newest_mtime() { # slot_newest_mtime <dir>; newest mtime under dir (ignoring .git), 0 if none
  local dir=${1:-}
  [ -d "$dir" ] || { printf '0\n'; return 0; }
  {
    if stat -c '%Y' "$dir" >/dev/null 2>&1; then
      find "$dir" -name .git -prune -o -exec stat -c '%Y' {} + 2>/dev/null
    else
      find "$dir" -name .git -prune -o -exec stat -f '%m' {} + 2>/dev/null
    fi
  } | awk 'BEGIN { m = 0 } $1 + 0 > m { m = $1 + 0 } END { printf "%d\n", m }'
}

slot_out_newest_mtime() { # slot_out_newest_mtime <ticket-dir>; newest mtime of a slot's own output files
  local dir=${1:-} f m newest=0
  for f in log worker.log worker-out.txt reviewer.log reviewer-out.txt verdict.txt \
    oncall.out oncall.err prompt.txt review-prompt.txt; do
    m=$(file_mtime "$dir/$f") || continue
    [ "$m" -gt "$newest" ] && newest=$m
  done
  printf '%s\n' "$newest"
}

slot_run_guarded() { # slot_run_guarded <dir> <out> <stdout> <stderr> <idle-secs> <max-secs> <command...>
  # A slot call is HUNG when, for <idle-secs>, none of its output files grew,
  # no file in <dir> changed and its process tree used no CPU: then the whole
  # tree is killed and the call returns 124 as failed. Elapsed time alone never
  # kills a call that is still working; <max-secs> is only a last-resort ceiling.
  # Sets SLOT_KILL_REASON to hung or max so the caller can say why.
  local dir=${1:?} outf=${2:-} stdoutf=${3:-} stderrf=${4:-}
  local idle=${5:?} max=${6:?} pid stamp last sig waited=0 idle_waited=0 rc
  shift 6
  SLOT_KILL_REASON=""
  stamp=$(mktemp "${TMPDIR:-/tmp}/belt-slot-stamp.XXXXXX" 2>/dev/null) \
    || stamp="${TMPDIR:-/tmp}/belt-slot-stamp.$$.$RANDOM"
  : >"$stamp" 2>/dev/null || stamp=""
  "$@" &
  pid=$!
  last=$(slot_progress_sig "$pid" "$outf" "$stdoutf" "$stderrf")
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$max" ]; then
      SLOT_KILL_REASON=max
      kill_tree "$pid"
      wait "$pid" 2>/dev/null || true
      rm -f "$stamp" 2>/dev/null || true
      return 124
    fi
    if [ "$idle_waited" -ge "$idle" ]; then
      SLOT_KILL_REASON=hung
      kill_tree "$pid"
      wait "$pid" 2>/dev/null || true
      rm -f "$stamp" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
    sig=$(slot_progress_sig "$pid" "$outf" "$stdoutf" "$stderrf")
    if [ "$sig" = "$last" ] && ! slot_dir_changed_since "$dir" "$stamp"; then
      idle_waited=$((idle_waited + 1))
    else
      idle_waited=0
      last=$sig
    fi
    touch "$stamp" 2>/dev/null || true
  done
  wait "$pid"
  rc=$?
  rm -f "$stamp" 2>/dev/null || true
  return $rc
}

last_nonempty_line() { # last non-blank line of a file, CR stripped and trimmed
  local line
  line=$(grep -v '^[[:space:]]*$' "${1:-}" 2>/dev/null | tail -n 1 | tr -d '\r') || line=""
  trim_str "$line"
}

answer_is_ok() { # answer_is_ok <file>; only when the last non-empty line is exactly OK
  # Case-insensitive and one optional trailing period: "NOT OK" or an echoed
  # prompt must never pass a slot test.
  local last
  last=$(last_nonempty_line "${1:-}")
  last=${last%.}
  last=$(trim_str "$last")
  [ -n "$last" ] || return 1
  [ "$(printf '%s' "$last" | tr '[:lower:]' '[:upper:]')" = "OK" ]
}

slot_test() { # slot_test [project-dir]; one PASS/FAIL line per slot, 1 if any fails
  local tmp prompt out stdoutf stderrf name cmd key role fails=0 rc secs=180 answer names
  load_config "${1:-}" || { warn "could not load config"; return 1; }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/belt-slot-test.XXXXXX" 2>/dev/null) || {
    warn "cannot create a temp dir for slot-test"
    return 1
  }
  names="worker reviewer"
  [ -n "${RISKY_REVIEWER_CMD:-}" ] && names="$names risky-reviewer"
  [ -n "${ONCALL_CMD:-}" ] && names="$names on-call"
  for name in $names; do
    case "$name" in
      worker)
        cmd=${WORKER_CMD:-}
        key="WORKER_CMD"
        role=worker
        ;;
      reviewer)
        cmd=${REVIEWER_CMD:-}
        key="REVIEWER_CMD"
        role=reviewer
        ;;
      on-call)
        cmd=${ONCALL_CMD:-}
        key="ONCALL_CMD"
        role=oncall
        ;;
      *)
        cmd=${RISKY_REVIEWER_CMD:-}
        key="RISKY_REVIEWER_CMD"
        role=reviewer
        ;;
    esac
    if [ -z "$cmd" ]; then
      printf 'FAIL %s: %s is not set in belt.conf\n' "$name" "$key"
      fails=$((fails + 1))
      continue
    fi
    mkdir -p "$tmp/$name" || { printf 'FAIL %s: cannot create temp dir\n' "$name"; fails=$((fails + 1)); continue; }
    prompt="$tmp/$name.prompt"
    printf 'Reply with exactly the word OK and nothing else. Do not edit any files.\n' >"$prompt"
    out="$tmp/$name.out"
    stdoutf="$tmp/$name.stdout"
    stderrf="$tmp/$name.stderr"
    : >"$out"
    rc=0
    # stderr stays in its own file: it is diagnostics, never the answer
    run_with_timeout "$secs" slot_run "$cmd" "$tmp/$name" "$prompt" "$out" "$stdoutf" "$stderrf" "$role" || rc=$?
    answer="$out"
    [ -s "$answer" ] || answer="$stdoutf"
    if [ "$rc" -eq 0 ] && answer_is_ok "$answer"; then
      printf 'PASS %s\n' "$name"
    else
      printf 'FAIL %s (exit %s)\n' "$name" "$rc"
      if [ -s "$answer" ]; then
        tail -n 3 "$answer" | awk '{ print "  " $0 }'
      elif [ -s "$stderrf" ]; then
        tail -n 3 "$stderrf" | awk '{ print "  " $0 }'
      else
        printf '  (no output)\n'
      fi
      fails=$((fails + 1))
    fi
  done
  rm -rf "$tmp"
  [ "$fails" -eq 0 ]
}

base_branch() { # BASE_BRANCH, else repo default branch, else main
  local b
  if [ -n "${BASE_BRANCH:-}" ]; then
    printf '%s\n' "$BASE_BRANCH"
    return 0
  fi
  b=$(git -C "${PROJECT:-$PWD}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  if [ -z "$b" ]; then
    if [ -n "${REPO:-}" ]; then
      b=$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) || b=""
    else
      b=$(cd "${PROJECT:-$PWD}" 2>/dev/null && gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) || b=""
    fi
  fi
  printf '%s\n' "${b:-main}"
}

repo_slug() { # owner/repo, from REPO or gh
  local s
  if [ -n "${REPO:-}" ]; then
    printf '%s\n' "$REPO"
    return 0
  fi
  s=$(cd "${PROJECT:-$PWD}" 2>/dev/null && gh repo view --json nameWithOwner -q .nameWithOwner 2>&1) || {
    warn "gh repo view failed: $(printf '%s' "$s" | head -n 2)"
    return 1
  }
  s=$(printf '%s' "$s" | head -n 1 | tr -d '[:space:]')
  if [ -z "$s" ] || [ "${s#*/}" = "$s" ]; then
    warn "could not resolve repo slug"
    return 1
  fi
  printf '%s\n' "$s"
}

state_dir_for() { # state_dir_for owner/repo
  local slug=${1:?slug}
  printf '%s/%s__%s\n' "${BELT_HOME%/}" "${slug%%/*}" "${slug##*/}"
}

claim_label() { # the label a claimed ticket wears (CLAIM_LABEL)
  printf '%s\n' "${CLAIM_LABEL:-claimed:belt}"
}

branch_prefix() { # the ticket branch prefix, always with one trailing slash
  local p=${BRANCH_PREFIX:-belt/}
  printf '%s/\n' "${p%/}"
}

belt_branch_for() { # belt_branch_for <issue>; the ticket's branch name
  printf '%s%s\n' "$(branch_prefix)" "${1:?}"
}

path_has_dotdot() { # true when any path component is exactly '..'
  case "/${1:-}/" in
    */../*) return 0 ;;
  esac
  return 1
}

physical_path() { # physical_path <path>; absolute path with every existing symlink resolved
  local p=${1:-} part rest base abs
  [ -n "$p" ] || return 1
  case "$p" in
    /*) ;;
    *) p="$PWD/$p" ;;
  esac
  # resolve the longest existing prefix with cd -P, then re-add the missing tail
  rest=""
  part=$p
  while :; do
    if [ -d "$part" ]; then
      abs=$(cd -P "$part" 2>/dev/null && pwd) || return 1
      break
    fi
    base=$(basename "$part")
    case "$base" in
      ''|.|/)
        abs=$(cd -P "${part:-/}" 2>/dev/null && pwd) || return 1
        break
        ;;
    esac
    rest="/$base$rest"
    part=$(dirname "$part")
    case "$part" in
      ''|.) part="/" ;;
    esac
  done
  [ "$abs" = "/" ] || abs=${abs%/}
  printf '%s%s\n' "$abs" "$rest"
}

ensure_under_belt_home() { # refuse worktree operations outside BELT_HOME (physical, no '..')
  local p=${1:-} home target
  [ -n "$p" ] || { warn "refusing empty path"; return 1; }
  if path_has_dotdot "$p"; then
    warn "refusing path containing '..': $p"
    return 1
  fi
  home=$(physical_path "${BELT_HOME%/}") || { warn "cannot resolve BELT_HOME: ${BELT_HOME:-}"; return 1; }
  target=$(physical_path "$p") || { warn "cannot resolve path: $p"; return 1; }
  case "$target" in
    "$home"/*) return 0 ;;
  esac
  warn "refusing path outside BELT_HOME ($home): $p -> $target"
  return 1
}

# --------------------------------------------------------- risky/ignored ---

is_risky_path() { # matches RISKY_PATHS globs; '*' spans '/', trailing '/' = folder
  local path=${1:-} g folder rc=1 had_f=0
  [ -n "${RISKY_PATHS:-}" ] || return 1
  case "$-" in *f*) had_f=1 ;; esac
  set -f # RISKY_PATHS is a list of patterns, not a list of files in $PWD
  for g in $RISKY_PATHS; do
    case "$g" in
      */)
        folder=${g%/}
        [ -n "$folder" ] || continue
        # folder patterns may contain globs: match the folder itself and
        # anything below it. set -f above keeps this from pathname-expanding.
        # shellcheck disable=SC2254
        case "$path" in
          $folder|$folder/*) rc=0 ;;
        esac
        ;;
      *)
        # shellcheck disable=SC2254
        case "$path" in
          $g) rc=0 ;;
        esac
        ;;
    esac
    [ "$rc" -eq 0 ] && break
  done
  [ "$had_f" -eq 1 ] || set +f
  return $rc
}

path_is_ignored() { # never stage these, whatever git says
  case "${1:-}" in
    .env*|*/.env*) return 0 ;;
    *.pem|*.key) return 0 ;;
    *secret*|*Secret*|*SECRET*) return 0 ;;
    .belt|.belt/*|*/.belt|*/.belt/*) return 0 ;;
    node_modules|node_modules/*|*/node_modules|*/node_modules/*) return 0 ;;
    .DS_Store|*/.DS_Store) return 0 ;;
  esac
  return 1
}

# ------------------------------------------------------------------ locks ---

BELT_LOCK_GRACE_SECONDS=${BELT_LOCK_GRACE_SECONDS:-10}

lock_self_pid() { # print the real PID of this shell, even inside a subshell
  local tmp p
  if [ -n "${BASHPID:-}" ]; then
    printf '%s\n' "$BASHPID"
    return 0
  fi
  # bash 3.2 has no BASHPID. A direct child sh reports our real PID in PPID.
  # Do not use $(...) around the pid read: that forks a subshell and would
  # report the substitution's PID instead of ours.
  tmp=$(mktemp "${TMPDIR:-/tmp}/belt-selfpid.XXXXXX" 2>/dev/null) \
    || tmp="${TMPDIR:-/tmp}/belt-selfpid.$$.$RANDOM"
  if sh -c 'printf "%s\n" "$PPID"' >"$tmp" 2>/dev/null; then
    p=$(cat "$tmp" 2>/dev/null) || p=""
  else
    p=""
  fi
  rm -f "$tmp"
  case "$p" in
    ''|*[!0-9]*) p=$$ ;;
  esac
  printf '%s\n' "$p"
}

lock_age_seconds() { # lock_age_seconds <lockdir>; 0 when unknown (never delete on unknown)
  local dir=${1:-} mtime now
  now=$(date '+%s' 2>/dev/null) || { printf '0\n'; return 0; }
  case "$now" in ''|*[!0-9]*) printf '0\n'; return 0 ;; esac
  if mtime=$(stat -c '%Y' "$dir" 2>/dev/null); then :
  elif mtime=$(stat -f '%m' "$dir" 2>/dev/null); then :
  else printf '0\n'; return 0
  fi
  case "$mtime" in ''|*[!0-9]*) printf '0\n'; return 0 ;; esac
  [ "$now" -ge "$mtime" ] || { printf '0\n'; return 0; }
  printf '%s\n' $((now - mtime))
}

lock_holder_alive() { # lock_holder_alive <lockdir>
  local p
  [ -f "${1:-}/pid" ] || return 1
  p=$(cat "$1/pid" 2>/dev/null) || return 1
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null
}

lock_nonce() { # a fresh, unique holder token
  printf '%s.%s.%s\n' "$(lock_self_pid)" "$RANDOM$RANDOM" "$(date '+%s' 2>/dev/null || echo 0)"
}

reclaim_stale_lock() { # reclaim_stale_lock <lockdir> <stale-pid> <stale-nonce>; 0 = removed
  # Only a lock whose holder pid is provably gone may be removed. The removal
  # itself is an atomic rename to a unique name, so two reclaimers never both
  # delete the same path; if the rename moved a lock that changed in the
  # meantime (a replacement), put it back instead of deleting it.
  local dir=${1:-} pid=${2:-} nonce=${3:-} tomb tpid tnonce
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null && return 1
  if [ -n "${BELT_LOCK_RECLAIM_HOOK:-}" ]; then
    # test hook: simulate a concurrent reclaimer replacing the lock
    eval "$BELT_LOCK_RECLAIM_HOOK" >/dev/null 2>&1 || true
  fi
  tomb="$dir.stale.$(lock_self_pid).$RANDOM$RANDOM"
  if ! mv "$dir" "$tomb" 2>/dev/null; then return 1; fi
  tpid=$(cat "$tomb/pid" 2>/dev/null) || tpid=""
  tnonce=$(cat "$tomb/nonce" 2>/dev/null) || tnonce=""
  if [ "$tpid" = "$pid" ] && [ "$tnonce" = "$nonce" ] && ! kill -0 "$tpid" 2>/dev/null; then
    rm -rf "$tomb"
    warn "removing stale lock $dir"
    return 0
  fi
  warn "not removing $dir: the lock changed while reclaiming it"
  if [ -e "$dir" ]; then
    warn "could not restore $dir; the live lock is left at $tomb"
  elif ! mv "$tomb" "$dir" 2>/dev/null; then
    warn "could not restore $dir from $tomb"
  fi
  return 1
}

acquire_lock() { # acquire_lock <lockdir> [wait-seconds]
  local dir=${1:-} wait=${2:-0} waited=0 nonce
  case "$dir" in ''|/) return 1 ;; esac
  while :; do
    if mkdir "$dir" 2>/dev/null; then
      # nonce first, pid last: a lock that has a pid always has its nonce too
      nonce=$(lock_nonce)
      if ! printf '%s\n' "$nonce" >"$dir/nonce.tmp" 2>/dev/null \
        || ! mv -f "$dir/nonce.tmp" "$dir/nonce" 2>/dev/null \
        || ! lock_self_pid >"$dir/pid.tmp" 2>/dev/null \
        || ! mv -f "$dir/pid.tmp" "$dir/pid" 2>/dev/null; then
        rm -rf "$dir"
        return 1
      fi
      return 0
    fi
    if lock_holder_alive "$dir"; then
      [ "$wait" -le 0 ] && return 1
    elif [ ! -s "$dir/pid" ]; then
      # No pid: the holder may still be between mkdir and its pid write (or it
      # died there). We cannot prove it is gone, so never steal it; age is no
      # proof that the holder is dead.
      warn "lock $dir has no holder pid; refusing to steal it"
      [ "$wait" -le 0 ] && return 1
    else
      case "$(cat "$dir/pid" 2>/dev/null)" in
        ''|*[!0-9]*)
          warn "lock $dir has an invalid holder pid; refusing to steal it"
          [ "$wait" -le 0 ] && return 1
          ;;
        *)
          if reclaim_stale_lock "$dir" "$(cat "$dir/pid" 2>/dev/null)" "$(cat "$dir/nonce" 2>/dev/null)"; then
            continue
          fi
          ;;
      esac
    fi
    if [ "$waited" -ge "$wait" ]; then return 1; fi
    sleep 2
    waited=$((waited + 2))
  done
}

release_lock() { # release_lock <lockdir>; only the real holder may remove it
  local dir=${1:-} tmp
  case "$dir" in ''|/) return 0 ;; esac
  [ -f "$dir/pid" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/belt-lock-rel.XXXXXX" 2>/dev/null) \
    || tmp="${TMPDIR:-/tmp}/belt-lock-rel.$$.$RANDOM"
  if ! lock_self_pid >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  if cmp -s "$tmp" "$dir/pid"; then
    rm -rf "$dir"
  else
    rm -f "$tmp"
  fi
  return 0
}

device_run() { # device_run <name> <command...>; hold DEVICE_LOCK when set
  local name=${1:-device} rc=0
  shift
  if [ -z "${DEVICE_LOCK:-}" ]; then
    "$@"
    return $?
  fi
  if ! acquire_lock "$DEVICE_LOCK" 1800; then
    warn "device lock timeout: $DEVICE_LOCK ($name)"
    return 125
  fi
  "$@" || rc=$?
  release_lock "$DEVICE_LOCK"
  return $rc
}

# ------------------------------------------------------ check semaphore ---

check_slot_root() { # one directory of slot locks under BELT_HOME
  printf '%s/check-slots\n' "${BELT_HOME%/}"
}

acquire_check_slot() { # wait for one of CHECK_SLOTS check slots; sets CHECK_SLOT_LOCK
  local root i lock
  root=$(check_slot_root)
  mkdir -p "$root" || { warn "cannot create $root"; return 1; }
  while :; do
    i=1
    while [ "$i" -le "${CHECK_SLOTS:-1}" ]; do
      lock="$root/slot-$i.lock"
      if acquire_lock "$lock" 0; then
        CHECK_SLOT_LOCK=$lock
        check_start_gap
        return 0
      fi
      i=$((i + 1))
    done
    sleep 2
  done
}

check_start_gap() { # space check starts CHECK_START_GAP_SEC apart across slots
  local gap=${CHECK_START_GAP_SEC:-0} f last now wait
  [ "$gap" -gt 0 ] 2>/dev/null || return 0
  f="$(check_slot_root)/last-start"
  acquire_lock "$f.lock" 600 || return 0
  last=$(cat "$f" 2>/dev/null) || last=0
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  now=$(date '+%s')
  wait=$((last + gap - now))
  if [ "$wait" -gt 0 ] && [ "$wait" -le "$gap" ]; then
    sleep "$wait"
  fi
  date '+%s' >"$f"
  release_lock "$f.lock"
  return 0
}

release_check_slot() { # release the slot this process holds, if any
  if [ -n "${CHECK_SLOT_LOCK:-}" ]; then
    release_lock "$CHECK_SLOT_LOCK"
  fi
  CHECK_SLOT_LOCK=""
  return 0
}

run_check_command() { # run_check_command <name> <shell-cmd>; slot -> device lock -> guarded command
  # Checks run code a worker wrote: same throwaway HOME and sandbox as a slot,
  # but without the harness env (CHECKS_UNSANDBOXED=1 drops only the sandbox).
  local name=${1:?} cmd=${2:?} rc=0
  acquire_check_slot || return 1
  device_run "$name" guard_exec check "$PWD" "$cmd" || rc=$?
  release_check_slot
  return $rc
}

# ------------------------------------------------------------- frontier ---

text_blockers() { # text_blockers <issue-body>; numbers named by 'Blocked by #N' lines
  printf '%s\n' "${1:-}" | tr -d '\r' \
    | grep -iE '^[[:space:]]*(-[[:space:]]+)?blocked[[:space:]]+by[[:space:]]*:?[[:space:]]*#' \
    | grep -oE '#[0-9]+' | tr -d '#'
  return 0
}

text_blocker_refs() { # text_blocker_refs <issue-body>; 'repo<TAB>number' lines from 'Blocked by' lines
  # A bare '#N' means this repo; 'owner/repo#N' and issue URLs mean that repo.
  local body=${1:-} ref rest repo num slug=${SLUG:-}
  printf '%s\n' "$body" | tr -d '\r' \
    | grep -iE '^[[:space:]]*(-[[:space:]]+)?blocked[[:space:]]+by[[:space:]]*:?[[:space:]]*' \
    | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+|#[0-9]+' \
    | while IFS= read -r ref || [ -n "$ref" ]; do
        case "$ref" in
          https://github.com/*|http://github.com/*)
            rest=${ref#*github.com/}
            repo=${rest%%/issues/*}
            num=${rest##*/}
            ;;
          \#*)
            repo=$slug
            num=${ref#\#}
            ;;
          *'#'*)
            repo=${ref%%#*}
            num=${ref##*#}
            ;;
          *)
            continue
            ;;
        esac
        case "$num" in ''|*[!0-9]*) continue ;; esac
        [ -n "$repo" ] || continue
        printf '%s\t%s\n' "$repo" "$num"
      done
  return 0
}

native_blockers() { # native_blockers <slug> <issue>; 'repo<TAB>number<TAB>state' lines; 1 on unreadable API
  local slug=${1:?} n=${2:?} page=1 per=100 chunk len=0 all="" out rc
  while [ "$page" -le 50 ]; do
    out=$(gh api "repos/$slug/issues/$n/dependencies/blocked_by?per_page=$per&page=$page" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
      # a 404 on the first page is the documented answer for "no native links";
      # a failure on any later page is unreadable (never silently truncate)
      if [ "$page" -eq 1 ] && printf '%s' "$out" | grep -qiE '(^|[^0-9])404([^0-9]|$)|not found'; then
        return 0
      fi
      warn "could not read native blockers for #$n: $(printf '%s' "$out" | head -n 1)"
      return 1
    fi
    chunk=$out
    if ! printf '%s' "$chunk" | jq -e 'type == "array"' >/dev/null 2>&1; then
      warn "native blockers for #$n are not a JSON array (page $page)"
      return 1
    fi
    len=$(printf '%s' "$chunk" | jq 'length' 2>/dev/null) || {
      warn "could not count native blockers for #$n (page $page)"
      return 1
    }
    case "$len" in ''|*[!0-9]*)
      warn "could not count native blockers for #$n (page $page)"
      return 1
      ;;
    esac
    all="$all$chunk"$'\n'
    [ "$len" -lt "$per" ] && break
    page=$((page + 1))
  done
  if [ "$page" -gt 50 ] && [ "$len" -ge "$per" ]; then
    warn "native blocker list for #$n is too large to read safely (> $((50 * per)) entries)"
    return 1
  fi
  # the API entry itself says which repository it belongs to; never match by number alone
  printf '%s' "$all" | jq -r --arg slug "$slug" '
      .[]
      | (if (.repository.full_name // "") != "" then .repository.full_name
         elif (.repository_url // "") != "" then (.repository_url | sub("^https?://api\\.github\\.com/repos/"; ""))
         elif (.html_url // "") != "" then (.html_url | sub("^https?://github\\.com/"; "") | sub("/issues/[0-9]+$"; ""))
         else "" end) as $repo
      | "\(if $repo == "" then $slug else $repo end)\t\(.number)\t\((.state // "" | tostring | ascii_downcase))"' 2>/dev/null \
    || { warn "could not parse native blockers for #$n"; return 1; }
  return 0
}

issue_state() { # issue_state <slug> <number>; lowercased state, 1 when unreadable
  local out
  out=$(gh api "repos/$1/issues/$2" --jq '.state' 2>/dev/null) || return 1
  out=$(printf '%s' "$out" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

issue_blocked() { # issue_blocked <issue> <body>; 0 = blocked (or unreadable, fail closed)
  # sets BLOCK_REASON. Native links and text blockers both count; a blocker
  # whose state is not provably 'closed' blocks. Blockers match on repository
  # and number, never on the number alone.
  local n=${1:?} body=${2:-} native text repo num state
  BLOCK_REASON=""
  if ! native=$(native_blockers "$SLUG" "$n"); then
    BLOCK_REASON="could not read native blockers for #$n"
    return 0
  fi
  text=$(text_blocker_refs "$body")
  while IFS=$'\t' read -r repo num; do
    [ -n "$num" ] || continue
    [ -n "$repo" ] || repo=$SLUG
    state=$(printf '%s\n' "$native" | awk -F'\t' -v r="$repo" -v k="$num" '$1 == r && $2 == k { print $3; exit }')
    if [ -z "$state" ] && ! state=$(issue_state "$repo" "$num"); then
      BLOCK_REASON="could not read the state of blocker $repo#$num"
      return 0
    fi
    if [ "$state" != "closed" ]; then
      BLOCK_REASON="blocked by $repo#$num (${state:-unknown})"
      return 0
    fi
  done <<EOF
$text
EOF
  while IFS=$'\t' read -r repo num state; do
    [ -n "$num" ] || continue
    if [ "$state" != "closed" ]; then
      BLOCK_REASON="blocked by ${repo:-$SLUG}#$num (${state:-unknown})"
      return 0
    fi
  done <<EOF
$native
EOF
  return 1
}

# ------------------------------------------------------- file clashes ---

path_exists_in_repo() { # path_exists_in_repo <path>; an existing file in the project/worktree
  local p=${1:-} root
  [ -n "$p" ] || return 1
  case "$p" in
    /*|..|../*|*/..|*/../*) return 1 ;;
  esac
  for root in "${PROJECT:-}" "${WORKTREE:-}"; do
    [ -n "$root" ] || continue
    [ -e "$root/$p" ] && return 0
  done
  return 1
}

named_files() { # named_files <issue-body>; paths named on 'Files:' lines, one per line
  local body=${1:-} line rest tok
  printf '%s\n' "$body" | tr -d '\r' | while IFS= read -r line; do
    case "$line" in
      [Ff][Ii][Ll][Ee][Ss]:*) rest=${line#*:} ;;
      *) continue ;;
    esac
    # ordinary comma/space separated tokens (backticked chunks are handled below)
    printf '%s' "$rest" | sed -e 's/`[^`]*`//g' | tr ',' ' ' | tr ' ' '\n' | while IFS= read -r tok || [ -n "$tok" ]; do
      tok=$(trim_str "$tok")
      case "$tok" in
        ''|*:*) continue ;;
      esac
      case "$tok" in
        ./*) tok=${tok#./} ;;
      esac
      printf '%s\n' "$tok"
    done
    # backticked paths count when they look like paths or name a real repo file
    printf '%s' "$rest" | grep -o '`[^`]*`' 2>/dev/null | sed -e 's/^`//' -e 's/`$//' | while IFS= read -r tok || [ -n "$tok" ]; do
      tok=$(trim_str "$tok")
      [ -n "$tok" ] || continue
      case "$tok" in
        */*|*.*) ;;
        *) path_exists_in_repo "$tok" || continue ;;
      esac
      case "$tok" in
        ./*) tok=${tok#./} ;;
      esac
      printf '%s\n' "$tok"
    done
  done
  return 0
}

files_clash() { # files_clash <new-files> <running-files>; 0 when any exact path overlaps
  local new=${1:-} running=${2:-} f
  [ -n "$new" ] && [ -n "$running" ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if printf '%s\n' "$running" | grep -Fqx -- "$f"; then
      return 0
    fi
  done <<EOF
$new
EOF
  return 1
}

ticket_hold_reason() { # ticket_hold_reason <issue> <body> <running-files>
  # sets TICKET_NAMED_FILES and TICKET_HOLD_REASON (empty = startable). It must
  # not print the answer: callers need the globals, and $(...) would subshell them.
  TICKET_NAMED_FILES=""
  TICKET_HOLD_REASON=""
  if issue_blocked "$1" "$2"; then
    TICKET_HOLD_REASON=$BLOCK_REASON
    return 0
  fi
  TICKET_NAMED_FILES=$(named_files "$2")
  if files_clash "$TICKET_NAMED_FILES" "${3:-}"; then
    TICKET_HOLD_REASON="files clash with a running ticket"
  fi
  return 0
}

issue_body_of() { # issue_body_of <issue>; body on stdout, 1 when unreadable
  local out
  out=$(gh issue view "$1" -R "$SLUG" --json body -q .body 2>/dev/null) || return 1
  printf '%s\n' "$out"
  return 0
}

issue_is_claimed() { # issue_is_claimed <issue>; 0 = claim label, 1 = not claimed, 2 = unreadable
  local out
  out=$(gh issue view "$1" -R "$SLUG" --json labels -q '.labels[].name' 2>/dev/null) || return 2
  printf '%s\n' "$out" | grep -qx -- "$(claim_label)"
}

count_active() { # count_active <"pid:n ...">
  printf '%s\n' "${1:-}" | wc -w | tr -d ' '
}

under_parallel_cap() { # under_parallel_cap <"pid:n ...">; MAX_PARALLEL=0 means no cap
  [ "${MAX_PARALLEL:-0}" -eq 0 ] || [ "$(count_active "$1")" -lt "$MAX_PARALLEL" ]
}

# ----------------------------------------------------------------- labels ---

fetch_queue() { # open ready-for-agent issues nobody else owns, oldest first
  # Page through every issue instead of filtering a 100-issue window: excluded
  # labels are filtered locally, so a single page could hide eligible tickets.
  local page=1 per=100 chunk n all="" parsed
  [ -n "${SLUG:-}" ] || return 1
  while [ "$page" -le 50 ]; do
    if ! chunk=$(gh api "repos/$SLUG/issues?state=open&labels=ready-for-agent&per_page=$per&page=$page" 2>/dev/null); then
      return 1
    fi
    if ! printf '%s' "$chunk" | jq -e 'type == "array"' >/dev/null 2>&1; then
      return 1
    fi
    n=$(printf '%s' "$chunk" | jq 'length' 2>/dev/null) || return 1
    case "$n" in ''|*[!0-9]*) return 1 ;; esac
    all="$all$chunk"$'\n'
    [ "$n" -lt "$per" ] && break
    page=$((page + 1))
  done
  if [ "$page" -gt 50 ] && [ "${n:-0}" -ge "$per" ]; then
    # still more pages than the safety cap: never pretend the queue is empty
    warn "ready-for-agent queue is too large to read safely (> $((50 * per)) issues)"
    return 1
  fi
  parsed=$(printf '%s' "$all" | jq -s -r --arg claim "$(claim_label)" '
      [ .[][] ]
      | map(select(.pull_request == null))
      | map(select(
          ([ .labels[].name ]
            | map(select(. == $claim or . == "stuck" or . == "needs-lead" or . == "needs-owner"))
            | length) == 0))
      | sort_by(.created_at)
      | .[].number' 2>/dev/null) || return 1
  printf '%s\n' "$parsed"
}

ensure_labels() { # ensure_labels <slug>; idempotent
  local slug=${1:?slug} l
  for l in "$(claim_label)" stuck needs-lead needs-owner ready-for-agent; do
    gh label create "$l" -R "$slug" --color ededed --description "managed by belt" --force \
      >/dev/null 2>&1 || warn "could not ensure label '$l' in $slug"
  done
  return 0
}

create_owner_issue() { # create_owner_issue <slug> <title> <body>; 0 = created/already open
  local slug=${1:?} title=${2:-} body=${3:-} existing out num
  [ -n "$title" ] || return 0
  title=$(trim_str "$title")
  title=$(truncate_str "$title" 80)
  [ -n "$title" ] || return 0
  existing=$(gh issue list -R "$slug" --state open --limit 200 --json title -q '.[].title' 2>/dev/null) || {
    warn "could not list open issues in $slug while deduplicating '$title'"
    existing=""
  }
  if [ -n "$existing" ] && printf '%s\n' "$existing" | grep -Fxq -- "$title"; then
    return 0
  fi
  if out=$(gh issue create -R "$slug" --title "$title" --label needs-owner --body "$body" 2>&1); then
    printf '%s\n' "$out" >>"${LOG:-/dev/null}" 2>/dev/null || true
    # the creation answer is the only trustworthy number: an issue list is
    # search-indexed and may not show an issue created a second ago
    num=$(printf '%s' "$out" | sed -n 's#.*/issues/\([0-9][0-9]*\).*#\1#p' | tail -n 1)
    case "$num" in ''|*[!0-9]*) num="" ;; esac
    if [ -n "$num" ] && [ -n "${BELT_OWNER_CREATED_LOG:-}" ]; then
      printf '%s\n' "$num" >>"$BELT_OWNER_CREATED_LOG" 2>/dev/null || true
    fi
    log "opened needs-owner issue: $title"
    return 0
  fi
  warn "could not open needs-owner issue: $title"
  return 1
}

# the slot guard is sourced last: it builds on physical_path and warn
# shellcheck source=guard.sh
[ -n "$BELT_LIB_DIR" ] && . "$BELT_LIB_DIR/guard.sh"

copy_template() { # copy_template <src> <dst>; never overwrite
  if [ -e "${2:-}" ]; then
    printf '%s exists, skipped\n' "$2"
    return 0
  fi
  mkdir -p "$(dirname "$2")" || return 1
  cp "$1" "$2" || return 1
  printf 'created %s\n' "$2"
  return 0
}

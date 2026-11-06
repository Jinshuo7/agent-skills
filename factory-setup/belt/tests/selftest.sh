#!/usr/bin/env bash
# tests/selftest.sh - offline tests for belt's pure functions.
set -u

ROOT=$(cd -P "$(dirname "$0")/.." && pwd) || exit 1
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/ticket.sh
. "$ROOT/lib/ticket.sh"
# shellcheck source=../lib/review.sh
. "$ROOT/lib/review.sh"
# belt itself for run_queue; the guard keeps main from running
BELT_SOURCED_ONLY=1
# shellcheck source=../belt
. "$ROOT/belt"

TMP=$(mktemp -d 2>/dev/null) || exit 1
trap 'rm -rf "$TMP"' EXIT
BELT_HOME="$TMP/belt-home"
# Tests must never see the real home.
mkdir -p "$TMP/home"; HOME="$TMP/home"; export HOME
LOG="$TMP/selftest.log"
# every temp file the code under test creates (throwaway HOMEs, stamps,
# profiles) must live under $TMP too, never in the real /tmp
TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR"
export TMPDIR
export BELT_HOME

fails=0
total=0

check_eq() { # check_eq <name> <expected> <actual>
  total=$((total + 1))
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

check_ok() { # check_ok <name> <command...>
  total=$((total + 1))
  local name=$1
  shift
  if "$@"; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n' "$name"
    fails=$((fails + 1))
  fi
}

check_no() { # check_no <name> <command...>
  total=$((total + 1))
  local name=$1
  shift
  if "$@"; then
    printf 'FAIL %s (unexpectedly true)\n' "$name"
    fails=$((fails + 1))
  else
    printf 'ok   %s\n' "$name"
  fi
}

# ---------------------------------------------------------------- weekdays ---

check_eq "dow monday" 1 "$(belt_dow 2025-01-06)"
check_eq "dow friday" 5 "$(belt_dow 2025-01-03)"
check_eq "dow saturday" 6 "$(belt_dow 2025-01-04)"
check_eq "dow sunday" 7 "$(belt_dow 2025-01-05)"
check_eq "dow leap day" 4 "$(belt_dow 2024-02-29)"

# ----------------------------------------------------------- pause windows ---

PAUSE_WINDOWS=""
PAUSE_TZ=""
check_no "empty PAUSE_WINDOWS never pauses" in_pause_window "2025-01-06 10:00"
check_eq "empty PAUSE_WINDOWS has no wait label" "" "$(pause_wait_label '2025-01-06 10:00')"
check_eq "empty PAUSE_WINDOWS never waits" "" \
  "$(BELT_NOW='2025-01-06 10:00' BELT_NO_SLEEP=1 pause_wait)"
check_eq "empty PAUSE_WINDOWS has no next pause" "" \
  "$(BELT_NOW='2025-01-06 10:00' next_pause_label)"

PAUSE_WINDOWS="Mon-Fri@09:00-12:00"
check_ok "window start pauses" in_pause_window "2025-01-06 09:00"
check_ok "inside a window pauses" in_pause_window "2025-01-06 11:59"
check_no "before a window" in_pause_window "2025-01-06 08:59"
check_no "after a window" in_pause_window "2025-01-06 12:30"
check_eq "pause wait label is the window end" "12:00" "$(pause_wait_label '2025-01-06 10:30')"
check_eq "pause_wait hook output" "paused, waiting until 12:00" \
  "$(BELT_NOW='2025-01-06 10:00' BELT_NO_SLEEP=1 pause_wait)"
check_eq "pause_wait off-window silent" "" "$(BELT_NOW='2025-01-06 12:00' pause_wait)"

# the end time is exclusive
check_no "window end is exclusive" in_pause_window "2025-01-06 12:00"

# weekday ranges cover every day between the two names; a single day also works
PAUSE_WINDOWS="Mon-Fri@09:00-10:00"
check_ok "weekday range includes monday" in_pause_window "2025-01-06 09:30"
check_ok "weekday range includes friday" in_pause_window "2025-01-03 09:30"
check_no "weekday range excludes saturday" in_pause_window "2025-01-04 09:30"
check_no "weekday range excludes sunday" in_pause_window "2025-01-05 09:30"
PAUSE_WINDOWS="Sat@10:00-11:00"
check_ok "a single weekday pauses" in_pause_window "2025-01-04 10:30"
check_no "a single weekday does not pause on friday" in_pause_window "2025-01-03 10:30"
PAUSE_WINDOWS="Sun-Tue@09:00-10:00"
check_ok "a wrapping weekday range pauses sunday" in_pause_window "2025-01-05 09:30"
check_ok "a wrapping weekday range pauses monday" in_pause_window "2025-01-06 09:30"
check_no "a wrapping weekday range excludes wednesday" in_pause_window "2025-01-08 09:30"

PAUSE_WINDOWS="Mon-Fri@09:00-12:00 Mon-Fri@14:00-18:00"
check_eq "next pause before work" "2025-01-06 09:00" "$(BELT_NOW='2025-01-06 08:00' next_pause_label)"
check_eq "next pause after lunch" "2025-01-06 14:00" "$(BELT_NOW='2025-01-06 12:30' next_pause_label)"
check_eq "next pause after hours" "2025-01-07 09:00" "$(BELT_NOW='2025-01-06 18:30' next_pause_label)"
check_eq "next pause from the weekend" "2025-01-06 09:00" "$(BELT_NOW='2025-01-04 10:00' next_pause_label)"

# PAUSE_TZ drives the clock and time math; BELT_NOW is read as a PAUSE_TZ time
pause_tz_math() (
  PAUSE_TZ="UTC"
  utc=$(belt_epoch '2025-01-06 00:00')
  PAUSE_TZ="Asia/Shanghai"
  shanghai=$(belt_epoch '2025-01-06 00:00')
  [ $((utc - shanghai)) -eq 28800 ]
)
check_ok "PAUSE_TZ is applied to time math" pause_tz_math
pause_tz_clock() (
  PAUSE_TZ="Asia/Shanghai"
  want=$(TZ=Asia/Shanghai date '+%s')
  got=$(belt_epoch "$(belt_now)")
  diff=$((got - want))
  [ "${diff#-}" -le 60 ]
)
check_ok "belt_now follows PAUSE_TZ" pause_tz_clock

# an invalid PAUSE_WINDOWS fails closed, with a plain message
pause_bad_config() ( # <bad-value>
  proj="$TMP/pause-bad"
  rm -rf "$proj"
  mkdir -p "$proj" || return 1
  printf 'PAUSE_WINDOWS="%s"\n' "$1" >"$proj/belt.conf"
  load_config "$proj" >/dev/null 2>"$TMP/pause-bad.err"
  rc=$?
  [ "$rc" -ne 0 ] && grep -q 'invalid PAUSE_WINDOWS' "$TMP/pause-bad.err"
)
check_ok "an unknown day in PAUSE_WINDOWS is refused" pause_bad_config "Funday@09:00-10:00"
check_ok "a reversed PAUSE_WINDOWS is refused" pause_bad_config "Mon@12:00-09:00"
check_ok "a malformed PAUSE_WINDOWS is refused" pause_bad_config "Mon@9-10"
pause_bad_start() ( # a real command exits nonzero and names PAUSE_WINDOWS
  proj="$TMP/pause-bad-start"
  rm -rf "$proj"
  mkdir -p "$proj" || return 1
  printf 'REPO="acme/widget"\nPAUSE_WINDOWS="Funday@09:00-10:00"\n' >"$proj/belt.conf"
  out=$(BELT_PROJECT="$proj" bash "$ROOT/belt" status 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'invalid PAUSE_WINDOWS'
)
check_ok "an invalid PAUSE_WINDOWS refuses to start belt" pause_bad_start

PAUSE_WINDOWS=""
PAUSE_TZ=""

# --------------------------------------------------------------- risky globs ---

RISKY_PATHS="src/* .github/ secrets/ *.sql"
check_ok "risky deep under src" is_risky_path "src/a/b/c.c"
check_no "not under src" is_risky_path "srcx/a.c"
check_ok "risky whole folder .github" is_risky_path ".github/workflows/ci.yml"
check_ok "risky folder itself" is_risky_path ".github"
check_ok "risky folder secrets" is_risky_path "secrets/token.txt"
check_no "prefix of folder name" is_risky_path "secretsfoo/x"
check_ok "risky suffix glob" is_risky_path "db/migrate/1.sql"
check_no "plain file" is_risky_path "README.md"
RISKY_PATHS=""
check_no "empty risky list means nothing risky" is_risky_path "src/a.c"

# a glob in RISKY_PATHS must not be replaced by a same-named file in $PWD
mkdir -p "$TMP/globcwd/src"
: >"$TMP/globcwd/src/only.txt"
RISKY_PATHS="src/*"
glob_risky() ( cd "$TMP/globcwd" && is_risky_path "src/a/b.c" )
check_ok "risky glob is not pathname-expanded" glob_risky

# a folder pattern (trailing /) must keep its wildcards too
RISKY_PATHS="src/*/"
check_ok "risky folder glob matches a nested path" is_risky_path "src/db/schema.sql"
check_ok "risky folder glob matches the folder itself" is_risky_path "src/db"
check_ok "risky folder glob is conservative for direct children" is_risky_path "src/a.txt"
RISKY_PATHS="docs/"

# ------------------------------------------------------------ ignored paths ---

check_ok "ignore .env" path_is_ignored ".env"
check_ok "ignore nested .env.local" path_is_ignored "app/.env.local"
check_ok "ignore pem" path_is_ignored "certs/server.pem"
check_ok "ignore key" path_is_ignored "id.key"
check_ok "ignore secret name" path_is_ignored "config/my-secret.json"
check_ok "ignore .envrc" path_is_ignored ".envrc"
check_ok "ignore nested .envrc" path_is_ignored "app/.envrc"
check_ok "ignore .env-production" path_is_ignored ".env-production"
check_ok "ignore nested .env-production" path_is_ignored "app/.env-production"
check_ok "ignore .belt" path_is_ignored ".belt/state"
check_ok "ignore node_modules" path_is_ignored "web/node_modules/x.js"
check_ok "ignore DS_Store" path_is_ignored ".DS_Store"
check_no "keep normal file" path_is_ignored "src/main.c"
check_no "keep env-like name" path_is_ignored "src/envelope.c"

# -------------------------------------------------------------- config load ---

mkdir -p "$TMP/empty-proj" "$TMP/full-proj"
load_config "$TMP/empty-proj" >/dev/null
check_eq "default MAX_PARALLEL" 0 "$MAX_PARALLEL"
check_eq "default WORKER_CMD empty" "" "$WORKER_CMD"
check_eq "default REVIEWER_CMD empty" "" "$REVIEWER_CMD"
check_eq "default RISKY_REVIEWER_CMD empty" "" "$RISKY_REVIEWER_CMD"
check_eq "default PAUSE_WINDOWS empty" "" "$PAUSE_WINDOWS"
check_eq "default PAUSE_TZ empty" "" "$PAUSE_TZ"
check_eq "default CHECK_WAIT_MIN" 15 "$CHECK_WAIT_MIN"
check_eq "default checks empty" "" "$CHECK_BUILD$CHECK_TEST$CHECK_LINT"
check_eq "default RISKY_PATHS empty" "" "$RISKY_PATHS"
default_slots_ok() ( case "$CHECK_SLOTS" in ''|*[!0-9]*) return 1 ;; esac; [ "$CHECK_SLOTS" -ge 1 ] )
check_ok "default CHECK_SLOTS is the CPU count" default_slots_ok

cat >"$TMP/full-proj/belt.conf" <<'EOF'
BASE_BRANCH="develop"
CHECK_BUILD="make build"
CHECK_TEST="make test"
CHECK_LINT="make lint"
RISKY_PATHS="db/ *secret*"
MAX_PARALLEL="3"
CHECK_SLOTS="2"
DEVICE_LOCK="/tmp/belt-test-device.lock"
WORKER_CMD="make worker"
REVIEWER_CMD="make reviewer"
RISKY_REVIEWER_CMD="make risky-reviewer"
PAUSE_WINDOWS="Mon-Fri@09:00-12:00 Sat@10:00-11:00"
PAUSE_TZ="Asia/Shanghai"
CHECK_WAIT_MIN="1"
REPO="acme/widget"
SLOT_WRITE_ALLOW="/tmp/slot-allow"
TOOLS_DIR="/tmp/tools-a /tmp/tools-b"
BACKUP_DIR="/tmp/backups"
CHECKS_UNSANDBOXED="1"
EOF
load_config "$TMP/full-proj" >/dev/null
check_eq "loaded BASE_BRANCH" "develop" "$BASE_BRANCH"
check_eq "loaded CHECK_BUILD" "make build" "$CHECK_BUILD"
check_eq "loaded CHECK_TEST" "make test" "$CHECK_TEST"
check_eq "loaded CHECK_LINT" "make lint" "$CHECK_LINT"
check_eq "loaded RISKY_PATHS" "db/ *secret*" "$RISKY_PATHS"
check_eq "loaded MAX_PARALLEL" 3 "$MAX_PARALLEL"
check_eq "loaded CHECK_SLOTS" 2 "$CHECK_SLOTS"
check_eq "loaded WORKER_CMD" "make worker" "$WORKER_CMD"
check_eq "loaded REVIEWER_CMD" "make reviewer" "$REVIEWER_CMD"
check_eq "loaded RISKY_REVIEWER_CMD" "make risky-reviewer" "$RISKY_REVIEWER_CMD"
check_eq "loaded PAUSE_WINDOWS" "Mon-Fri@09:00-12:00 Sat@10:00-11:00" "$PAUSE_WINDOWS"
check_eq "loaded PAUSE_TZ" "Asia/Shanghai" "$PAUSE_TZ"
check_eq "loaded CHECK_WAIT_MIN" 1 "$CHECK_WAIT_MIN"
check_eq "loaded REPO" "acme/widget" "$REPO"
check_eq "loaded SLOT_WRITE_ALLOW" "/tmp/slot-allow" "$SLOT_WRITE_ALLOW"
check_eq "loaded TOOLS_DIR" "/tmp/tools-a /tmp/tools-b" "$TOOLS_DIR"
check_eq "loaded BACKUP_DIR" "/tmp/backups" "$BACKUP_DIR"
check_eq "loaded CHECKS_UNSANDBOXED" 1 "$CHECKS_UNSANDBOXED"

load_config "$TMP/empty-proj" >/dev/null
check_eq "reload resets MAX_PARALLEL" 0 "$MAX_PARALLEL"
check_eq "reload resets REPO" "" "$REPO"
check_eq "reload resets BASE_BRANCH" "" "$BASE_BRANCH"
check_eq "reload resets RISKY_REVIEWER_CMD" "" "$RISKY_REVIEWER_CMD"
check_eq "reload resets PAUSE_WINDOWS" "" "$PAUSE_WINDOWS"
check_eq "reload resets PAUSE_TZ" "" "$PAUSE_TZ"
check_eq "reload resets SLOT_WRITE_ALLOW" "" "$SLOT_WRITE_ALLOW"
check_eq "reload resets TOOLS_DIR" "" "$TOOLS_DIR"
check_eq "reload resets BACKUP_DIR" "" "$BACKUP_DIR"
check_eq "reload resets CHECKS_UNSANDBOXED" 0 "$CHECKS_UNSANDBOXED"

mkdir -p "$TMP/bad-cap-proj"
printf 'MAX_PARALLEL="lots"\nCHECK_SLOTS="many"\n' >"$TMP/bad-cap-proj/belt.conf"
load_config "$TMP/bad-cap-proj" >/dev/null
check_eq "non-numeric MAX_PARALLEL means no cap" 0 "$MAX_PARALLEL"
default_slots_ok2() ( case "$CHECK_SLOTS" in ''|*[!0-9]*) return 1 ;; esac; [ "$CHECK_SLOTS" -ge 1 ] )
check_ok "non-numeric CHECK_SLOTS falls back to the CPU count" default_slots_ok2

xcode_check_defaults() ( # Xcode checks: one at a time, 20 s apart, unless belt.conf says otherwise
  mkdir -p "$TMP/xcode-proj" "$TMP/xcode-proj2"
  printf 'CHECKS_UNSANDBOXED="1"\n' >"$TMP/xcode-proj/belt.conf"
  load_config "$TMP/xcode-proj" >/dev/null || return 1
  [ "$CHECK_SLOTS" = 1 ] && [ "$CHECK_START_GAP_SEC" = 20 ] || return 1
  printf 'CHECKS_UNSANDBOXED="1"\nCHECK_SLOTS="3"\nCHECK_START_GAP_SEC="5"\n' >"$TMP/xcode-proj2/belt.conf"
  load_config "$TMP/xcode-proj2" >/dev/null || return 1
  [ "$CHECK_SLOTS" = 3 ] && [ "$CHECK_START_GAP_SEC" = 5 ] || return 1
  load_config "$TMP/bad-cap-proj" >/dev/null || return 1
  [ "$CHECK_START_GAP_SEC" = 0 ]
)
check_ok "Xcode checks default to one slot and a 20-second start gap" xcode_check_defaults

xcode_developer_dir() ( # Command Line Tools selected: belt points DEVELOPER_DIR at Xcode
  if [ ! -d /Applications/Xcode.app/Contents/Developer ]; then
    printf 'note: no Xcode here; DEVELOPER_DIR default skipped\n'
    return 0
  fi
  xcode-select() { printf '/Library/Developer/CommandLineTools\n'; }
  unset DEVELOPER_DIR
  load_config "$TMP/bad-cap-proj" >/dev/null || return 1
  [ "$DEVELOPER_DIR" = /Applications/Xcode.app/Contents/Developer ] || return 1
  DEVELOPER_DIR=/opt/OtherXcode/Contents/Developer
  load_config "$TMP/bad-cap-proj" >/dev/null || return 1
  [ "$DEVELOPER_DIR" = /opt/OtherXcode/Contents/Developer ]
)
check_ok "an unset DEVELOPER_DIR is set to Xcode when the Command Line Tools are selected" xcode_developer_dir

check_gap_spacing() ( # two check starts land at least CHECK_START_GAP_SEC apart
  BELT_HOME="$TMP/gap-home"; export BELT_HOME
  CHECK_SLOTS=2; CHECK_START_GAP_SEC=2
  acquire_check_slot || return 1; a=$(date '+%s'); lock_a=$CHECK_SLOT_LOCK
  acquire_check_slot || return 1; b=$(date '+%s')
  release_check_slot; CHECK_SLOT_LOCK=$lock_a; release_check_slot
  [ $((b - a)) -ge 1 ]
)
check_ok "check starts are spaced by CHECK_START_GAP_SEC" check_gap_spacing

check_eq "default SLOT_IDLE_MIN" 20 "$SLOT_IDLE_MIN"
check_eq "default SLOT_MAX_MIN" 180 "$SLOT_MAX_MIN"
check_eq "default SUITE_TIMEOUT_MIN" 120 "$SUITE_TIMEOUT_MIN"
check_eq "default ONCALL_TIMEOUT_MIN" 30 "$ONCALL_TIMEOUT_MIN"
check_eq "default SILENT_MIN" 45 "$SILENT_MIN"
check_eq "default CONFLICT_MIN" 10 "$CONFLICT_MIN"
check_eq "default LEAD_WAIT_MIN" 120 "$LEAD_WAIT_MIN"
check_eq "default FULL_SUITE_CMD" "" "$FULL_SUITE_CMD"
check_eq "default ONCALL_CMD" "" "$ONCALL_CMD"
check_eq "default BUDGETS" "" "$BUDGETS"
check_ok "default OWNER_NOTIFY_CMD uses osascript" \
  eval 'case "$OWNER_NOTIFY_CMD" in *osascript*) true ;; *) false ;; esac'

mkdir -p "$TMP/watch-proj-conf"
cat >"$TMP/watch-proj-conf/belt.conf" <<'EOF'
FULL_SUITE_CMD="make test-all"
SUITE_TIMEOUT_MIN="90"
SLOT_IDLE_MIN="12"
SLOT_MAX_MIN="90"
ONCALL_CMD="make oncall"
ONCALL_TIMEOUT_MIN="20"
SILENT_MIN="30"
CONFLICT_MIN="7"
LEAD_WAIT_MIN="60"
BUDGETS="impl=30 review=10"
OWNER_NOTIFY_CMD="printf hi"
EOF
load_config "$TMP/watch-proj-conf" >/dev/null
check_eq "loaded FULL_SUITE_CMD" "make test-all" "$FULL_SUITE_CMD"
check_eq "loaded SUITE_TIMEOUT_MIN" 90 "$SUITE_TIMEOUT_MIN"
check_eq "loaded SLOT_IDLE_MIN" 12 "$SLOT_IDLE_MIN"
check_eq "loaded SLOT_MAX_MIN" 90 "$SLOT_MAX_MIN"
check_eq "loaded ONCALL_CMD" "make oncall" "$ONCALL_CMD"
check_eq "loaded ONCALL_TIMEOUT_MIN" 20 "$ONCALL_TIMEOUT_MIN"
check_eq "loaded SILENT_MIN" 30 "$SILENT_MIN"
check_eq "loaded CONFLICT_MIN" 7 "$CONFLICT_MIN"
check_eq "loaded LEAD_WAIT_MIN" 60 "$LEAD_WAIT_MIN"
check_eq "loaded BUDGETS" "impl=30 review=10" "$BUDGETS"
check_eq "loaded OWNER_NOTIFY_CMD" "printf hi" "$OWNER_NOTIFY_CMD"
load_config "$TMP/empty-proj" >/dev/null
check_eq "reload resets SLOT_IDLE_MIN" 20 "$SLOT_IDLE_MIN"
check_eq "reload resets SLOT_MAX_MIN" 180 "$SLOT_MAX_MIN"
check_eq "reload resets CONFLICT_MIN" 10 "$CONFLICT_MIN"
check_eq "reload resets ONCALL_CMD" "" "$ONCALL_CMD"
check_eq "reload resets FULL_SUITE_CMD" "" "$FULL_SUITE_CMD"
check_eq "reload resets OWNER_NOTIFY_CMD" \
  'osascript -e "display notification \"$BELT_MESSAGE\" with title \"belt\""' "$OWNER_NOTIFY_CMD"

check_eq "state dir" "$TMP/belt-home/acme__widget" "$(state_dir_for acme/widget)"
mkdir -p "$TMP/belt-home" "$TMP/outside" "$TMP/belt-home/real"
ln -sfn "$TMP/outside" "$TMP/belt-home/link-out"
ln -sfn "$TMP/belt-home/real" "$TMP/belt-home/link-in"
check_no "refuse path outside BELT_HOME" ensure_under_belt_home "/tmp/elsewhere/1"
check_no "refuse '..' escape from BELT_HOME" ensure_under_belt_home "$TMP/belt-home/../escape"
check_no "refuse symlinked parent outside BELT_HOME" ensure_under_belt_home "$TMP/belt-home/link-out/x"
check_ok "accept symlink that resolves inside BELT_HOME" ensure_under_belt_home "$TMP/belt-home/link-in/x"
check_ok "accept missing nested path under BELT_HOME" ensure_under_belt_home "$TMP/belt-home/acme__widget/1"

# ------------------------------------------------------------------- slots ---

slot_env_out="$TMP/slot-env.txt"
slot_env_dir="$TMP/slot-env-dir"
slot_env_prompt="$TMP/slot-env.prompt"
slot_env_answer="$TMP/slot-env.answer"
mkdir -p "$slot_env_dir"
printf 'Reply with exactly the word OK and nothing else.\n' >"$slot_env_prompt"
: >"$slot_env_answer"
export SLOT_ENV_OUT="$slot_env_out"
slot_env_cmd='printf "%s\n%s\n%s\n" "$BELT_PROMPT_FILE" "$BELT_OUT_FILE" "$(pwd -P)" >"$SLOT_ENV_OUT"'
slot_run "$slot_env_cmd" "$slot_env_dir" "$slot_env_prompt" "$slot_env_answer" "$TMP/slot-env.stdout"
check_eq "slot exports BELT_PROMPT_FILE" "$slot_env_prompt" "$(sed -n 1p "$slot_env_out")"
check_eq "slot exports BELT_OUT_FILE" "$slot_env_answer" "$(sed -n 2p "$slot_env_out")"
check_eq "slot runs inside the given dir" "$(cd -P "$slot_env_dir" && pwd)" "$(sed -n 3p "$slot_env_out")"

# stdin is /dev/null: a slot can never block waiting for input
slot_run 'if read -r line; then printf "read:%s\n" "$line"; else printf "eof\n"; fi' \
  "$slot_env_dir" "$slot_env_prompt" "$slot_env_answer" "$TMP/slot-stdin.out"
check_eq "slot stdin is /dev/null" "eof" "$(cat "$TMP/slot-stdin.out")"

run_timeout_rc() ( run_with_timeout 1 sleep 5; printf '%s\n' "$?" )
check_eq "a slow slot is killed by the timeout helper" 124 "$(run_timeout_rc)"

# the timeout must reach the slot's own children, not just the wrapper
tree_kill_marker="$TMP/timeout-tree-marker"
rm -f "$tree_kill_marker"
tree_slot() ( ( sleep 2; printf 'survived\n' >"$tree_kill_marker" ) & wait )
tree_kill_test() (
  run_with_timeout 1 tree_slot
  [ "$?" -eq 124 ] || return 1
  i=0
  while [ "$i" -lt 4 ]; do
    [ ! -e "$tree_kill_marker" ] || return 1
    sleep 1
    i=$((i + 1))
  done
)
check_ok "timeout kills the slot's whole process tree" tree_kill_test

# a hang is no progress, never elapsed time: real runs take 50-95 minutes.
# BELT_TIME_SCALE=60 turns SLOT_IDLE_MIN=1 / SLOT_MAX_MIN=1 into one second.
slot_cap_prompt="$TMP/slot-cap.prompt"
printf 'Reply\n' >"$slot_cap_prompt"
slot_busy_log="$TMP/slot-busy.log"
: >"$slot_busy_log"
slot_busy_test() (
  SLOT_IDLE_MIN=1
  SLOT_MAX_MIN=180
  BELT_TIME_SCALE=60
  LOG="$slot_busy_log"
  : >"$TMP/slot-busy.out"
  # prints for ~4s: longer than the idle window, shorter than the ceiling
  slot_run_retry 'i=0; while [ "$i" -lt 20 ]; do printf "."; sleep 0.2; i=$((i+1)); done' \
    "$TMP" "$slot_cap_prompt" "$TMP/slot-busy.out" "$TMP/slot-busy.stdout" \
    "$TMP/slot-busy.stderr"
  rc=$?
  [ "$rc" -eq 0 ] && [ "${SLOT_KILLED:-0}" = "0" ] && ! grep -q 'slot hung' "$LOG"
)
check_ok "a slot that keeps printing past SLOT_IDLE_MIN is not killed" slot_busy_test

slot_hung_log="$TMP/slot-hung.log"
: >"$slot_hung_log"
slot_hung_test() (
  SLOT_IDLE_MIN=1
  SLOT_MAX_MIN=180
  BELT_TIME_SCALE=60
  LOG="$slot_hung_log"
  : >"$TMP/slot-hung.out"
  slot_run_retry 'sleep 30' "$TMP" "$slot_cap_prompt" "$TMP/slot-hung.out" \
    "$TMP/slot-hung.stdout" "$TMP/slot-hung.stderr"
  rc=$?
  [ "$rc" -eq 124 ] && [ "${SLOT_KILLED:-0}" = "1" ]
)
check_ok "a slot silent past SLOT_IDLE_MIN is killed and counts as failed" slot_hung_test
check_ok "the hang is written to the log" \
  grep -q 'slot hung: no output, no file change, no CPU for 1 min' "$slot_hung_log"

slot_ceiling_log="$TMP/slot-ceiling.log"
: >"$slot_ceiling_log"
slot_ceiling_test() (
  SLOT_IDLE_MIN=20
  SLOT_MAX_MIN=1
  BELT_TIME_SCALE=60
  LOG="$slot_ceiling_log"
  : >"$TMP/slot-ceiling.out"
  # busy the whole time: only the hard ceiling may end it
  slot_run_retry 'i=0; while [ "$i" -lt 40 ]; do printf "."; sleep 0.2; i=$((i+1)); done' \
    "$TMP" "$slot_cap_prompt" "$TMP/slot-ceiling.out" "$TMP/slot-ceiling.stdout" \
    "$TMP/slot-ceiling.stderr"
  rc=$?
  [ "$rc" -eq 124 ] && [ "${SLOT_KILLED:-0}" = "1" ]
)
check_ok "SLOT_MAX_MIN kills a busy slot as a last resort" slot_ceiling_test
check_ok "the ceiling is written to the log" \
  grep -q 'slot hit the hard ceiling of 1 min' "$slot_ceiling_log"

# stamp writes one TSV line per event around each stage
stamp_test() (
  TICKET_DIR="$TMP/stamp-ticket"
  N=5
  rm -rf "$TICKET_DIR"
  mkdir -p "$TICKET_DIR"
  stamp impl start
  stamp impl end
  [ "$(wc -l <"$TICKET_DIR/timings.tsv" | tr -d ' ')" -eq 2 ] || return 1
  awk -F'\t' '
    NR == 1 && $2 == "5" && $3 == "impl" && $4 == "start" { one = 1 }
    NR == 2 && $2 == "5" && $3 == "impl" && $4 == "end" { two = 1 }
    END { exit !(one && two) }
  ' "$TICKET_DIR/timings.tsv"
)
check_ok "stamp writes start and end lines to timings.tsv" stamp_test

# a missing slot must stop before any ticket is claimed (no gh call at all)
missing_slot_proj="$TMP/missing-slot-proj"
mkdir -p "$missing_slot_proj"
printf 'REPO="acme/widget"\nREVIEWER_CMD="true"\n' >"$missing_slot_proj/belt.conf"
missing_slot_stops() (
  BELT_PROJECT="$missing_slot_proj"
  gh() { : >"$TMP/gh-missing"; return 0; }
  rm -f "$TMP/gh-missing" "$TMP/missing-slot.err"
  ticket_run 66 2>"$TMP/missing-slot.err"
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ ! -e "$TMP/gh-missing" ] || return 1
  grep -q 'WORKER_CMD' "$TMP/missing-slot.err"
)
check_ok "a missing WORKER_CMD stops before claiming a ticket" missing_slot_stops

missing_keys_message() ( WORKER_CMD=""; REVIEWER_CMD=""; require_slots 2>&1 | grep -q 'WORKER_CMD and REVIEWER_CMD' )
check_ok "the missing-slot message names both keys" missing_keys_message

slot_test_proj="$TMP/slot-test-proj"
mkdir -p "$slot_test_proj"
cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf OK"
REVIEWER_CMD="printf OK > \"\$BELT_OUT_FILE\""
EOF
slot_test_pass() ( slot_test "$slot_test_proj" >"$TMP/slot-pass.out" 2>&1 )
check_ok "slot-test passes when both slots answer OK" slot_test_pass
check_eq "slot-test prints one PASS line per slot" 2 "$(grep -c '^PASS ' "$TMP/slot-pass.out")"

cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf OK"
REVIEWER_CMD="printf NOPE"
EOF
slot_test_fail() ( slot_test "$slot_test_proj" >"$TMP/slot-fail.out" 2>&1; rc=$?; [ "$rc" -ne 0 ] )
check_ok "slot-test fails when a slot does not answer OK" slot_test_fail
slot_fail_output() ( grep -q '^FAIL reviewer' "$TMP/slot-fail.out" && grep -q 'NOPE' "$TMP/slot-fail.out" )
check_ok "slot-test shows the failing slot and its output" slot_fail_output

# only the last non-empty line counts, and only stdout/BELT_OUT_FILE is an answer
cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf 'NOT OK\n'"
REVIEWER_CMD="printf OK > \"\$BELT_OUT_FILE\""
EOF
slot_test_not_ok() ( slot_test "$slot_test_proj" >"$TMP/slot-not-ok.out" 2>&1; rc=$?; [ "$rc" -ne 0 ] && grep -q '^FAIL worker' "$TMP/slot-not-ok.out" )
check_ok "slot-test rejects 'NOT OK' as an answer" slot_test_not_ok

cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf 'OK\nNOPE\n'"
REVIEWER_CMD="printf OK > \"\$BELT_OUT_FILE\""
EOF
slot_test_last_line() ( slot_test "$slot_test_proj" >"$TMP/slot-last.out" 2>&1; rc=$?; [ "$rc" -ne 0 ] && grep -q '^FAIL worker' "$TMP/slot-last.out" )
check_ok "slot-test reads the last line, not any earlier OK" slot_test_last_line

cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf 'NOPE\n'; printf 'OK\n' >&2"
REVIEWER_CMD="printf OK > \"\$BELT_OUT_FILE\""
EOF
slot_test_stderr() ( slot_test "$slot_test_proj" >"$TMP/slot-stderr.out" 2>&1; rc=$?; [ "$rc" -ne 0 ] && grep -q '^FAIL worker' "$TMP/slot-stderr.out" )
check_ok "slot-test never accepts OK from stderr" slot_test_stderr

cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf 'working...\nok.\n'"
REVIEWER_CMD="printf '  OK.  ' > \"\$BELT_OUT_FILE\""
EOF
slot_test_ok_variants() ( slot_test "$slot_test_proj" >"$TMP/slot-ok.out" 2>&1 )
check_ok "slot-test accepts 'ok.' as the last line" slot_test_ok_variants

cat >"$slot_test_proj/belt.conf" <<'EOF'
WORKER_CMD="printf OK"
REVIEWER_CMD="printf OK > \"\$BELT_OUT_FILE\""
RISKY_REVIEWER_CMD="printf OK > \"\$BELT_OUT_FILE\""
EOF
slot_test_risky() ( slot_test "$slot_test_proj" >"$TMP/slot-risky.out" 2>&1 && grep -q '^PASS risky-reviewer' "$TMP/slot-risky.out" )
check_ok "slot-test tests RISKY_REVIEWER_CMD when set" slot_test_risky
check_eq "slot-test prints a risky-reviewer line" 1 "$(grep -c 'risky-reviewer' "$TMP/slot-risky.out")"

# --------------------------------------------------------- review answers ---

printf 'OUT\n' >"$TMP/answer.out"
printf 'STDOUT\n' >"$TMP/answer.stdout"
check_eq "review answer prefers BELT_OUT_FILE" "$TMP/answer.out" \
  "$(review_answer "$TMP/answer.out" "$TMP/answer.stdout")"
: >"$TMP/answer.out"
check_eq "review answer falls back to captured stdout" "$TMP/answer.stdout" \
  "$(review_answer "$TMP/answer.out" "$TMP/answer.stdout")"
check_no "review answer fails when both are empty" review_answer "$TMP/answer.out" "$TMP/answer.missing"

review_remote="$TMP/review-remote.git"
review_proj="$TMP/review-proj"
git init -q --bare "$review_remote"
git clone -q "$review_remote" "$review_proj"
git -C "$review_proj" config user.email belt@example.com
git -C "$review_proj" config user.name belt
printf 'base\n' >"$review_proj/base.txt"
git -C "$review_proj" add base.txt
git -C "$review_proj" commit -qm base
git -C "$review_proj" branch -M main
git -C "$review_proj" push -q -u origin main
git -C "$review_proj" checkout -q -b belt/7
printf 'feature\n' >"$review_proj/feature.txt"
git -C "$review_proj" add feature.txt
git -C "$review_proj" commit -qm feature
review_sha=$(git -C "$review_proj" rev-parse HEAD)
git -C "$review_proj" push -q -u origin belt/7

review_case() { # review_case <ticket-dir> <reviewer-command> [selected-command]
  TICKET_DIR="$1"
  REVIEWER_CMD="$2"
  PROJECT="$review_proj"
  SLUG="acme/widget"
  BASE="main"
  STATE_DIR="$BELT_HOME/review-state"
  LOG="$TICKET_DIR/review.log"
  mkdir -p "$TICKET_DIR"
  gh() {
    if [ "$1 $2" = "pr view" ]; then printf '%s\n' "$review_sha"; return 0; fi
    return 0
  }
  review_pr 7 acme/widget "$review_proj" main "${3:-$REVIEWER_CMD}"
}

review_out_wins() (
  review_case "$TMP/review-out-ticket" \
    'printf "P1: from stdout\nVERDICT: FIX\n"; printf "P2: minor\nVERDICT: PASS\n" > "$BELT_OUT_FILE"' \
    && [ "$REVIEW_P1" -eq 0 ]
)
check_ok "a non-empty BELT_OUT_FILE wins over stdout" review_out_wins

review_stdout_fallback() (
  review_case "$TMP/review-stdout-ticket" 'printf "P1: bug\nVERDICT: FIX\n"' \
    && [ "$REVIEW_P1" -eq 1 ]
)
check_ok "stdout is used when BELT_OUT_FILE stays empty" review_stdout_fallback

review_selected_command() ( # the 5th argument wins over REVIEWER_CMD
  review_case "$TMP/review-selected-ticket" 'printf "VERDICT: FIX\n"' \
    'printf "VERDICT: PASS\n"'
)
check_ok "review_pr runs the reviewer command it is given" review_selected_command

review_prompt_contains_diff() (
  review_prompt main "$review_sha" "$review_proj" >"$TMP/review-prompt-diff.txt" || return 1
  grep -Fxq "Review this diff of the checkout in the current folder (head $review_sha); you may read other files for context." "$TMP/review-prompt-diff.txt" &&
  grep -Fxq 'The diff:' "$TMP/review-prompt-diff.txt" &&
  grep -Fxq '```diff' "$TMP/review-prompt-diff.txt" &&
  grep -Fxq '+feature' "$TMP/review-prompt-diff.txt"
)
check_ok "review prompt embeds the full diff" review_prompt_contains_diff

head -c 410000 /dev/zero | tr '\0' 'x' >"$review_proj/big.txt"
git -C "$review_proj" add big.txt
git -C "$review_proj" commit -qm big
review_big_sha=$(git -C "$review_proj" rev-parse HEAD)

review_prompt_too_large() (
  if review_prompt main "$review_big_sha" "$review_proj" >"$TMP/review-prompt-big.txt" 2>/dev/null; then
    return 1
  fi
  [ ! -s "$TMP/review-prompt-big.txt" ] &&
  printf '%s' "$REVIEW_ERR" | grep -Eq '^diff too large for review \([0-9]+ bytes\)$'
)
check_ok "an oversize diff fails the review" review_prompt_too_large

review_oversize_end_to_end() (
  review_sha=$review_big_sha
  if review_case "$TMP/review-big-ticket" 'printf "VERDICT: PASS\n"'; then return 1; fi
  printf '%s' "$REVIEW_ERR" | grep -Eq '^diff too large for review \([0-9]+ bytes\)$'
)
check_ok "review_pr refuses an oversize diff" review_oversize_end_to_end

review_diff_error() (
  if review_prompt nope-branch "$review_sha" "$review_proj" >/dev/null 2>&1; then return 1; fi
  printf '%s' "$REVIEW_ERR" | grep -q 'could not compute diff'
)
check_ok "an uncomputable diff fails the review" review_diff_error

# ------------------------------------------------------------- rate limits ---

rate_retry() { # <command>; runs slot_run_retry with instant waits
  BELT_NO_SLEEP=1
  RATE_OUT="$TMP/rate-out"; RATE_STDOUT="$TMP/rate-stdout"; RATE_ERR="$TMP/rate-stderr"
  printf 'Reply with OK\n' >"$TMP/rate.prompt"
  : >"$RATE_OUT"; : >"$RATE_STDOUT"; : >"$RATE_ERR"
  slot_run_retry "$1" "$TMP" "$TMP/rate.prompt" "$RATE_OUT" "$RATE_STDOUT" "$RATE_ERR"
}
rate_stderr_then_ok() (
  RATE_COUNTER="$TMP/rate-count-1"; export RATE_COUNTER
  printf '0\n' >"$RATE_COUNTER"
  cmd='n=$(cat "$RATE_COUNTER"); n=$((n + 1)); printf "%s\n" "$n" >"$RATE_COUNTER"; if [ "$n" -lt 2 ]; then printf "429 Too Many Requests\n" >&2; exit 1; fi; printf "done\n"'
  rate_retry "$cmd" || return 1
  [ "$(cat "$RATE_COUNTER")" = "2" ] && grep -q 'done' "$RATE_STDOUT"
)
check_ok "rate-limit output retries then succeeds" rate_stderr_then_ok

rate_outfile_then_ok() (
  RATE_COUNTER="$TMP/rate-count-2"; export RATE_COUNTER
  printf '0\n' >"$RATE_COUNTER"
  cmd='n=$(cat "$RATE_COUNTER"); n=$((n + 1)); printf "%s\n" "$n" >"$RATE_COUNTER"; if [ "$n" -lt 2 ]; then printf "quota exceeded\n" >"$BELT_OUT_FILE"; exit 1; fi; printf "VERDICT: PASS\n" >"$BELT_OUT_FILE"'
  rate_retry "$cmd" || return 1
  [ "$(cat "$RATE_COUNTER")" = "2" ] && grep -q 'VERDICT: PASS' "$RATE_OUT"
)
check_ok "a rate limit in BELT_OUT_FILE also retries" rate_outfile_then_ok

rate_non_limit_no_retry() (
  RATE_COUNTER="$TMP/rate-count-3"; export RATE_COUNTER
  printf '0\n' >"$RATE_COUNTER"
  cmd='n=$(cat "$RATE_COUNTER"); n=$((n + 1)); printf "%s\n" "$n" >"$RATE_COUNTER"; printf "boom\n" >&2; exit 1'
  rate_retry "$cmd" && return 1
  [ "$(cat "$RATE_COUNTER")" = "1" ]
)
check_ok "a non-rate-limit failure does not retry" rate_non_limit_no_retry

# every retry must start from the ticket's starting commit, a clean tree and an
# empty OUT_DIR: a partial edit or a stale nochange.txt must never leak forward
retry_repo="$TMP/retry-repo"
mkdir -p "$retry_repo"
git -C "$retry_repo" init -q
git -C "$retry_repo" config user.email belt@example.com
git -C "$retry_repo" config user.name belt
printf 'base\n' >"$retry_repo/tracked.txt"
git -C "$retry_repo" add tracked.txt
git -C "$retry_repo" commit -qm base
retry_out="$TMP/retry-out"
mkdir -p "$retry_out"
retry_count="$TMP/retry-count"
printf 'Reply\n' >"$TMP/retry.prompt"
cat >"$TMP/retry-worker.sh" <<'WORKER'
#!/usr/bin/env bash
n=$(cat "$RETRY_COUNT")
n=$((n + 1))
printf '%s\n' "$n" >"$RETRY_COUNT"
if [ "$n" -lt 2 ]; then
  printf 'tampered\n' > tracked.txt
  printf 'leftover\n' > untracked.txt
  printf 'stale\n' > "$RETRY_OUT/nochange.txt"
  printf '429 rate limit\n' >&2
  exit 1
fi
[ "$(cat tracked.txt)" = base ] || { printf 'tracked tree was not reset\n' >&2; exit 1; }
[ ! -e untracked.txt ] || { printf 'untracked file survived\n' >&2; exit 1; }
[ -z "$(ls -A "$RETRY_OUT")" ] || { printf 'OUT_DIR was not emptied\n' >&2; exit 1; }
printf 'done\n'
WORKER
retry_reset_test() (
  printf '0\n' >"$retry_count"
  RETRY_COUNT="$retry_count" RETRY_OUT="$retry_out"
  export RETRY_COUNT RETRY_OUT
  WORKTREE="$retry_repo"
  OUT_DIR="$retry_out"
  BELT_NO_SLEEP=1 slot_run_retry "bash '$TMP/retry-worker.sh'" "$retry_repo" \
    "$TMP/retry.prompt" "$TMP/retry.out" "$TMP/retry.stdout" "$TMP/retry.stderr"
)
check_ok "a rate-limit retry resets the worktree and OUT_DIR" retry_reset_test

# the backoff may not sleep or start another attempt past the 6h deadline
budget_calls="$TMP/budget-calls"
cat >"$TMP/budget-worker.sh" <<'WORKER'
#!/usr/bin/env bash
n=$(cat "$BUDGET_CALLS")
n=$((n + 1))
printf '%s\n' "$n" >"$BUDGET_CALLS"
printf '429 rate limit\n' >&2
exit 1
WORKER
budget_stop_test() (
  printf '0\n' >"$budget_calls"
  BUDGET_CALLS="$budget_calls"
  export BUDGET_CALLS
  clock="$TMP/budget-clock"
  printf '0\n' >"$clock"
  date() { # first call is the start, the next is just before the deadline
    if [ "$1" = '+%s' ] && [ $# -eq 1 ]; then
      n=$(cat "$clock")
      n=$((n + 1))
      printf '%s\n' "$n" >"$clock"
      case "$n" in
        1) printf '1000000\n' ;;
        2) printf '1021599\n' ;;
        *) printf '%s\n' $((1021599 + (n - 2) * 61)) ;;
      esac
    else
      command date "$@"
    fi
  }
  BELT_NO_SLEEP=1 slot_run_retry "bash '$TMP/budget-worker.sh'" "$TMP" \
    "$TMP/retry.prompt" "$TMP/budget.out" "$TMP/budget.stdout" "$TMP/budget.stderr" \
    >/dev/null 2>&1
  [ "$(cat "$budget_calls")" = "1" ]
)
check_ok "rate-limit backoff stops at the 6h deadline" budget_stop_test


review_edits_files() (
  review_case "$TMP/review-edit-ticket" 'printf "VERDICT: PASS\n"; printf "x\n" > reviewer-touched.txt'
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s' "$REVIEW_ERR" | grep -q 'reviewer changed files'
)
check_ok "a reviewer that edits a file fails the review" review_edits_files

review_hidden_edit() ( # review_hidden_edit <ticket-dir> <flag> <message-fragment>
  # A sandboxed reviewer cannot write the shared index (its gitdir is inside
  # the common dir), so the flag may never be set; the content hash must still
  # fail the review. Unsandboxed, the flag check names the trick instead.
  review_case "$1" "printf 'VERDICT: PASS\n'; git update-index --$2 base.txt 2>/dev/null; printf 'tampered\n' > base.txt"
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s' "$REVIEW_ERR" | grep -q "$3" ||
    printf '%s' "$REVIEW_ERR" | grep -q 'reviewer changed files'
)
check_ok "a reviewer editing behind assume-unchanged fails the review" \
  review_hidden_edit "$TMP/review-assume-ticket" assume-unchanged 'assume-unchanged'
check_ok "a reviewer editing behind skip-worktree fails the review" \
  review_hidden_edit "$TMP/review-skip-ticket" skip-worktree 'skip-worktree'

# a reviewer that answers without a valid verdict gets exactly one more run
cat >"$TMP/review-bad-once.sh" <<'REVIEWER'
#!/usr/bin/env bash
n=$(cat "$REVIEW_COUNTER" 2>/dev/null || printf 0)
n=$((n + 1))
printf '%s\n' "$n" >"$REVIEW_COUNTER"
if [ "$n" -eq 1 ]; then
  exit 0
fi
printf 'VERDICT: PASS\n'
REVIEWER

cat >"$TMP/review-always-bad.sh" <<'REVIEWER'
#!/usr/bin/env bash
n=$(cat "$REVIEW_COUNTER" 2>/dev/null || printf 0)
n=$((n + 1))
printf '%s\n' "$n" >"$REVIEW_COUNTER"
printf 'still no verdict\n'
REVIEWER

review_retry_bad_then_good() ( # no answer once, then a PASS
  REVIEW_COUNTER="$TMP/review-bad-once-count"; export REVIEW_COUNTER
  printf '0\n' >"$REVIEW_COUNTER"
  review_case "$TMP/review-bad-once-ticket" "bash '$TMP/review-bad-once.sh'" || return 1
  [ "$(tr -d '[:space:]' <"$REVIEW_COUNTER")" = "2" ]
)
check_ok "a reviewer with no answer is rerun once and can pass" review_retry_bad_then_good

review_retry_always_bad() ( # no verdict line twice: fail closed after the rerun
  REVIEW_COUNTER="$TMP/review-always-bad-count"; export REVIEW_COUNTER
  printf '0\n' >"$REVIEW_COUNTER"
  if review_case "$TMP/review-always-bad-ticket" "bash '$TMP/review-always-bad.sh'"; then
    return 1
  fi
  [ "$(tr -d '[:space:]' <"$REVIEW_COUNTER")" = "2" ] || return 1
  printf '%s' "$REVIEW_ERR" | grep -q 'last line is not a VERDICT line'
)
check_ok "a reviewer with no verdict line fails after one rerun" review_retry_always_bad

review_verdict_cases() ( # wrapped verdicts count; anything else is no verdict
  f="$TMP/verdict-case.txt"
  v() { printf "$1" >"$f"; review_verdict_of "$f"; }
  [ "$(v 'P2: x\nVERDICT: PASS\n')" = "VERDICT: PASS" ] || return 1
  [ "$(v '**VERDICT: PASS**\n')" = "VERDICT: PASS" ] || return 1
  [ "$(v '`VERDICT: FIX`\n')" = "VERDICT: FIX" ] || return 1
  [ "$(v 'P1: y\nAll told. VERDICT: FIX\n')" = "VERDICT: FIX" ] || return 1
  [ "$(v 'P1: y\nVERDICT: FIX\n```\n\n')" = "VERDICT: FIX" ] || return 1
  [ "$(v '## VERDICT:PASS.\r\n')" = "VERDICT: PASS" ] || return 1
  [ -z "$(v 'VERDICT: PASS\nthanks\n')" ] || return 1
  [ -z "$(v 'NOVERDICT: PASS\n')" ] || return 1
  [ -z "$(v 'VERDICT: PASS unless FIX\n')" ] || return 1
  [ -z "$(v 'VERDICT: MAYBE\n')" ] || return 1
  [ -z "$(v '\n')" ]
)
check_ok "a verdict wrapped in marks, a fence or a sentence still counts" review_verdict_cases

# ------------------------------------------------------------ status strings ---

# log timestamps follow the machine's local time, never a fixed zone: TZ is
# pinned to UTC here so a hardcoded TZ=Asia/Shanghai shows up as an 8h skew.
ts_epoch() { # ts_epoch <YYYY-MM-DD HH:MM:SS>, read as UTC
  TZ=UTC date -j -f '%Y-%m-%d %H:%M:%S' "$1" '+%s' 2>/dev/null ||
    TZ=UTC date -d "$1" '+%s' 2>/dev/null || echo 0
}
log_wrote_ts() ( # log_wrote_ts <log|warn|log_file> <message>; timestamp it wrote
  file="$TMP/log-ts.log"
  : >"$file"
  LOG="$file" TZ=UTC "$1" "$2" >/dev/null 2>&1
  sed -n 's/^\[\([^]]*\)\].*/\1/p' "$file" | tail -n 1
)
for helper in log warn log_file; do
  ts=$(log_wrote_ts "$helper" "zone probe")
  skew=$(( $(ts_epoch "$ts") - $(TZ=UTC date '+%s') ))
  total=$((total + 1))
  if [ -n "$ts" ] && [ "${skew#-}" -le 5 ]; then
    printf 'ok   %s timestamp uses local time\n' "$helper"
  else
    printf 'FAIL %s timestamp uses local time (got [%s])\n' "$helper" "$ts"
    fails=$((fails + 1))
  fi
done

check_eq "trim spaces" "hello world" "$(trim_str '  hello world  ')"
check_eq "trim tabs" "x" "$(trim_str "$(printf '\tx\t')")"
check_eq "trim empty" "" "$(trim_str '')"
check_eq "truncate short" "abc" "$(truncate_str "abc" 80)"
check_eq "truncate long" "abcde" "$(truncate_str "abcdefghij" 5)"
check_eq "status line trims and bounds" "project: a/b" "$(status_trim_line '   project: a/b   ' 120)"
long=$(printf 'x%.0s' $(seq 1 200))
trimmed=$(status_trim_line "$long" 120)
check_eq "status line bounded length" 120 "${#trimmed}"

printf 'a\nb\n' >"$TMP/lines.txt"
check_eq "line_count" 2 "$(line_count "$TMP/lines.txt")"
check_eq "line_count missing" 0 "$(line_count "$TMP/nope.txt")"

# status only mentions pause windows when PAUSE_WINDOWS is set; the time here comes
# from belt_now's BELT_NOW hook, not the machine clock.
mkdir -p "$TMP/stubbin"
cat >"$TMP/stubbin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *'pr list'*) printf '[]\n' ;;
  *) printf '0\n' ;;
esac
STUB
chmod +x "$TMP/stubbin/gh"

status_pause_line() ( # status_pause_line <PAUSE_WINDOWS> <BELT_NOW>; the 'next pause' line
  proj="$TMP/status-proj"
  rm -rf "$proj"
  mkdir -p "$proj"
  printf 'REPO="acme/widget"\nPAUSE_WINDOWS="%s"\n' "$1" >"$proj/belt.conf"
  PATH="$TMP/stubbin:$PATH" BELT_HOME="$TMP/belt-home" BELT_PROJECT="$proj" \
    BELT_NOW="$2" bash "$ROOT/belt" status 2>/dev/null | grep '^next pause:' || true
)
check_eq "status omits next pause when PAUSE_WINDOWS is empty" "" \
  "$(status_pause_line '' '2025-01-06 12:30')"
check_eq "status shows next pause when PAUSE_WINDOWS is set" "next pause: 2025-01-06 09:00" \
  "$(status_pause_line 'Mon-Fri@09:00-12:00' '2025-01-06 08:00')"
check_eq "status shows an active pause" "next pause: now until 12:00" \
  "$(status_pause_line 'Mon-Fri@09:00-12:00' '2025-01-06 10:00')"


# ------------------------------------------------------- verdict/CI parsing ---

{
  i=1
  while [ "$i" -le 14 ]; do
    printf 'P2: minor %s\n' "$i"
    i=$((i + 1))
  done
  printf 'P1: hidden later\n'
  printf 'VERDICT: FIX\n'
} >"$TMP/verdict-many.txt"
check_eq "P1 counted after the 12-line display cap" 1 "$(count_p1_findings "$TMP/verdict-many.txt")"
check_eq "P1 count on an empty verdict" 0 "$(count_p1_findings "$TMP/missing-verdict.txt")"

check_eq "CI empty + failed gh is unknown" "unknown" "$(ci_state_from_output "" 1)"
check_eq "CI empty + ok gh is none" "none" "$(ci_state_from_output "" 0)"
check_eq "CI explicit no checks is none" "none" "$(ci_state_from_output "no checks reported on the 'x' branch" 1)"
check_eq "CI pass" "pass" "$(ci_state_from_output '[{"bucket":"pass"}]' 0)"
check_eq "CI fail" "fail" "$(ci_state_from_output '[{"bucket":"fail"}]' 1)"
check_eq "CI pending" "pending" "$(ci_state_from_output '[{"bucket":"pending"}]' 1)"
check_eq "CI garbage is unknown" "unknown" "$(ci_state_from_output 'gh: Not Found (HTTP 404)' 1)"

# ------------------------------------------------------------ queue fetch ---

queue_page() ( # page 1 is all claimed; page 2 has the only eligible issue
  SLUG="acme/widget"
  gh() {
    case "$2" in
      *'&page=1') jq -n '[range(100) as $i | {number: ($i + 1), labels: [{name: "ready-for-agent"}, {name: "claimed:belt"}], created_at: "2025-01-01T00:00:00Z", pull_request: null}]' ;;
      *'&page=2') printf '[{"number":4242,"labels":[{"name":"ready-for-agent"}],"created_at":"2025-01-01T00:00:00Z","pull_request":null}]' ;;
      *) printf '[]' ;;
    esac
    return 0
  }
  fetch_queue
)
check_eq "queue is paged past the first 100 issues" "4242" "$(queue_page)"

queue_fail_rc() ( # a failed lookup must not look like an empty queue
  SLUG="acme/widget"
  gh() { return 1; }
  fetch_queue >/dev/null 2>&1
  printf '%s\n' "$?"
)
check_eq "failed queue fetch is an error, not empty" 1 "$(queue_fail_rc)"

# ------------------------------------------------------------- frontier ---

check_eq "text blocker 'Blocked by #12'" "12" "$(text_blockers 'Blocked by #12')"
check_eq "text blocker comma list" "$(printf '12\n14')" "$(text_blockers 'Blocked by: #12, #14')"
check_eq "text blocker with a dash" "12" "$(text_blockers '- Blocked by #12')"
check_eq "text blocker is case-insensitive" "7" "$(text_blockers 'BLOCKED BY #7')"
check_eq "text blocker ignores prose" "" "$(text_blockers 'this is not Blocked by #3')"

blocker_probe() ( # <native-mode> <native-json> <body> <state-of-12>
  SLUG="acme/widget"
  mode=$1; json=$2; body=$3; state12=$4
  gh() {
    case "$*" in
      *dependencies/blocked_by*)
        case "$mode" in
          error) printf 'gh: HTTP 500\n' >&2; return 1 ;;
          404) printf 'gh: Not Found (HTTP 404)\n' >&2; return 1 ;;
          *) printf '%s\n' "$json"; return 0 ;;
        esac
        ;;
      *issues/12*) printf '%s\n' "$state12"; return 0 ;;
    esac
    return 1
  }
  issue_blocked 5 "$body"
)
blocker_allows() ( blocker_probe "$@" && return 1; return 0 )

check_ok "an open native blocker holds the ticket" \
  blocker_probe json '[{"number":12,"state":"open"}]' '' open
check_ok "a closed native blocker allows the ticket" \
  blocker_allows json '[{"number":12,"state":"closed"}]' '' open
check_ok "a text 'Blocked by #N' blocker holds while open" \
  blocker_probe json '[]' 'Blocked by #12' open
check_ok "a text 'Blocked by #N' blocker allows when closed" \
  blocker_allows json '[]' 'Blocked by #12' closed
check_ok "a dependency API error holds the ticket" \
  blocker_probe error '' '' open
check_ok "a dependency API 404 means no native links" \
  blocker_allows 404 '' '' open

# native blockers are paginated: an open blocker on page 2 still holds
native_paged_blockers() (
  SLUG="acme/widget"
  gh() {
    case "$*" in
      *'dependencies/blocked_by?per_page=100&page=1'*)
        jq -n '[range(100) as $i | {number: ($i + 1), state: "closed", repository_url: "https://api.github.com/repos/acme/widget"}]'
        ;;
      *'dependencies/blocked_by?per_page=100&page=2'*)
        printf '[{"number":999,"state":"open","repository_url":"https://api.github.com/repos/acme/widget"}]\n'
        ;;
      *) printf '[]\n' ;;
    esac
    return 0
  }
  issue_blocked 5 ""
)
check_ok "native blockers are read beyond the first page" native_paged_blockers

# blocker identity is repository + number: a closed other/repo#12 must not
# satisfy an open local #12
blocker_repo_identity() (
  SLUG="acme/widget"
  gh() {
    case "$*" in
      *dependencies/blocked_by*)
        printf '[{"number":12,"state":"closed","repository_url":"https://api.github.com/repos/other/repo"}]\n'
        ;;
      *'issues/12'*) printf 'open\n' ;;
    esac
    return 0
  }
  issue_blocked 5 'Blocked by #12'
)
check_ok "a closed cross-repo #12 does not satisfy an open local #12" blocker_repo_identity

# the explicit repository form matches that repository's blocker
blocker_repo_explicit() (
  SLUG="acme/widget"
  gh() {
    case "$*" in
      *dependencies/blocked_by*)
        printf '[{"number":12,"state":"closed","repository_url":"https://api.github.com/repos/other/repo"}]\n'
        ;;
      *'issues/12'*) printf 'open\n' ;;
    esac
    return 0
  }
  issue_blocked 5 'Blocked by other/repo#12'
  rc=$?
  [ "$rc" -eq 1 ]
)
check_ok "a cross-repo blocker matches by repository and number" blocker_repo_explicit

hold_reason_for() ( # <body> <running-files>
  SLUG="acme/widget"
  gh() { case "$*" in *dependencies/blocked_by*) printf '[]\n' ;; esac; return 0; }
  ticket_hold_reason 5 "$1" "$2"
  printf '%s\n' "$TICKET_HOLD_REASON"
)
check_eq "a file clash holds the ticket" "files clash with a running ticket" \
  "$(hold_reason_for 'Files: a.c, b.c' 'b.c')"
check_eq "a non-overlapping file list is not held" "" \
  "$(hold_reason_for 'Files: a.c' 'src/b.c')"
check_eq "a ticket naming no files is never held" "" \
  "$(hold_reason_for 'just prose, no file list' 'a.c b.c')"
check_eq "Files: line splits commas and spaces" "$(printf 'src/a.c\nsrc/b.c')" \
  "$(named_files 'Files: src/a.c, src/b.c')"
check_eq "backticked path on a Files: line counts" "lib/x.sh" \
  "$(named_files 'Files: `lib/x.sh`')"
check_eq "backticked non-path is ignored" "" "$(named_files 'Files: `build`')"

# a backticked name that exists in the repo is a file even without '/' or '.'
mkdir -p "$TMP/named-repo"
printf 'bin\n' >"$TMP/named-repo/belt"
named_existing_file() ( PROJECT="$TMP/named-repo"; WORKTREE=""; named_files 'Files: `belt`' )
check_eq "a backticked existing extensionless file counts" "belt" "$(named_existing_file)"
named_missing_file() ( PROJECT="$TMP/named-repo"; WORKTREE=""; named_files 'Files: `nosuchcommand`' )
check_eq "a backticked missing extensionless name stays ignored" "" "$(named_missing_file)"

cap_checks() (
  MAX_PARALLEL=0
  under_parallel_cap "1:1 2:2 3:3" || return 1
  MAX_PARALLEL=1
  under_parallel_cap "" || return 1
  under_parallel_cap "1:1" && return 1
  return 0
)
check_ok "MAX_PARALLEL=0 means no cap, a positive value still caps" cap_checks

queue_starts_all() ( # MAX_PARALLEL=0 starts every frontier ticket in one round
  SLUG="acme/widget"; PROJECT="$TMP"; MAX_PARALLEL=0; PAUSE_WINDOWS=""; BELT_POLL_SECONDS=0
  WORKER_CMD="true"; REVIEWER_CMD="true"; BELT_HOME="$TMP/queue-home"
  started="$TMP/queue-started"; served="$TMP/queue-served"
  : >"$started"; : >"$served"
  fetch_queue() {
    if [ ! -s "$served" ]; then
      printf '11\n12\n13\n' >"$served"
      printf '11\n12\n13\n'
    fi
    return 0
  }
  gh() {
    case "$*" in
      *dependencies/blocked_by*) printf '[]\n'; return 0 ;;
      *'issue view'*) printf '\n'; return 0 ;;
    esac
    return 0
  }
  ticket_run() { printf '%s\n' "$1" >>"$started"; }
  run_queue >/dev/null 2>&1 || return 1
  [ "$(sort "$started" | tr '\n' ' ')" = "11 12 13 " ]
)
check_ok "MAX_PARALLEL=0 starts every frontier ticket" queue_starts_all

queue_holds_clash() ( # a clashing ticket waits until the running one finishes
  SLUG="acme/widget"; PROJECT="$TMP"; MAX_PARALLEL=0; PAUSE_WINDOWS=""; BELT_POLL_SECONDS=1
  WORKER_CMD="true"; REVIEWER_CMD="true"; BELT_HOME="$TMP/clash-home"
  seq="$TMP/clash-seq"; served="$TMP/clash-served"; done22="$TMP/clash-done-22"
  : >"$seq"; rm -f "$served" "$done22"
  fetch_queue() {
    if [ ! -e "$served" ]; then : >"$served"; printf '21\n22\n'; return 0; fi
    [ -e "$done22" ] || printf '22\n'
    return 0
  }
  gh() {
    case "$*" in
      *dependencies/blocked_by*) printf '[]\n'; return 0 ;;
      *'issue view 21'*) printf 'Files: src/a.c\n'; return 0 ;;
      *'issue view 22'*) printf 'Files: src/a.c\n'; return 0 ;;
    esac
    return 0
  }
  ticket_run() {
    printf 'start %s\n' "$1" >>"$seq"
    sleep 1
    printf 'end %s\n' "$1" >>"$seq"
    [ "$1" = 22 ] && : >"$done22"
    return 0
  }
  run_queue >/dev/null 2>&1 || return 1
  [ "$(cat "$seq")" = "$(printf 'start 21\nend 21\nstart 22\nend 22')" ]
)
check_ok "a file clash holds until the running ticket finishes" queue_holds_clash

# claiming is atomic per issue: a duplicate candidate never starts, and it must
# not delete the original's reservation (which would let a clashing ticket start)
queue_claim_is_atomic() (
  SLUG="acme/widget"; PROJECT="$TMP"; MAX_PARALLEL=0; PAUSE_WINDOWS=""; BELT_POLL_SECONDS=0
  WORKER_CMD="true"; REVIEWER_CMD="true"; BELT_HOME="$TMP/claim-home"
  seq="$TMP/claim-seq"
  rm -f "$TMP"/claim-*
  : >"$seq"
  fetch_queue() {
    if [ ! -e "$TMP/claim-done-31" ]; then printf '31\n32\n'; return 0; fi
    [ -e "$TMP/claim-done-32" ] || printf '32\n'
    return 0
  }
  gh() {
    case "$*" in
      *dependencies/blocked_by*) printf '[]\n'; return 0 ;;
      *'issue view 31'*)
        case "$*" in *'--json labels'*) return 0 ;; esac
        if [ -e "$TMP/claim-seen-31" ]; then printf 'prose only\n'; else
          : >"$TMP/claim-seen-31"
          printf 'Files: src/a.c\n'
        fi
        return 0
        ;;
      *'issue view 32'*)
        case "$*" in *'--json labels'*) return 0 ;; esac
        printf 'Files: src/a.c\n'
        return 0
        ;;
    esac
    return 0
  }
  ticket_run() {
    if [ "$1" = 31 ]; then
      if [ -e "$TMP/claim-active-31" ]; then
        printf 'duplicate 31\n' >>"$seq"
        return 0
      fi
      : >"$TMP/claim-active-31"
      printf 'start 31\n' >>"$seq"
      sleep 2
      printf 'end 31\n' >>"$seq"
      rm -f "$TMP/claim-active-31"
      : >"$TMP/claim-done-31"
    else
      printf 'start 32\n' >>"$seq"
      [ -e "$TMP/claim-done-31" ] || printf 'overlap 32\n' >>"$seq"
      printf 'end 32\n' >>"$seq"
      : >"$TMP/claim-done-32"
    fi
    return 0
  }
  run_queue >/dev/null 2>&1 || return 1
  [ "$(cat "$seq")" = "$(printf 'start 31\nend 31\nstart 32\nend 32')" ]
)
check_ok "a duplicate claim never launches or drops the file reservation" queue_claim_is_atomic

# a queue where every ticket is held is rechecked, never treated as empty
queue_held_rechecks() (
  SLUG="acme/widget"; PROJECT="$TMP"; MAX_PARALLEL=0; PAUSE_WINDOWS=""; BELT_POLL_SECONDS=0
  WORKER_CMD="true"; REVIEWER_CMD="true"; BELT_HOME="$TMP/held-home"; BELT_NO_SLEEP=1
  started="$TMP/held-started"; rm -f "$started"
  held_state="$TMP/held-state"; printf '0\n' >"$held_state"
  fetch_queue() {
    [ -e "$started" ] && return 0
    printf '41\n'
    return 0
  }
  gh() {
    case "$*" in
      *dependencies/blocked_by*) printf '[]\n'; return 0 ;;
      *'--json labels'*) return 0 ;;
      *'issue view'*) printf 'Blocked by #99\n'; return 0 ;;
      *'issues/99'*)
        n=$(cat "$held_state"); n=$((n + 1)); printf '%s\n' "$n" >"$held_state"
        if [ "$n" -lt 2 ]; then printf 'open\n'; else printf 'closed\n'; fi
        return 0
        ;;
    esac
    return 0
  }
  ticket_run() { : >"$started"; }
  run_queue >/dev/null 2>&1 || return 1
  [ -e "$started" ]
)
check_ok "a fully held queue is rechecked instead of exiting" queue_held_rechecks


check_slots_serialize() (
  BELT_HOME="$TMP/check-slots-home"; CHECK_SLOTS=1; DEVICE_LOCK=""; CHECK_SLOT_LOCK=""
  marker="$TMP/check-slots-seq"; : >"$marker"
  seq_cmd="printf 'start\\n' >>'$marker'; sleep 1; printf 'end\\n' >>'$marker'"
  ( run_check_command probe "$seq_cmd" ) &
  ( run_check_command probe "$seq_cmd" ) &
  wait
  [ "$(cat "$marker")" = "$(printf 'start\nend\nstart\nend')" ]
)
check_ok "CHECK_SLOTS=1 serializes check commands" check_slots_serialize


# ------------------------------------------------------------------- locks ---

lock="$TMP/test.lock"
check_ok "acquire free lock" acquire_lock "$lock" 0
check_ok "lock holder alive" lock_holder_alive "$lock"
check_no "second acquire fails" acquire_lock "$lock" 0
release_lock "$lock"
check_no "released lock gone" lock_holder_alive "$lock"
mkdir "$lock"
printf '99999999\n' >"$lock/pid"
check_ok "stale lock is taken over" acquire_lock "$lock" 0
release_lock "$lock"

mkdir "$TMP/fresh.lock"
check_no "fresh pid-less lock is not stolen" acquire_lock "$TMP/fresh.lock" 0
check_ok "fresh pid-less lock still exists" test -d "$TMP/fresh.lock"
rm -rf "$TMP/fresh.lock"

# age is not proof the holder is gone: no pid means never steal it
mkdir "$TMP/old-pidless.lock"
touch -t 202001010000 "$TMP/old-pidless.lock"
check_no "old pid-less lock is never stolen" acquire_lock "$TMP/old-pidless.lock" 0
check_ok "old pid-less lock still exists" test -d "$TMP/old-pidless.lock"
rm -rf "$TMP/old-pidless.lock"

# two reclaimers must not delete a replacement lock (test hook replaces the
# lock after the stale check but before the reclaim)
mkdir "$TMP/race.lock"
printf '99999999\n' >"$TMP/race.lock/pid"
printf 'old.nonce\n' >"$TMP/race.lock/nonce"
replace_hook='printf "%s\n" $$ >"'"$TMP"'/race.lock/pid"; printf "new.nonce\n" >"'"$TMP"'/race.lock/nonce"'
reclaim_race() ( BELT_LOCK_RECLAIM_HOOK="$replace_hook" acquire_lock "$TMP/race.lock" 0 )
check_no "reclaimer never deletes a replacement lock" reclaim_race
check_ok "replacement lock keeps a live holder" lock_holder_alive "$TMP/race.lock"
check_eq "replacement lock keeps its holder pid" "$$" "$(cat "$TMP/race.lock/pid" 2>/dev/null)"
rm -rf "$TMP/race.lock"

( acquire_lock "$TMP/sub.lock" 0 ) &
subpid=$!
wait "$subpid"
check_eq "lock pid is the subshell holder, not the dispatcher" "$subpid" "$(cat "$TMP/sub.lock/pid" 2>/dev/null)"
rm -rf "$TMP/sub.lock"

# one run per ticket: a live ticket lock must stop a second run before any gh call
ticket_lock_refused() (
  BELT_PROJECT="$TMP/ticket-proj"
  mkdir -p "$TMP/ticket-proj"
  printf 'REPO="acme/widget"\nWORKER_CMD="true"\nREVIEWER_CMD="true"\n' >"$TMP/ticket-proj/belt.conf"
  REPO="acme/widget"
  N=55
  SLUG="acme/widget"
  TICKET_DIR="$BELT_HOME/acme__widget/55"
  mkdir -p "$TICKET_DIR"
  acquire_lock "$TICKET_DIR/ticket.lock" 0 || return 1
  rm -f "$TMP/gh-called"
  gh() { : >"$TMP/gh-called"; return 0; }
  ticket_run 55 >/dev/null 2>&1
  rc=$?
  release_lock "$TICKET_DIR/ticket.lock"
  [ "$rc" -ne 0 ] && [ ! -e "$TMP/gh-called" ]
)
check_ok "a second run of the same ticket is refused" ticket_lock_refused

# explicit 'belt run <issue>' applies the same blocker check as the queue
single_run_blocker_refused() (
  proj="$TMP/single-run-proj"
  mkdir -p "$proj"
  printf 'REPO="acme/widget"\nWORKER_CMD="true"\nREVIEWER_CMD="true"\n' >"$proj/belt.conf"
  marker="$TMP/single-run-started"
  rm -f "$marker"
  BELT_PROJECT="$proj"
  gh() {
    case "$*" in
      *dependencies/blocked_by*) printf '[]\n'; return 0 ;;
      *'issues/9'*) printf 'open\n'; return 0 ;;
      *'issue view'*)
        case "${SINGLE_RUN_MODE:-blocked}" in
          unreadable) printf 'boom\n' >&2; return 1 ;;
          *) printf 'Blocked by #9\n'; return 0 ;;
        esac
        ;;
    esac
    return 0
  }
  ticket_run() { : >"$marker"; return 0; }
  cmd_run 5 >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$marker" ]
)
SINGLE_RUN_MODE=blocked check_ok "belt run <issue> refuses a blocked ticket" single_run_blocker_refused
SINGLE_RUN_MODE=unreadable check_ok "belt run <issue> refuses an unreadable ticket" single_run_blocker_refused

# ------------------------------------------------------------ changed files ---

repo="$TMP/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email belt@example.com
git -C "$repo" config user.name belt
printf 'base\n' >"$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit -qm base
mkdir -p "$repo/newdir/sub"
printf 'a\n' >"$repo/newdir/a.txt"
printf 'secret\n' >"$repo/newdir/.env"
printf 'b\n' >"$repo/newdir/sub/b.txt"
WORKTREE="$repo"
TICKET_DIR="$TMP/collect-ticket"
mkdir -p "$TICKET_DIR"
list="$TMP/changed.nul"
check_ok "collect_files succeeds" collect_files "$list"
count=0
while IFS= read -r -d '' p; do count=$((count + 1)); done <"$list"
check_eq "collect_files expands an untracked directory into files" 3 "$count"
dirs=0
while IFS= read -r -d '' p; do [ -d "$repo/$p" ] && dirs=$((dirs + 1)); done <"$list"
check_eq "collect_files emits no directory paths" 0 "$dirs"

# a filename that looks like a wildcard must be staged literally, never expanded
literal="$TMP/literal-repo"
mkdir -p "$literal"
git -C "$literal" init -q
git -C "$literal" config user.email belt@example.com
git -C "$literal" config user.name belt
printf 'base\n' >"$literal/base.txt"
git -C "$literal" add base.txt
git -C "$literal" commit -qm base
printf 'secret\n' >"$literal/my-secret.env"
printf 'wild\n' >"$literal/*"
check_ok "literal add stages a wildcard filename" git_add_explicit "$literal" "*"
check_eq "literal add never expands the filename" "*" "$(git -C "$literal" diff --cached --name-only)"

# ------------------------------------------------ commit/PR safety harness ---

commit_remote="$TMP/commit-remote.git"
commit_proj="$TMP/commit-proj"
git init -q --bare "$commit_remote"
git clone -q "$commit_remote" "$commit_proj"
git -C "$commit_proj" config user.email belt@example.com
git -C "$commit_proj" config user.name belt
printf 'SECRET=one\n' >"$commit_proj/.env"
printf 'base\n' >"$commit_proj/base.txt"
git -C "$commit_proj" add .env base.txt
git -C "$commit_proj" commit -qm base
git -C "$commit_proj" branch -M main
git -C "$commit_proj" push -q -u origin main
git -C "$commit_proj" checkout -q -b belt/8
git -C "$commit_proj" push -q -u origin belt/8
printf 'SECRET=two\n' >"$commit_proj/.env"
printf 'feature\n' >"$commit_proj/feature.txt"
commit_tracked_excluded() (
  WORKTREE="$commit_proj"
  TICKET_DIR="$TMP/commit-ticket"
  OUT_DIR="$TICKET_DIR/out"
  mkdir -p "$OUT_DIR"
  BRANCH="belt/8"; N=8; ISSUE_TITLE="t"; BASE="main"; PR=9
  SLUG="acme/widget"; LOG="$TMP/commit.log"
  STATUS_REASON=""; NOCHANGE_TEXT=""
  station_commit_push_pr
)
check_no "tracked excluded changes left out of the commit are refused" commit_tracked_excluded

# a worker file literally named '*' must not turn into a pathspec that stages secrets
wild_remote="$TMP/wild-remote.git"
wild_proj="$TMP/wild-proj"
git init -q --bare "$wild_remote"
git clone -q "$wild_remote" "$wild_proj"
git -C "$wild_proj" config user.email belt@example.com
git -C "$wild_proj" config user.name belt
printf 'base\n' >"$wild_proj/base.txt"
git -C "$wild_proj" add base.txt
git -C "$wild_proj" commit -qm base
git -C "$wild_proj" branch -M main
git -C "$wild_proj" push -q -u origin main
git -C "$wild_proj" checkout -q -b belt/10
git -C "$wild_proj" push -q -u origin belt/10
printf 'wild\n' >"$wild_proj/*"
printf 'TOKEN=one\n' >"$wild_proj/my-secret.env"
wildcard_commit_is_literal() (
  WORKTREE="$wild_proj"
  TICKET_DIR="$TMP/wild-ticket"
  OUT_DIR="$TICKET_DIR/out"
  mkdir -p "$OUT_DIR"
  BRANCH="belt/10"; N=10; ISSUE_TITLE="t"; BASE="main"; PR=10
  SLUG="acme/widget"; LOG="$TMP/wild.log"
  STATUS_REASON=""; NOCHANGE_TEXT=""
  station_commit_push_pr || return 1
  git -C "$wild_proj" show --name-only --pretty=format: HEAD | grep -Fxq -- '*' || return 1
  ! git -C "$wild_proj" show --name-only --pretty=format: HEAD | grep -Fxq -- 'my-secret.env'
)
check_ok "a wildcard filename never stages an ignored secret" wildcard_commit_is_literal

# a resumed PR must target the configured base branch
base_remote="$TMP/base-remote.git"
base_proj="$TMP/base-proj"
git init -q --bare "$base_remote"
git clone -q "$base_remote" "$base_proj"
git -C "$base_proj" config user.email belt@example.com
git -C "$base_proj" config user.name belt
printf 'base\n' >"$base_proj/base.txt"
git -C "$base_proj" add base.txt
git -C "$base_proj" commit -qm base
git -C "$base_proj" branch -M main
git -C "$base_proj" push -q -u origin main
git -C "$base_proj" checkout -q -b belt/5
printf 'change\n' >"$base_proj/change.txt"
git -C "$base_proj" add change.txt
git -C "$base_proj" commit -qm change
base_sha=$(git -C "$base_proj" rev-parse HEAD)
git -C "$base_proj" push -q -u origin belt/5
git -C "$base_proj" checkout -q main
pr_other_base() (
  PROJECT="$base_proj"; BASE_BRANCH="develop"; SLUG="acme/widget"; N=5; BRANCH="belt/5"
  STATE_DIR="$BELT_HOME/acme__widget"; WORKTREE="$STATE_DIR/worktrees/5"
  LOG="$TMP/pr-base.log"
  mkdir -p "$STATE_DIR/worktrees"
  gh() {
    case "$1 $2" in
      "pr list") printf '6\n' ;;
      "pr view")
        case "$*" in
          *baseRefName*) printf 'main\n' ;;
          *) printf '%s\n' "$base_sha" ;;
        esac ;;
    esac
    return 0
  }
  station_worktree
)
check_no "resumed PR targeting another base is refused" pr_other_base

# rerunning a ticket without a PR must drop unreviewed commits from the branch
reset_remote="$TMP/reset-remote.git"
reset_proj="$TMP/reset-proj"
git init -q --bare "$reset_remote"
git clone -q "$reset_remote" "$reset_proj"
git -C "$reset_proj" config user.email belt@example.com
git -C "$reset_proj" config user.name belt
printf 'base\n' >"$reset_proj/base.txt"
git -C "$reset_proj" add base.txt
git -C "$reset_proj" commit -qm base
git -C "$reset_proj" branch -M main
git -C "$reset_proj" push -q -u origin main
git -C "$reset_proj" checkout -q -b belt/9
printf 'TOKEN=secret\n' >"$reset_proj/secret.env"
git -C "$reset_proj" add secret.env
git -C "$reset_proj" commit -qm 'secret left by a failed run'
git -C "$reset_proj" checkout -q main
reset_base_head=$(git -C "$reset_proj" rev-parse origin/main)
rerun_discards_leftovers() (
  PROJECT="$reset_proj"; BASE_BRANCH="main"; SLUG="acme/widget"; N=9; BRANCH="belt/9"
  STATE_DIR="$BELT_HOME/acme__widget"; WORKTREE="$STATE_DIR/worktrees/9"
  LOG="$TMP/reset.log"
  mkdir -p "$STATE_DIR/worktrees"
  gh() { printf '\n'; return 0; }
  station_worktree || return 1
  [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$reset_base_head" ] || return 1
  [ ! -e "$WORKTREE/secret.env" ]
)
check_ok "rerun discards unreviewed commits on the reused branch" rerun_discards_leftovers

# a rename out of a risky directory must still count as that risky path
risk_repo="$TMP/risk-repo"
mkdir -p "$risk_repo/db"
git -C "$risk_repo" init -q
git -C "$risk_repo" config user.email belt@example.com
git -C "$risk_repo" config user.name belt
printf 'schema\n' >"$risk_repo/db/schema.sql"
git -C "$risk_repo" add db/schema.sql
git -C "$risk_repo" commit -qm base
git -C "$risk_repo" update-ref refs/remotes/origin/main HEAD
git -C "$risk_repo" mv db/schema.sql schema.sql
git -C "$risk_repo" commit -qm rename
risky_after_rename() (
  WORKTREE="$risk_repo"; BASE="main"; ISSUE_BODY=""
  TICKET_DIR="$TMP/risk-ticket"; LOG="$TMP/risk.log"
  mkdir -p "$TICKET_DIR"
  ticket_is_risky
)
RISKY_PATHS="db/"
check_ok "a file renamed out of a risky folder is still risky" risky_after_rename
RISKY_PATHS=""

reviewer_choice() ( # <worktree> <risky-paths> <risky-cmd> <routine-cmd>
  WORKTREE="$1"; BASE="main"; RISKY_PATHS="$2"
  RISKY_REVIEWER_CMD="$3"; REVIEWER_CMD="$4"
  ISSUE_BODY=""; TICKET_DIR="$TMP/reviewer-choice-ticket"; LOG="$TMP/reviewer-choice.log"
  mkdir -p "$TICKET_DIR"
  choose_reviewer
  printf '%s\n' "$REVIEWER_CHOICE_CMD"
)
check_eq "a risky diff uses RISKY_REVIEWER_CMD" "riskycmd" \
  "$(reviewer_choice "$risk_repo" 'db/' riskycmd routinecmd)"
check_eq "a routine diff uses REVIEWER_CMD" "routinecmd" \
  "$(reviewer_choice "$review_proj" 'db/' riskycmd routinecmd)"
check_eq "an unset RISKY_REVIEWER_CMD falls back" "routinecmd" \
  "$(reviewer_choice "$risk_repo" 'db/' '' routinecmd)"
check_eq "a risk failure is treated as risky" "riskycmd" \
  "$(reviewer_choice "$TMP/no-such-worktree" 'db/' riskycmd routinecmd)"

# ---------------------------------------------------------------- symlinks ---

mkdir -p "$TMP/bin"
ln -s "$ROOT/belt" "$TMP/bin/belt"
belt_help_ok() { "$TMP/bin/belt" help >/dev/null 2>&1; }
check_ok "belt help through a symlink" belt_help_ok

# ------------------------------------------------------------- owner steps ---

TICKET_DIR="$TMP/owner-ticket"
OUT_DIR="$TICKET_DIR/out"
N=77
SLUG="acme/widget"
mkdir -p "$OUT_DIR"
printf 'Create an Apple developer account\n' >"$OUT_DIR/owner-steps.txt"
create_owner_issue() { return 1; }
process_owner_steps >/dev/null 2>&1
check_no "failed owner step is not marked done" grep -Fxq -- "Create an Apple developer account" "$TICKET_DIR/owner-steps.done"
create_owner_issue() { return 0; }
process_owner_steps >/dev/null 2>&1
check_ok "created owner step is marked done" grep -Fxq -- "Create an Apple developer account" "$TICKET_DIR/owner-steps.done"

# nochange already finished the ticket: callers must not continue to review
nochange_stops_flow() (
  N=9; STATUS_REASON=""; NOCHANGE_TEXT="nothing to change"
  station_commit_push_pr() { return 2; }
  ticket_nochange() { return 0; }
  push_pr_or_stop
  [ "$?" -ne 0 ]
)
check_ok "nochange stops instead of continuing to review" nochange_stops_flow

# --------------------------------------------------------- watch on-call ---

# the owner-steps test above replaced create_owner_issue with a stub; restore it
unset -f create_owner_issue
BELT_COMMON_LOADED=""
. "$ROOT/lib/common.sh"

watch_proj="$TMP/watch-proj"
watch_oncall_count="$TMP/watch-oncall-count"
watch_oncall_pwd="$TMP/watch-oncall-pwd"
watch_notify_file="$TMP/watch-notify.txt"
watch_creates="$TMP/watch-creates.txt"
watch_titles="$TMP/watch-titles.txt"
watch_backup="$TMP/watch-backup"
watch_oncall_script="$TMP/watch-oncall.sh"
watch_notify_script="$TMP/watch-notify.sh"
mkdir -p "$watch_proj"
printf '# watch project\n' >"$watch_proj/BELT.md"
cat >"$watch_oncall_script" <<'ONCALL'
#!/usr/bin/env bash
printf 'run\n' >>"$ONCALL_COUNT"
pwd -P >>"$ONCALL_PWD"
printf 'fixing the ticket\nONCALL: %s\n' "${ONCALL_VERDICT:-FIXED}"
ONCALL
cat >"$watch_notify_script" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s\n' "$BELT_MESSAGE" >>"$NOTIFY_FILE"
NOTIFY
cat >"$watch_proj/belt.conf" <<EOF
REPO="acme/widget"
ONCALL_CMD="ONCALL_COUNT='$watch_oncall_count' ONCALL_PWD='$watch_oncall_pwd' bash '$watch_oncall_script'"
OWNER_NOTIFY_CMD="NOTIFY_FILE='$watch_notify_file' bash '$watch_notify_script'"
BACKUP_DIR="$watch_backup"
EOF

# one fake gh for every watch scenario: STUCK_FLAG decides whether a stuck issue
# exists, CI_BUCKET drives `gh pr checks`.
watch_gh() {
  case "$*" in
    *'--label stuck'*)
      if [ -e "${STUCK_FLAG:-/nonexistent}" ]; then printf '[{"number":61}]\n'; else printf '[]\n'; fi
      ;;
    *'pr checks'*)
      printf '[{"bucket":"%s"}]\n' "${CI_BUCKET:-pass}"
      ;;
    *'pr list'*)
      printf '[]\n'
      ;;
    *'issue create'*)
      printf '%s\n' "$*" >>"${WATCH_CREATES:-/dev/null}"
      # real gh would list this title next time; keep the dedupe honest offline
      if [ -n "${WATCH_TITLES:-}" ]; then
        printf '%s\n' "$*" | sed -n 's/.*--title \(.*\) --label.*/\1/p' >>"$WATCH_TITLES"
      fi
      printf 'https://github.com/acme/widget/issues/99\n'
      ;;
    *'issue list'*'--json title'*)
      if [ -n "${WATCH_TITLES:-}" ] && [ -s "$WATCH_TITLES" ]; then cat "$WATCH_TITLES"; fi
      ;;
    *'issue list'*) printf '[]\n' ;;
    *'issues'*) printf '[]\n' ;;
    *) return 0 ;;
  esac
}

watch_pass() { # watch_pass <belt-home> [stuck-flag]
  BELT_HOME="$1"; export BELT_HOME
  STUCK_FLAG="${2:-}"; export STUCK_FLAG
  ONCALL_COUNT="$watch_oncall_count"; export ONCALL_COUNT
  ONCALL_PWD="$watch_oncall_pwd"; export ONCALL_PWD
  WATCH_TITLES="$watch_titles"; export WATCH_TITLES
  gh() { watch_gh "$@"; }
  cmd_watch "$watch_proj" >/dev/null 2>&1
  printf '%s\n' "$?"
}

watch_stuck_flags() ( # a persistent key retries the on-call every pass until the cap escalates
  home="$TMP/watch-home-stuck"
  flag="$TMP/watch-stuck-flag"
  rm -rf "$home" "$watch_oncall_count" "$watch_oncall_pwd"
  rm -f "$watch_creates" "$watch_titles"
  : >"$flag"
  WATCH_CREATES="$watch_creates"; export WATCH_CREATES
  watch_pass "$home" "$flag" >/dev/null || return 1
  [ "$(grep -c '' "$watch_oncall_count")" -eq 1 ] || return 1
  [ "$(sed -n 1p "$watch_oncall_pwd")" = "$(cd -P "$watch_proj" && pwd)" ] || return 1
  # the same problem on the next pass: watch.seen must not starve the retry
  watch_pass "$home" "$flag" >/dev/null || return 1
  [ "$(grep -c '' "$watch_oncall_count")" -eq 2 ] || return 1
  # the third pass hands the ticket to the owner instead of a third on-call
  watch_pass "$home" "$flag" >/dev/null || return 1
  [ "$(grep -c '' "$watch_oncall_count")" -eq 2 ] || return 1
  grep -q 'keeps failing' "$watch_creates" || return 1
  # condition clears: watch.seen re-arms
  rm -f "$flag"
  watch_pass "$home" >/dev/null || return 1
  [ ! -s "$home/acme__widget/watch.seen" ]
)
check_ok "a persistent problem retries the on-call until the cap escalates" watch_stuck_flags

watch_owner_verdict() { # ONCALL: OWNER opens one needs-owner issue + one ping
  home="$TMP/watch-home-owner"
  flag="$TMP/watch-owner-flag"
  rm -rf "$home" "$watch_oncall_count" "$watch_notify_file" "$watch_creates"
  rm -f "$watch_titles"
  WATCH_TITLES="$watch_titles"; export WATCH_TITLES
  : >"$flag"
  WATCH_CREATES="$watch_creates"; export WATCH_CREATES
  ONCALL_VERDICT="OWNER look at the deploy key"; export ONCALL_VERDICT
  BELT_HOME="$home"; export BELT_HOME
  ONCALL_COUNT="$watch_oncall_count"; export ONCALL_COUNT
  ONCALL_PWD="$watch_oncall_pwd"; export ONCALL_PWD
  STUCK_FLAG="$flag"; export STUCK_FLAG
  gh() { watch_gh "$@"; }
  cmd_watch "$watch_proj" >/dev/null 2>&1 || return 1
  cmd_watch "$watch_proj" >/dev/null 2>&1 || return 1
  [ "$(grep -c 'needs an owner: look at the deploy key' "$watch_creates")" -eq 1 ] || return 1
  [ "$(grep -c '' "$watch_notify_file")" -eq 1 ]
}
check_ok "an ONCALL ending OWNER opens needs-owner and pings exactly once" watch_owner_verdict

watch_restart_cap() ( # a 3rd on-call for the same issue opens needs-owner instead
  home="$TMP/watch-home-cap"
  flag="$TMP/watch-cap-flag"
  rm -rf "$home" "$watch_oncall_count" "$watch_creates"
  rm -f "$watch_titles"
  : >"$flag"
  WATCH_CREATES="$watch_creates"; export WATCH_CREATES
  i=0
  while [ "$i" -lt 3 ]; do
    watch_pass "$home" "$flag" >/dev/null
    rm -f "$flag"
    watch_pass "$home" >/dev/null
    : >"$flag"
    i=$((i + 1))
  done
  [ "$(grep -c '' "$watch_oncall_count")" -eq 2 ] || return 1
  grep -q 'keeps failing' "$watch_creates"
)
check_ok "a third on-call for one issue hands it to the owner" watch_restart_cap

# a live ticket with CI running/queued is waiting normally, never silent
watch_silent_home="$TMP/watch-silent-home"
watch_silent_state="$watch_silent_home/acme__widget/71"
mkdir -p "$watch_silent_state/ticket.lock"
printf '%s\n' "$$" >"$watch_silent_state/ticket.lock/pid"
printf 'nonce\n' >"$watch_silent_state/ticket.lock/nonce"
printf 'working\n' >"$watch_silent_state/log"
touch -t 202001010000 "$watch_silent_state/log"
watch_silent_key_for() { # <ci-bucket>
  BELT_HOME="$watch_silent_home"; export BELT_HOME
  SLUG="acme/widget"
  CI_BUCKET="$1"
  gh() { watch_gh "$@"; }
  # two samples showing no real CPU use: this test's own shell stands in for the run
  printf '%s:%s:1\n' "$$" "$(slot_cpu_cs "$$")" >"$watch_silent_home/acme__widget/watch-cpu.71"
  watch_silent_key 71
}
check_eq "a CI-running ticket is not silent" "" "$(watch_silent_key_for pending)"
check_eq "a quiet ticket with no CI in progress is silent" "silent:71" "$(watch_silent_key_for fail)"

# a custom runner that exposes no pid has no CPU evidence: busy, never silent
watch_silent_nopid_home="$TMP/watch-silent-nopid-home"
watch_silent_nopid_state="$watch_silent_nopid_home/acme__widget/72"
mkdir -p "$watch_silent_nopid_state"
printf 'working\n' >"$watch_silent_nopid_state/log"
touch -t 202001010000 "$watch_silent_nopid_state/log" "$watch_silent_nopid_state"
watch_silent_nopid() (
  BELT_HOME="$watch_silent_nopid_home"; export BELT_HOME
  SLUG="acme/widget"
  TICKET_ALIVE_CMD='true'; export TICKET_ALIVE_CMD
  CI_BUCKET=fail
  gh() { watch_gh "$@"; }
  watch_silent_key 72
)
check_eq "a custom runner with no exposed pid is never flagged silent" "" \
  "$(watch_silent_nopid)"

watch_lock_blocks() { # a live pass lock stops a second pass (and runs no on-call)
  home="$TMP/watch-home-lock"
  flag="$TMP/watch-lock-flag"
  rm -rf "$home" "$watch_oncall_count"
  : >"$flag"
  mkdir -p "$home/acme__widget/watch.lock"
  printf '%s\n' "$$" >"$home/acme__widget/watch.lock/pid"
  printf 'nonce\n' >"$home/acme__widget/watch.lock/nonce"
  before=$(grep -c '' "$watch_oncall_count" 2>/dev/null || echo 0)
  watch_pass "$home" "$flag" >/dev/null
  [ "$(grep -c '' "$watch_oncall_count" 2>/dev/null || echo 0)" -eq "$before" ]
}
check_ok "the watch lock prevents an overlapping pass" watch_lock_blocks

# a claimed ticket whose holder died is stale: the recovery chain dead-ended
wait_for_file() { # <file> <seconds>; wait until the file exists and has content
  local f=${1:?} limit=${2:-15} i=0
  while [ ! -s "$f" ] && [ "$i" -lt "$limit" ]; do sleep 1; i=$((i + 1)); done
  [ -s "$f" ]
}
watch_dead_pid() { # a pid that is provably gone
  local p
  ( exit 0 ) &
  p=$!
  wait "$p" 2>/dev/null || true
  printf '%s\n' "$p"
}
watch_stale_home="$TMP/watch-stale-home"
watch_stale_state="$watch_stale_home/acme__widget/72"
mkdir -p "$watch_stale_state/ticket.lock"
printf 'nonce\n' >"$watch_stale_state/ticket.lock/nonce"
printf 'work\n' >"$watch_stale_state/log"
touch -t 202001010000 "$watch_stale_state/log" "$watch_stale_state/ticket.lock"
printf '%s\n' "$(watch_dead_pid)" >"$watch_stale_state/ticket.lock/pid"
watch_stale_key_for() {
  BELT_HOME="$watch_stale_home"; export BELT_HOME
  SLUG="acme/widget"
  watch_stale_key 72 "$(date '+%s')"
}
check_eq "a dead holder idle past SILENT_MIN is stale" "stale:72" "$(watch_stale_key_for)"
touch "$watch_stale_state/log"
check_eq "a dead holder that just stopped is not stale yet" "" "$(watch_stale_key_for)"
touch -t 202001010000 "$watch_stale_state/log"
watch_stale_collect() { # the collect key, with a claimed:belt issue for #72
  BELT_HOME="$watch_stale_home"; export BELT_HOME
  SLUG="acme/widget"
  gh() {
    case "$*" in
      *'--label claimed:belt'*) printf '[{"number":72,"labels":[{"name":"claimed:belt"}]}]\n' ;;
      *) printf '[]\n' ;;
    esac
  }
  out="$TMP/watch-stale-problems"
  watch_collect "$out" >/dev/null 2>&1
  cut -f1 "$out" | grep -x 'stale:72'
}
check_ok "watch_collect emits stale:<n> for a dead claimed ticket" watch_stale_collect
printf '%s\n' "$$" >"$watch_stale_state/ticket.lock/pid"
touch -t 202001010000 "$watch_stale_state/log" "$watch_stale_state/ticket.lock"
check_eq "a live holder is never stale" "" "$(watch_stale_key_for)"

# a project with its own ticket runner: custom label, branch prefix, log,
# liveness and restart command, with no ticket.lock and no belt install
runner_proj="$TMP/runner-proj"
runner_home="$TMP/runner-home"
runner_logs="$TMP/runner-logs"
runner_alive="$TMP/runner-alive"
runner_prompt="$TMP/runner-prompt"
runner_calls="$TMP/runner-calls"
mkdir -p "$runner_proj" "$runner_logs/81"
cat >"$runner_proj/belt.conf" <<EOF
REPO="acme/widget"
CLAIM_LABEL="claimed:pipeline"
BRANCH_PREFIX="pipeline/"
TICKET_LOG_CMD='printf "%s\n" "\$RUNNER_LOGS/\$BELT_ISSUE/run.log"'
TICKET_ALIVE_CMD='test -f "\$RUNNER_ALIVE"'
TICKET_RESTART_CMD='bash restart-pipeline.sh \$BELT_ISSUE'
ONCALL_EXTRA_RULES='Runner rule: check the pipeline dashboard.'
ONCALL_CMD='cp "\$BELT_PROMPT_FILE" "\$RUNNER_PROMPT"; printf "runner on-call\nONCALL: FIXED\n"'
OWNER_NOTIFY_CMD="true"
EOF
runner_gh() {
  printf '%s\n' "$*" >>"${RUNNER_CALLS:-/dev/null}"
  case "$*" in
    *'label create'*) return 0 ;;
    *'--label claimed:pipeline'*)
      printf '[{"number":81,"labels":[{"name":"claimed:pipeline"}]}]\n' ;;
    *'--label claimed:belt'*) printf '[]\n' ;;
    *'--head pipeline/81'*) printf '401\n' ;;
    *'--head belt/81'*) printf '\n' ;;
    *'pr checks 401'*) printf '[{"bucket":"fail"}]\n' ;;
    *'api repos/acme/widget/pulls/401'*) printf 'clean\n' ;;
    *'pr list'*'--json number,headRefName,headRefOid'*)
      printf '[{"number":401,"headRefName":"pipeline/81","headRefOid":"cafebabe0123456789abcdef0123456789abcdef"}]\n' ;;
    *'pr list'*'--json number,state,headRefName'*)
      printf '[{"number":401,"state":"OPEN","headRefName":"pipeline/81"}]\n' ;;
    *'issue create'*) printf 'https://github.com/acme/widget/issues/90\n' ;;
    *'issue list'*) printf '[]\n' ;;
    *'issues'*) printf '[]\n' ;;
    *) return 0 ;;
  esac
}
runner_load() { # the project's config and a fake gh, per test subshell
  BELT_HOME="$runner_home"; export BELT_HOME
  RUNNER_LOGS="$runner_logs"; export RUNNER_LOGS
  RUNNER_ALIVE="$runner_alive"; export RUNNER_ALIVE
  RUNNER_PROMPT="$runner_prompt"; export RUNNER_PROMPT
  RUNNER_CALLS="$runner_calls"; export RUNNER_CALLS
  LOG="$TMP/runner.log"
  load_config "$runner_proj" >/dev/null || return 1
  SLUG="acme/widget"
  gh() { runner_gh "$@"; }
}
runner_collect() ( # the custom label and branch prefix drive discovery
  runner_load || return 1
  rm -rf "$runner_home"; : >"$runner_alive"; : >"$runner_calls"
  # a pid lets this discovery test reach the branch-prefix PR lookup; the
  # no-pid case has its own silent test below
  mkdir -p "$runner_home/acme__widget/81/ticket.lock"
  printf '%s\n' "$$" >"$runner_home/acme__widget/81/ticket.lock/pid"
  printf '%s:%s:1\n' "$$" "$(slot_cpu_cs "$$")" >"$runner_home/acme__widget/watch-cpu.81"
  printf 'run\n' >"$runner_logs/81/run.log"
  touch -t 202001010000 "$runner_logs/81/run.log" "$runner_logs/81"
  out="$TMP/runner-problems"
  watch_collect "$out" >/dev/null 2>&1 || return 1
  grep -q -- '--label claimed:pipeline' "$runner_calls" || return 1
  ! grep -q -- '--label claimed:belt' "$runner_calls" || return 1
  grep -q -- '--head pipeline/81' "$runner_calls" || return 1
  ! grep -q -- '--head belt/81' "$runner_calls" || return 1
  ! grep -q 'stale:81' "$out"
)
check_ok "a custom CLAIM_LABEL and BRANCH_PREFIX are detected" runner_collect

runner_live_dead() ( # alive cmd says live -> no stale; dead -> stale, no lock
  runner_load || return 1
  rm -rf "$runner_home"
  printf 'run\n' >"$runner_logs/81/run.log"
  touch -t 202001010000 "$runner_logs/81/run.log" "$runner_logs/81"
  : >"$runner_alive"
  [ -z "$(watch_stale_key 81 "$(date '+%s')")" ] || return 1
  rm -f "$runner_alive"
  [ "$(watch_stale_key 81 "$(date '+%s')")" = "stale:81" ] || return 1
  [ ! -e "$runner_home/acme__widget/81/ticket.lock" ]
)
check_ok "a live TICKET_ALIVE_CMD is not stale and a dead one is" runner_live_dead

runner_restart_prompt() ( # the prompt offers the RESTART verdict and the extra rules
  runner_load || return 1
  rm -rf "$runner_home"; rm -f "$runner_prompt"; : >"$runner_alive"
  oncall_run_problem "stale:81" 81 stale >/dev/null 2>&1 || return 1
  prompt="$runner_home/acme__widget/oncall/stale_81/prompt.txt"
  [ -s "$prompt" ] || return 1
  grep -q 'ONCALL: RESTART <n>' "$prompt" || return 1
  grep -q 'ONCALL: RESTART 81' "$prompt" || return 1
  # the on-call never runs the restart command itself: the watch pass does
  ! grep -q 'bash restart-pipeline.sh' "$prompt" || return 1
  grep -q 'Runner rule: check the pipeline dashboard.' "$prompt" || return 1
  grep -q 'claimed:pipeline' "$prompt"
)
check_ok "the on-call prompt offers ONCALL: RESTART and ONCALL_EXTRA_RULES" runner_restart_prompt

default_runner_keys() ( # the new keys default to exactly today's behaviour
  proj="$TMP/default-keys-proj"; home="$TMP/default-keys-home"
  rm -rf "$proj" "$home"; mkdir -p "$proj"
  printf 'REPO="acme/widget"\n' >"$proj/belt.conf"
  BELT_HOME="$home"; export BELT_HOME
  LOG="$TMP/default-keys.log"
  load_config "$proj" >/dev/null || return 1
  SLUG="acme/widget"
  [ "$CLAIM_LABEL" = "claimed:belt" ] || return 1
  [ "$(branch_prefix)" = "belt/" ] || return 1
  [ -z "$TICKET_LOG_CMD" ] || return 1
  [ -z "$TICKET_ALIVE_CMD" ] || return 1
  [ -z "$ONCALL_EXTRA_RULES" ] || return 1
  [ "$(watch_restart_text 7)" = "belt run 7" ] || return 1
  [ "$(watch_ticket_log 7)" = "$home/acme__widget/7/log" ] || return 1
  playbook=$(watch_playbook)
  printf '%s\n' "$playbook" | grep -q 'ONCALL: RESTART <n>' || return 1
  printf '%s\n' "$playbook" | grep -q 'restarts the ticket outside it' || return 1
  # the playbook no longer tells the on-call to run the restart command
  ! printf '%s\n' "$playbook" | grep -q 'belt run <n>' || return 1
  printf '%s\n' "$playbook" | grep -q 'stale `claimed:belt`' || return 1
  mkdir -p "$home/acme__widget/7/ticket.lock"
  printf '%s\n' "$$" >"$home/acme__widget/7/ticket.lock/pid"
  watch_ticket_live 7 || return 1
  # FULL_SUITE_CMD empty keeps the suite off
  suite_start_detached >/dev/null 2>&1 || return 1
  [ ! -e "$home/acme__widget/suite.out" ] && [ ! -e "$home/acme__widget/suite.lock" ]
)
check_ok "the custom runner keys default to belt's own behaviour" default_runner_keys

# Round 4: a merge-conflicted belt PR gets no CI, so it is conflict:<n>, not silent:
conflict_home="$TMP/watch-conflict-home"
conflict_state="$conflict_home/acme__widget"
conflict_pr=310
conflict_sha="feedface0123456789abcdef0123456789abcdef"
conflict_gh() {
  case "$*" in
    *'api repos/acme/widget/pulls/310'*) printf 'dirty\n' ;;
    *'pr checks 310'*) return 0 ;;
    *'pr list'*'--json number,headRefName,headRefOid'*)
      printf '[{"number":310,"headRefName":"belt/63","headRefOid":"%s"}]\n' "$conflict_sha" ;;
    *'pr list'*'--head belt/63'*) printf '310\n' ;;
    *'pr list'*) printf '[]\n' ;;
    *'--label stuck'*|*'--label needs-lead'*|*'--label claimed:belt'*) printf '[]\n' ;;
    *'issue list'*) printf '[]\n' ;;
    *'issue create'*) printf 'https://github.com/acme/widget/issues/99\n' ;;
    *) return 0 ;;
  esac
}
conflict_first_seen() ( # the key waits CONFLICT_MIN before firing, then stays stable
  BELT_HOME="$TMP/conflict-first-home"; export BELT_HOME
  SLUG="acme/widget"
  CONFLICT_MIN=1 BELT_TIME_SCALE=60
  gh() { conflict_gh "$@"; }
  first=$(watch_conflict_key 63 "$conflict_pr" "$conflict_sha" 1000000)
  again=$(watch_conflict_key 63 "$conflict_pr" "$conflict_sha" 1000002)
  [ -z "$first" ] && [ "$again" = "conflict:63" ]
)
check_ok "conflict:<n> waits CONFLICT_MIN before the on-call sees it" conflict_first_seen
conflict_pass_setup() {
  rm -rf "$conflict_home" "$watch_oncall_count"
  mkdir -p "$conflict_state/63/ticket.lock" "$conflict_state/conflict-wait"
  printf '%s\n' "$$" >"$conflict_state/63/ticket.lock/pid"
  printf 'nonce\n' >"$conflict_state/63/ticket.lock/nonce"
  printf 'work\n' >"$conflict_state/63/log"
  touch -t 202001010000 "$conflict_state/63/log" "$conflict_state/63/ticket.lock"
  printf '%s\t%s\n' "$conflict_sha" "$(( $(date '+%s') - 3600 ))" \
    >"$conflict_state/conflict-wait/$conflict_pr"
}
conflict_pass() ( # one conflict: on-call, and no silent: for the same PR
  BELT_HOME="$conflict_home"; export BELT_HOME
  BELT_WATCH_ONLY=63; export BELT_WATCH_ONLY
  ONCALL_VERDICT="FIXED"; export ONCALL_VERDICT
  gh() { conflict_gh "$@"; }
  cmd_watch "$watch_proj" >/dev/null 2>&1 || return 1
  [ "$(grep -c '' "$watch_oncall_count" 2>/dev/null)" -eq 1 ] || return 1
  [ "$(cut -f1 "$conflict_state/watch.problems")" = "conflict:63" ] || return 1
  ! grep -q 'silent:63' "$conflict_state/watch.problems" || return 1
  grep -q 'merge-conflicted' "$conflict_state/oncall/conflict_63/prompt.txt" || return 1
  grep -q 'never rebase or force-push' "$conflict_state/oncall/conflict_63/prompt.txt"
)
conflict_pass_setup
check_ok "a conflicted PR runs one conflict:<n> on-call and never silent:<n>" conflict_pass

# Round 4: restarting a dead holder frees the issue and its PR before belt run
restart_claim_clear() ( # <live|dead>; assert whether claimed:belt is removed
  local mode=${1:-dead} proj home calls dead
  proj="$TMP/restart-proj"; home="$TMP/restart-home"; calls="$TMP/restart-calls"
  rm -rf "$proj" "$home"; rm -f "$calls"
  mkdir -p "$proj" "$home/acme__widget/63/ticket.lock"
  printf 'REPO="acme/widget"\nWORKER_CMD="true"\nREVIEWER_CMD="true"\n' >"$proj/belt.conf"
  if [ "$mode" = live ]; then dead=$$; else dead=$(watch_dead_pid); fi
  printf '%s\n' "$dead" >"$home/acme__widget/63/ticket.lock/pid"
  printf 'nonce\n' >"$home/acme__widget/63/ticket.lock/nonce"
  BELT_HOME="$home"; export BELT_HOME
  BELT_PROJECT="$proj"; export BELT_PROJECT
  gh() {
    case "$*" in
      *'dependencies/blocked_by'*) printf '[]\n' ;;
      *'issue view'*'--json body'*) printf 'body\n' ;;
      *'issue view'*'--json labels'*) printf 'claimed:belt\n' ;;
      *'pr view'*'--json labels'*) printf 'claimed:belt\n' ;;
      *'pr list'*'--head belt/63'*) printf '310\n' ;;
      *'issue edit'*|*'pr edit'*) printf '%s\n' "$*" >>"$calls" ;;
      *) return 0 ;;
    esac
  }
  ticket_run() { printf 'ticket_run\n' >>"$calls"; return 0; }
  cmd_run 63 >/dev/null 2>&1 || return 1
  if [ "$mode" = live ]; then
    [ "$(cat "$calls")" = "ticket_run" ]
    return $?
  fi
  sed -n 1p "$calls" | grep -q 'issue edit 63 .*--remove-label claimed:belt' || return 1
  sed -n 2p "$calls" | grep -q 'pr edit 310 .*--remove-label claimed:belt' || return 1
  [ "$(sed -n 3p "$calls")" = "ticket_run" ]
)
check_ok "a dead-holder restart clears claimed:belt from the issue and PR first" \
  restart_claim_clear dead
check_ok "a live-holder run never clears claimed:belt" restart_claim_clear live

# a red base is bisected detached: the watch pass never waits for 12 suite runs
bisect_home="$TMP/bisect-home"
bisect_red="abcdef0123456789abcdef0123456789abcdef01"
bisect_green="0123456789abcdef0123456789abcdef01234567"
mkdir -p "$bisect_home/acme__widget"
printf 'result=red\nsha=%s\nunknown=0\ngreen=%s\n' "$bisect_red" "$bisect_green" \
  >"$bisect_home/acme__widget/suite.state"
bisect_stub_root="$TMP/bisect-stub-root"
mkdir -p "$bisect_stub_root"
cat >"$bisect_stub_root/belt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$BISECT_STUB_OUT"
sleep 5
STUB
bisect_dispatch() ( # watch_bisect_start returns at once and dispatches once
  BELT_HOME="$bisect_home"; export BELT_HOME
  BISECT_STUB_OUT="$TMP/bisect-stub.out"; export BISECT_STUB_OUT
  LOG="$TMP/bisect-test.log"
  load_config "$watch_proj" >/dev/null || return 1
  BELT_ROOT="$bisect_stub_root"; export BELT_ROOT
  SLUG="acme/widget"
  start=$(date '+%s')
  watch_bisect_start "$bisect_red" || { printf 'bisect dispatch: first start failed\n' >&2; return 1; }
  elapsed=$(( $(date '+%s') - start ))
  [ "$elapsed" -le 3 ] || { printf 'bisect dispatch: took %ss, not detached\n' "$elapsed" >&2; return 1; }
  [ -e "$bisect_home/acme__widget/bisect.started.$bisect_red" ] \
    || { printf 'bisect dispatch: no started marker\n' >&2; return 1; }
  watch_bisect_start "$bisect_red" || { printf 'bisect dispatch: second start failed\n' >&2; return 1; }
  wait_for_file "$TMP/bisect-stub.out" 20 \
    || { printf 'bisect dispatch: stub wrote nothing\n' >&2; return 1; }
  [ "$(cat "$TMP/bisect-stub.out")" = "__bisect $(cd -P "$watch_proj" && pwd) $bisect_red" ] \
    || { printf 'bisect dispatch: wrong args [%s]\n' "$(cat "$TMP/bisect-stub.out" 2>/dev/null)" >&2; return 1; }
)
check_ok "the red-base bisect is dispatched detached, once per SHA" bisect_dispatch

bisect_worker() ( # the detached worker bisects under bisect.lock and writes the culprit
  BELT_HOME="$bisect_home"; export BELT_HOME
  SLUG="acme/widget"
  LOG="$TMP/bisect-test.log"
  suite_bisect() { printf '%s\n' "$bisect_green"; }
  suite_culprit_pr() { printf '#12 fake PR\n'; }
  watch_bisect_run "$bisect_red" || return 1
  [ ! -e "$bisect_home/acme__widget/bisect.lock" ] || return 1
  [ "$(sed -n 1p "$bisect_home/acme__widget/bisect.culprit")" = "$bisect_green" ] || return 1
  [ "$(sed -n 2p "$bisect_home/acme__widget/bisect.culprit")" = "#12 fake PR" ]
)
rm -f "$bisect_home/acme__widget/bisect.culprit"
check_ok "the detached bisect worker writes bisect.culprit under its own lock" bisect_worker

bisect_report() ( # a finished bisect is commented on the red issue exactly once
  BELT_HOME="$bisect_home"; export BELT_HOME
  SLUG="acme/widget"
  LOG="$TMP/bisect-test.log"
  printf '%s\n%s\n' "$bisect_green" "#12 fake PR" >"$bisect_home/acme__widget/bisect.culprit"
  printf '%s\n' 55 >"$bisect_home/acme__widget/suite.issue"
  comments="$TMP/bisect-comments"
  : >"$comments"
  gh() { printf '%s\n' "$*" >>"$comments"; return 0; }
  watch_bisect_report
  watch_bisect_report
  [ "$(grep -c '' "$comments")" -eq 1 ] || return 1
  grep -q "first bad commit is $bisect_green" "$comments" && grep -q '#12 fake PR' "$comments"
)
check_ok "a later pass comments a finished bisect once" bisect_report

# a started marker is not final: a dead worker is retried twice, then escalated
bisect_retry_home="$TMP/bisect-retry-home"
bisect_retry_calls="$TMP/bisect-retry-calls"
bisect_retry_creates="$TMP/bisect-retry-creates"
bisect_retry_stub_root="$TMP/bisect-retry-stub-root"
mkdir -p "$bisect_retry_stub_root" "$bisect_retry_home/acme__widget"
printf 'result=red\nsha=%s\nunknown=0\ngreen=%s\n' "$bisect_red" "$bisect_green" \
  >"$bisect_retry_home/acme__widget/suite.state"
cat >"$bisect_retry_stub_root/belt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BISECT_CALLS"
STUB
bisect_retry_cap() ( # a dead worker is re-dispatched twice, then handed to the owner
  home="$bisect_retry_home"; state="$home/acme__widget"
  calls="$bisect_retry_calls"; : >"$calls"
  creates="$bisect_retry_creates"; : >"$creates"
  rm -f "$watch_notify_file"
  BELT_HOME="$home"; export BELT_HOME
  BISECT_CALLS="$calls"; export BISECT_CALLS
  LOG="$TMP/bisect-retry.log"
  load_config "$watch_proj" >/dev/null || return 1
  BELT_ROOT="$bisect_retry_stub_root"; export BELT_ROOT
  SLUG="acme/widget"
  gh() {
    case "$*" in
      *'issue create'*) printf '%s\n' "$*" >>"$creates"; printf 'https://github.com/acme/widget/issues/91\n' ;;
      *'issue list'*) printf '[]\n' ;;
      *) return 0 ;;
    esac
  }
  wait_worker_dead() {
    local i=0 pid
    pid=$(cat "$state/bisect.worker.$bisect_red" 2>/dev/null) || return 1
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
    ! kill -0 "$pid" 2>/dev/null
  }
  watch_bisect_start "$bisect_red" || return 1
  wait_worker_dead || return 1
  [ "$(grep -c '' "$calls")" -eq 1 ] || return 1
  watch_bisect_start "$bisect_red" || return 1
  wait_worker_dead || return 1
  [ "$(grep -c '' "$calls")" -eq 2 ] || return 1
  watch_bisect_start "$bisect_red" || return 1
  wait_worker_dead || return 1
  [ "$(grep -c '' "$calls")" -eq 3 ] || return 1
  # a third dead worker is not retried again: it becomes an owner problem
  watch_bisect_start "$bisect_red" || return 1
  [ "$(grep -c '' "$calls")" -eq 3 ] || return 1
  [ "$(grep -c '' "$creates")" -eq 1 ] || return 1
  grep -q -- '--label needs-owner' "$creates" || return 1
  grep -q 'needs an owner' "$creates" || return 1
  [ "$(grep -c '' "$watch_notify_file" 2>/dev/null || echo 0)" -eq 1 ] || return 1
  # a later pass must not ping the owner twice
  watch_bisect_start "$bisect_red" || return 1
  [ "$(grep -c '' "$watch_notify_file" 2>/dev/null || echo 0)" -eq 1 ] || return 1
  [ "$(grep -c '' "$calls")" -eq 3 ]
)
check_ok "a dead bisect is re-dispatched twice, then handed to the owner" bisect_retry_cap

# ------------------------------------------------------------ belt drill ---

drill_proj="$TMP/drill-proj"
drill_home="$TMP/drill-home"
drill_prompt_seen="$TMP/drill-prompt-seen"
drill_real_notify="$TMP/drill-real-notify"
drill_creates="$TMP/drill-creates"
drill_closed="$TMP/drill-closed"
drill_comments="$TMP/drill-comments"
drill_oncall="$TMP/drill-oncall.sh"
drill_notify="$TMP/drill-notify.sh"
mkdir -p "$drill_proj"
cat >"$drill_oncall" <<'ONCALL'
#!/usr/bin/env bash
grep -q 'This is a drill: change nothing, reply ONCALL: OWNER drill reached the owner' \
  "$BELT_PROMPT_FILE" && printf 'note-seen\n' >>"$DRILL_PROMPT_SEEN"
if [ "${DRILL_NO_VERDICT:-0}" = "1" ]; then
  printf 'drill checked, nothing to report\n'
else
  printf 'drill\nONCALL: OWNER drill reached the owner\n'
fi
ONCALL
cat >"$drill_notify" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s\n' "$BELT_MESSAGE" >>"$DRILL_REAL_NOTIFY"
NOTIFY
cat >"$drill_proj/belt.conf" <<EOF
REPO="acme/widget"
ONCALL_CMD="DRILL_PROMPT_SEEN='$drill_prompt_seen' bash '$drill_oncall'"
OWNER_NOTIFY_CMD="DRILL_REAL_NOTIFY='$drill_real_notify' bash '$drill_notify'"
EOF

drill_gh() { # a tiny stateful GitHub: real gh shapes, real search-index lag
  # Real gh `issue list` reads GitHub's search index, so an issue created a
  # second ago is often missing from it. The fake models that: an issue created
  # during this drill is invisible to `issue list` until a later call reloads
  # nothing. `issue view` reads the issue itself and always sees it.
  local allargs=("$@") cmd=$1 sub=$2 a json="" q="" label="" num title body labels
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=$2; shift 2 ;;
      -q|--jq) q=$2; shift 2 ;;
      --label) label=$2; shift 2 ;;
      -R|--limit) shift 2 ;;
      *) shift ;;
    esac
  done
  case "$cmd $sub" in
    'issue list')
      drill_gh_json "$label" \
        | if [ -n "$q" ]; then jq -r "$q"; else cat; fi
      ;;
    'issue view')
      set -- "${allargs[@]}"; shift 2
      num=$1
      case "$json" in
        *state*) awk -F'\t' -v n="$num" '$1 == n { print $2 }' "$DRILL_MOCK" ;;
        *) awk -F'\t' -v n="$num" '$1 == n { print $5 }' "$DRILL_MOCK" ;;
      esac
      ;;
    'issue create')
      set -- "${allargs[@]}"; shift 2
      title=""; body=""; labels=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --title) title=$2; shift 2 ;;
          --body) body=$2; shift 2 ;;
          --label) labels="$labels,$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      num=$(drill_gh_alloc)
      printf '%s\tOPEN\t%s\t%s\t%s\n' "$num" "${labels#,}" "$title" "$body" >>"$DRILL_MOCK"
      # The real drill issue existed ~50s before its pass, so the pass sees it
      # (as in the real log). A needs-owner issue is created one second before
      # the after-list, so real gh's search index does not show it yet.
      case "$labels" in *needs-owner*) printf '%s\n' "$num" >>"$DRILL_UNINDEXED" ;; esac
      printf '%s\n' "${allargs[*]}" >>"$DRILL_CREATES"
      [ -n "${DRILL_REAL_AFTER:-}" ] && case "$labels" in
        *needs-owner*)
          # another belt process opens a real needs-owner issue in the window
          printf '79\tOPEN\tneeds-owner\t#61 needs an owner: real\tNeeded for #61\n' >>"$DRILL_MOCK"
          ;;
      esac
      printf 'https://github.com/acme/widget/issues/%s\n' "$num"
      ;;
    'issue close')
      set -- "${allargs[@]}"; shift 2
      num=$1
      if [ -n "${DRILL_CLOSE_FAILS:-}" ]; then return 1; fi
      awk -F'\t' -v n="$num" 'BEGIN{OFS="\t"} $1 == n { $2 = "CLOSED" } { print }' "$DRILL_MOCK" \
        >"$DRILL_MOCK.new" && mv "$DRILL_MOCK.new" "$DRILL_MOCK"
      printf '%s\n' "${allargs[*]}" >>"$DRILL_CLOSED"
      ;;
    'issue comment') printf '%s\n' "${allargs[*]}" >>"$DRILL_COMMENTS" ;;
    *) return 0 ;;
  esac
}

drill_gh_alloc() { # the next issue number: 77, then 78, ...
  local n
  n=$(cat "$DRILL_NEXT" 2>/dev/null) || n=77
  printf '%s\n' $((n + 1)) >"$DRILL_NEXT"
  printf '%s\n' "$n"
}

drill_gh_json() { # <label>; open issues as gh --json would return them
  local lab=${1:-}
  awk -F'\t' -v lab="$lab" -v unindexed="$DRILL_UNINDEXED" '
    BEGIN { while ((getline n < unindexed) > 0) lag[n] = 1; printf "[" }
    $2 == "OPEN" && !($1 in lag) && (lab == "" || index("," $3 ",", "," lab ",")) {
      printf "%s{\"number\":%s,\"title\":\"%s\",\"body\":\"%s\",\"labels\":[", (c++ ? "," : ""), $1, $4, $5
      m = split($3, L, ","); for (i = 1; i <= m; i++) printf "%s{\"name\":\"%s\"}", (i > 1 ? "," : ""), L[i]
      printf "]}"
    }
    END { printf "]\n" }
  ' "$DRILL_MOCK"
}

drill_case() ( # <no-verdict>; one belt drill run against the fake gh and slots
  BELT_HOME="$drill_home"; export BELT_HOME
  DRILL_PROMPT_SEEN="$drill_prompt_seen"; export DRILL_PROMPT_SEEN
  DRILL_REAL_NOTIFY="$drill_real_notify"; export DRILL_REAL_NOTIFY
  DRILL_CREATES="$drill_creates"; export DRILL_CREATES
  DRILL_CLOSED="$drill_closed"; export DRILL_CLOSED
  DRILL_COMMENTS="$drill_comments"; export DRILL_COMMENTS
  DRILL_MOCK="$TMP/drill-mock"; export DRILL_MOCK
  DRILL_UNINDEXED="$TMP/drill-unindexed"; export DRILL_UNINDEXED
  DRILL_NEXT="$TMP/drill-next"; export DRILL_NEXT
  DRILL_NO_VERDICT="$1"; export DRILL_NO_VERDICT
  : >"$DRILL_MOCK"; : >"$DRILL_UNINDEXED"; rm -f "$DRILL_NEXT"
  # issues that were already open before the drill (old project state)
  [ -n "${DRILL_PRESET:-}" ] && [ -f "$DRILL_PRESET" ] && cat "$DRILL_PRESET" >"$DRILL_MOCK"
  LOG="$TMP/drill-test.log"
  gh() { drill_gh "$@"; }
  cmd_drill "$drill_proj"
)

drill_reset() { # a clean drill home and call log
  rm -rf "$drill_home"
  rm -f "$drill_prompt_seen" "$drill_real_notify" "$drill_creates" "$drill_closed" "$drill_comments"
}

drill_pass() { # a real on-call answer plus exactly one real notify
  drill_reset
  out=$(drill_case 0 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -q '^PASS:' || return 1
  [ "$(grep -c '' "$drill_prompt_seen" 2>/dev/null)" -eq 1 ] || return 1
  [ "$(grep -c '' "$drill_real_notify" 2>/dev/null)" -eq 1 ] || return 1
  grep -q 'drill reached the owner' "$drill_real_notify" || return 1
  [ "$(grep -c '' "$drill_home/acme__widget/drill/notify.log" 2>/dev/null)" -eq 1 ] || return 1
  grep -q 'belt drill .* (safe to close)' "$drill_creates" || return 1
  grep -q -- '--label stuck --label belt-drill' "$drill_creates" || return 1
  grep -q 'it proves the repair chain end to end' "$drill_creates" || return 1
  grep -q 'issue close 77' "$drill_closed" || return 1
  ! grep -q 'stuck:77' "$drill_home/acme__widget/watch.seen" 2>/dev/null
}
check_ok "belt drill PASSes with one on-call verdict and one owner notify" drill_pass

drill_owner_closed() { # its own needs-owner issue is closed even though the
  # search-indexed issue list never showed it (the real GitHub failure)
  drill_reset
  out=$(drill_case 0 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -q '^PASS:' || return 1
  grep -q 'issue close 78' "$drill_closed" || return 1
  grep -q 'issue comment 78' "$drill_comments" || return 1
  # and the fake really did keep #78 out of every needs-owner list
  grep -qx '78' "$TMP/drill-unindexed" || return 1
}
check_ok "a drill closes its own needs-owner issue while the issue list still lags" \
  drill_owner_closed

drill_owner_left_open() { # a close that did not stick is a FAIL, not a PASS
  drill_reset
  DRILL_CLOSE_FAILS=1; export DRILL_CLOSE_FAILS
  out=$(drill_case 0 2>&1); rc=$?
  unset DRILL_CLOSE_FAILS
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$out" | grep -q '^FAIL: its own needs-owner issue(s) #78 are still open' || return 1
  ! printf '%s\n' "$out" | grep -q '^PASS:' || return 1
}
check_ok "a drill FAILs when its own needs-owner issue is still open after cleanup" \
  drill_owner_left_open

drill_fail() { # no verdict: FAIL, and the issue is closed and the key removed anyway
  drill_reset
  out=$(drill_case 1 2>&1); rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$out" | grep -q '^FAIL: the on-call ended without a verdict line' || return 1
  grep -q 'issue close 77' "$drill_closed" || return 1
  ! grep -q 'stuck:77' "$drill_home/acme__widget/watch.seen" 2>/dev/null
}
check_ok "belt drill FAILs without a verdict but still closes the drill issue" drill_fail

drill_restores_state() ( # a drill gives back watch.seen and the owner issue it opened
  home="$drill_home"
  drill_reset
  mkdir -p "$home/acme__widget"
  printf 'stuck:61\nneeds-lead:62\nsilent:63\n' >"$home/acme__widget/watch.seen"
  printf 'owner:#41 needs an owner: something else\n' >"$home/acme__widget/ping.seen"
  out=$(drill_case 0 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -q '^PASS:' || return 1
  # other issues' keys survive, the drill's key does not
  [ "$(grep -c '' "$home/acme__widget/watch.seen" 2>/dev/null)" -eq 3 ] || return 1
  grep -qx 'stuck:61' "$home/acme__widget/watch.seen" || return 1
  grep -qx 'needs-lead:62' "$home/acme__widget/watch.seen" || return 1
  grep -qx 'silent:63' "$home/acme__widget/watch.seen" || return 1
  ! grep -q 'stuck:77' "$home/acme__widget/watch.seen" 2>/dev/null || return 1
  # the needs-owner issue the OWNER verdict opened is closed again
  grep -q 'issue close 78' "$drill_closed" || return 1
  grep -q 'issue close 77' "$drill_closed" || return 1
  # no leftover drill state: neither its on-call dir, attempts nor owner ping
  [ ! -e "$home/acme__widget/oncall/stuck_77" ] || return 1
  [ ! -e "$home/acme__widget/oncall-attempts/77" ] || return 1
  [ -f "$home/acme__widget/ping.seen" ] || return 1
  [ "$(grep -c '' "$home/acme__widget/ping.seen")" -eq 1 ] || return 1
  grep -qx 'owner:#41 needs an owner: something else' "$home/acme__widget/ping.seen" || return 1
  # no leftover bookkeeping file in the drill folder
  ! ls "$home/acme__widget/drill" | grep -q 'owners\.' || return 1
)
check_ok "a drill restores watch.seen and closes the needs-owner issue it opened" \
  drill_restores_state

drill_spares_real_owner() ( # a real needs-owner issue in the window is left open
  home="$drill_home"
  drill_reset
  preset="$TMP/drill-preset"
  printf '60\tOPEN\tneeds-owner\told owner issue\tNeeded for issue #51\n' >"$preset"
  DRILL_PRESET="$preset"; export DRILL_PRESET
  DRILL_REAL_AFTER=1; export DRILL_REAL_AFTER
  out=$(drill_case 0 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
  printf '%s\n' "$out" | grep -q '^PASS:' || return 1
  # its own owner issue (#78) goes; the old #60 and the parallel #79 stay
  grep -q 'issue close 78' "$drill_closed" || return 1
  ! grep -q 'issue close 60' "$drill_closed" || return 1
  ! grep -q 'issue close 79' "$drill_closed" || return 1
  ! grep -q 'issue comment 79' "$drill_comments" || return 1
)
check_ok "a drill leaves a real needs-owner issue opened in its window alone" \
  drill_spares_real_owner

drill_lock_busy() ( # a live watch.lock makes the drill fail clearly, not silently
  home="$drill_home"
  rm -rf "$home"
  rm -f "$drill_prompt_seen" "$drill_real_notify" "$drill_creates" "$drill_closed" "$drill_comments"
  proj="$TMP/drill-lock-proj"
  mkdir -p "$proj"
  cat >"$proj/belt.conf" <<EOF
REPO="acme/widget"
ONCALL_TIMEOUT_MIN="1"
ONCALL_CMD="DRILL_PROMPT_SEEN='$drill_prompt_seen' bash '$drill_oncall'"
OWNER_NOTIFY_CMD="DRILL_REAL_NOTIFY='$drill_real_notify' bash '$drill_notify'"
EOF
  mkdir -p "$home/acme__widget/watch.lock"
  printf '%s\n' "$$" >"$home/acme__widget/watch.lock/pid"
  printf 'nonce\n' >"$home/acme__widget/watch.lock/nonce"
  BELT_HOME="$home"; export BELT_HOME
  DRILL_PROMPT_SEEN="$drill_prompt_seen"; export DRILL_PROMPT_SEEN
  DRILL_REAL_NOTIFY="$drill_real_notify"; export DRILL_REAL_NOTIFY
  DRILL_CREATES="$drill_creates"; export DRILL_CREATES
  DRILL_CLOSED="$drill_closed"; export DRILL_CLOSED
  DRILL_COMMENTS="$drill_comments"; export DRILL_COMMENTS
  BELT_TIME_SCALE=60; export BELT_TIME_SCALE
  LOG="$TMP/drill-test.log"
  gh() { drill_gh "$@"; }
  out=$(cmd_drill "$proj" 2>&1); rc=$?
  [ "$rc" -ne 0 ] || return 1
  printf '%s\n' "$out" | grep -q '^FAIL: watch.lock busy, the drill did not run' || return 1
  ! printf '%s\n' "$out" | grep -q 'without a verdict' || return 1
  # it never opened a drill issue it could not run
  ! [ -s "$drill_creates" ] || return 1
  ! [ -s "$drill_prompt_seen" ] || return 1
)
check_ok "a drill blocked by a live watch.lock says the drill did not run" drill_lock_busy

# ------------------------------------------------------- watch baseline ---

base_home="$TMP/base-home"
base_issues="$TMP/base-issues"

base_gh() { # real gh shapes: --json prints JSON, -q runs jq on that JSON
  local allargs=("$@") cmd=$1 sub=$2 json="" q="" label="" num json_out
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=$2; shift 2 ;;
      -q|--jq) q=$2; shift 2 ;;
      --label) label=$2; shift 2 ;;
      -R|--limit|--head|--state) shift 2 ;;
      *) shift ;;
    esac
  done
  case "$cmd $sub" in
    'issue list')
      json_out=$(awk -F'\t' -v lab="$label" '
        $2 == "OPEN" && (lab == "" || index("," $3 ",", "," lab ",")) {
          printf "%s{\"number\":%s,\"title\":\"%s\",\"body\":\"%s\",\"labels\":[", (c++ ? "," : ""), $1, $4, $5
          m = split($3, L, ","); for (i = 1; i <= m; i++) printf "%s{\"name\":\"%s\"}", (i > 1 ? "," : ""), L[i]
          printf "]}"
        }
      ' "$BASE_ISSUES")
      json_out="[$json_out]"
      if [ -n "$q" ]; then printf '%s' "$json_out" | jq -r "$q"; else printf '%s\n' "$json_out"; fi
      ;;
    'issue view')
      set -- "${allargs[@]}"; shift 2
      num=$1
      awk -F'\t' -v n="$num" '$1 == n { print $5 }' "$BASE_ISSUES"
      ;;
    'issue create')
      printf '%s\n' "${allargs[*]}" >>"${BASE_CREATES:-/dev/null}"
      printf 'https://github.com/acme/widget/issues/99\n'
      ;;
    'pr list') printf '[]\n' ;;
    *) return 0 ;;
  esac
}

base_issues_set() { # <num>:<labels> ...; rewrite the fake repo's open issues
  : >"$base_issues" 2>/dev/null || return 1
  local e num labs
  for e in "$@"; do
    num=${e%%:*}
    labs=${e#*:}
    printf '%s\tOPEN\t%s\ttitle %s\tNeeded for issue #%s\n' "$num" "$labs" "$num" "$num" >>"$base_issues"
  done
}

base_baseline() ( # belt watch --baseline for the shared watch project
  BELT_HOME="$base_home"; export BELT_HOME
  BASE_ISSUES="$base_issues"; export BASE_ISSUES
  gh() { base_gh "$@"; }
  cmd_watch --baseline "$watch_proj"
)

base_pass() ( # one watch pass with the same fake gh
  BELT_HOME="$base_home"; export BELT_HOME
  BASE_ISSUES="$base_issues"; export BASE_ISSUES
  ONCALL_COUNT="$watch_oncall_count"; export ONCALL_COUNT
  ONCALL_PWD="$watch_oncall_pwd"; export ONCALL_PWD
  gh() { base_gh "$@"; }
  cmd_watch "$watch_proj" >/dev/null 2>&1
)

baseline_written() (
  rm -rf "$base_home"
  base_issues_set 61:stuck 62:needs-owner 63:'stuck,needs-owner' 64:ready-for-agent
  base_baseline >/dev/null || return 1
  [ "$(cat "$base_home/acme__widget/watch.baseline")" = "$(printf '61\n62\n63')" ]
)
check_ok "belt watch --baseline records the open stuck and needs-owner numbers" \
  baseline_written

baseline_old_stuck_quiet() ( # an old stuck issue: no on-call, no restart, no key
  rm -rf "$base_home" "$watch_oncall_count" "$watch_oncall_pwd"
  base_issues_set 61:stuck
  base_baseline >/dev/null || return 1
  base_pass || return 1
  [ ! -s "$watch_oncall_count" ] || return 1
  ! grep -q 'stuck:61' "$base_home/acme__widget/watch.problems" 2>/dev/null
)
check_ok "an old stuck issue in the baseline never reaches the on-call" \
  baseline_old_stuck_quiet

baseline_new_stuck_runs() ( # an issue opened later is handled normally
  rm -rf "$base_home" "$watch_oncall_count" "$watch_oncall_pwd"
  base_issues_set 61:stuck
  base_baseline >/dev/null || return 1
  base_issues_set 61:stuck 64:stuck
  base_pass || return 1
  [ "$(grep -c '' "$watch_oncall_count")" -eq 1 ] || return 1
  grep -q 'stuck:64' "$base_home/acme__widget/watch.problems"
)
check_ok "a stuck issue opened after the baseline is handled normally" \
  baseline_new_stuck_runs

baseline_owner_ping() ( # a baselined needs-owner issue is never pinged, a new one is
  rm -rf "$base_home" "$watch_oncall_count" "$watch_notify_file"
  base_issues_set 61:stuck 62:needs-owner
  base_baseline >/dev/null || return 1
  base_issues_set 61:stuck 62:needs-owner 65:needs-owner
  base_pass || return 1
  [ "$(grep -c '' "$watch_notify_file")" -eq 1 ] || return 1
  grep -q 'title 65' "$watch_notify_file" || return 1
  ! grep -q 'title 62' "$watch_notify_file"
)
check_ok "a baselined needs-owner issue gets no owner ping, a new one does" \
  baseline_owner_ping

baseline_removed_rearms() ( # removing the number from the file re-arms the issue
  rm -rf "$base_home" "$watch_oncall_count" "$watch_oncall_pwd"
  base_issues_set 61:stuck
  base_baseline >/dev/null || return 1
  : >"$base_home/acme__widget/watch.baseline"
  base_pass || return 1
  [ "$(grep -c '' "$watch_oncall_count")" -eq 1 ]
)
check_ok "removing an issue number from the baseline re-arms it" baseline_removed_rearms

baseline_drops_pr_keys() ( # a baselined issue's PR keys go too, other keys stay
  rm -rf "$base_home"
  mkdir -p "$base_home/acme__widget"
  printf '61\n62\n' >"$base_home/acme__widget/watch.baseline"
  printf 'stuck:61\t61\tstuck\nlead:62\t62\tlead\nconflict:62\t62\tconflict\nsilent:63\t63\tsilent\nred:abc\t0\tred\n' \
    >"$TMP/base-problems"
  BELT_HOME="$base_home"; export BELT_HOME
  SLUG="acme/widget"
  watch_drop_baselined "$TMP/base-problems"
  [ "$(cut -f1 "$TMP/base-problems" | tr '\n' ' ')" = "silent:63 red:abc " ]
)
check_ok "the baseline also silences stuck:, its PR keys and leaves red: alone" \
  baseline_drops_pr_keys

# the app builder and launchd are stubbed on PATH: the tests never touch real
# osacompile/codesign/launchctl/PlistBuddy and write only under $TMP with HOME there
watch_stub_bin="$TMP/watch-tool-bin"
mkdir -p "$watch_stub_bin"
cat >"$watch_stub_bin/osacompile" <<'STUB'
#!/bin/bash
out=""; src=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) src=$1; shift ;;
  esac
done
[ -n "$out" ] || exit 1
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources" || exit 1
printf '#!/bin/bash\nexit 0\n' >"$out/Contents/MacOS/applet"
chmod 755 "$out/Contents/MacOS/applet"
printf '<plist version="1.0"><dict/></plist>\n' >"$out/Contents/Info.plist"
[ -n "${STUB_LOG:-}" ] && printf 'osacompile %s\n' "$src" >>"$STUB_LOG"
[ -n "${STUB_APPLESCRIPT:-}" ] && cp "$src" "$STUB_APPLESCRIPT"
exit 0
STUB
cat >"$watch_stub_bin/PlistBuddy" <<'STUB'
#!/bin/bash
[ -n "${STUB_LOG:-}" ] && printf 'PlistBuddy %s\n' "$*" >>"$STUB_LOG"
exit 0
STUB
cat >"$watch_stub_bin/codesign" <<'STUB'
#!/bin/bash
app=""
for a in "$@"; do app=$a; done
rw=no
[ -f "$app/Contents/Resources/run-watch.sh" ] && rw=yes
[ -n "${STUB_LOG:-}" ] && printf 'codesign %s run-watch=%s\n' "$*" "$rw" >>"$STUB_LOG"
exit 0
STUB
cat >"$watch_stub_bin/launchctl" <<'STUB'
#!/bin/bash
[ -n "${STUB_LOG:-}" ] && printf 'launchctl %s\n' "$*" >>"$STUB_LOG"
case "$*" in
  *kickstart*)
    if [ "${STUB_KICKSTART_PROOF:-1}" = "1" ] && [ -n "${STUB_WATCH_LOG:-}" ]; then
      mkdir -p "$(dirname "$STUB_WATCH_LOG")" 2>/dev/null || true
      printf '[stub] watch: config loaded\n' >>"$STUB_WATCH_LOG" 2>/dev/null || true
    fi
    ;;
esac
exit 0
STUB
cat >"$watch_stub_bin/osascript" <<'STUB'
#!/bin/bash
[ -n "${STUB_NOTIFY:-}" ] && printf '%s\n' "$*" >>"$STUB_NOTIFY"
exit 0
STUB
chmod 755 "$watch_stub_bin"/*
PATH="$watch_stub_bin:$PATH"; export PATH
STUB_LOG="$TMP/watch-tool.log"; export STUB_LOG
STUB_APPLESCRIPT="$TMP/watch-applescript.txt"; export STUB_APPLESCRIPT
STUB_WATCH_LOG="$BELT_HOME/acme__widget/watch.log"; export STUB_WATCH_LOG
watch_app="$HOME/.belt/bin/Belt Watch.app"

watch_install_proj="$TMP/watch-install-proj"
mkdir -p "$watch_install_proj"
printf 'REPO="acme/widget"\n' >"$watch_install_proj/belt.conf"
BELT_LAUNCH_AGENTS="$TMP/launchagents"
BELT_NO_LAUNCHCTL=1
watch_install_gh() { # offline gh: no open issues, so the baseline is empty
  case "$*" in
    *'issue list'*) case "$*" in *' -q '*) return 0 ;; *) printf '[]\n' ;; esac ;;
    *) return 0 ;;
  esac
}
watch_install() { gh() { watch_install_gh "$@"; }; BELT_LAUNCH_AGENTS="$TMP/launchagents" BELT_NO_LAUNCHCTL=1 cmd_install --watch "$watch_install_proj" >/dev/null 2>&1; }
watch_uninstall() { BELT_LAUNCH_AGENTS="$TMP/launchagents" BELT_NO_LAUNCHCTL=1 cmd_unwatch "$watch_install_proj" >/dev/null 2>&1; }
watch_install_loaded() ( # launchd stubs on: no real launchctl ever runs
  gh() { watch_install_gh "$@"; }
  export BELT_LAUNCH_AGENTS="$TMP/launchagents" BELT_NO_LAUNCHCTL=0 BELT_NO_SLEEP=1 STUB_KICKSTART_PROOF=1
  cmd_install --watch "$watch_install_proj" 2>&1
)
watch_install_loaded_no_proof() (
  gh() { watch_install_gh "$@"; }
  export BELT_LAUNCH_AGENTS="$TMP/launchagents" BELT_NO_LAUNCHCTL=0 BELT_NO_SLEEP=1 STUB_KICKSTART_PROOF=0
  cmd_install --watch "$watch_install_proj" 2>&1
)
: >"$STUB_LOG"
check_ok "belt install --watch writes the launchd plist" watch_install
check_ok "the plist is named com.belt.watch.<owner>.<repo>.plist" \
  test -f "$TMP/launchagents/com.belt.watch.acme.widget.plist"
check_ok "the plist runs belt watch every 10 minutes" \
  grep -q '<key>StartInterval</key><integer>600</integer>' "$TMP/launchagents/com.belt.watch.acme.widget.plist"
check_ok "the app is created once at ~/.belt/bin/Belt Watch.app" \
  test -d "$watch_app"
check_ok "the applet is what launchd runs, not /bin/bash" \
  grep -q "<string>$watch_app/Contents/MacOS/applet</string>" "$TMP/launchagents/com.belt.watch.acme.widget.plist"
plist_has_env() { # <key> <value>
  grep -A1 "<key>$1</key>" "$TMP/launchagents/com.belt.watch.acme.widget.plist" | grep -Fq "<string>$2</string>"
}
check_ok "the plist passes BELT_WATCH_BELT to the applet" \
  plist_has_env BELT_WATCH_BELT "$ROOT/belt"
check_ok "the plist passes BELT_WATCH_PROJECT to the applet" \
  plist_has_env BELT_WATCH_PROJECT "$(cd -P "$watch_install_proj" && pwd)"
check_ok "the plist passes BELT_WATCH_OUT and BELT_WATCH_ERR to the applet" \
  plist_has_env BELT_WATCH_OUT "$BELT_HOME/acme__widget/watch.out"
check_ok "the plist keeps the PATH for the applet" \
  plist_has_env PATH "$PATH"
check_ok "run-watch.sh execs belt watch and appends stdout and stderr separately" \
  grep -q 'exec /bin/bash "\$BELT_WATCH_BELT" watch "\$BELT_WATCH_PROJECT" >>"\$BELT_WATCH_OUT" 2>>"\$BELT_WATCH_ERR"' \
    "$watch_app/Contents/Resources/run-watch.sh"
check_no "run-watch.sh names no project, so one app serves every project" \
  grep -q "$watch_install_proj" "$watch_app/Contents/Resources/run-watch.sh"
check_ok "the applet only runs run-watch.sh relative to itself" \
  grep -q 'POSIX path of (path to me)' "$STUB_APPLESCRIPT"
check_ok "the applet is marked LSUIElement through PlistBuddy" \
  grep -q 'PlistBuddy .*Add :LSUIElement bool true' "$STUB_LOG"
check_ok "the app is signed after run-watch.sh is written" \
  bash -c 'os=$(grep -n "^osacompile " "$1" | cut -d: -f1); cs=$(grep -n "^codesign .*run-watch=yes" "$1" | cut -d: -f1); [ -n "$os" ] && [ -n "$cs" ] && [ "$cs" -gt "$os" ]' _ "$STUB_LOG"
check_ok "belt install --watch writes the baseline when none exists" \
  test -f "$BELT_HOME/acme__widget/watch.baseline"
install_keeps_baseline() { # an existing baseline is never overwritten
  printf '61\n62\n' >"$BELT_HOME/acme__widget/watch.baseline"
  watch_install || return 1
  [ "$(cat "$BELT_HOME/acme__widget/watch.baseline")" = "$(printf '61\n62')" ]
}
check_ok "belt install --watch keeps an existing baseline" install_keeps_baseline
check_eq "re-installing never rebuilds the app (the macOS grant is kept)" 1 \
  "$(grep -c '^osacompile ' "$STUB_LOG")"
install_proves_pass() { # kickstart makes one pass write the proof line
  rm -f "$STUB_WATCH_LOG"
  watch_install_loaded >"$TMP/watch-install.out" || return 1
  grep -q '^PASS: first automatic run read its config$' "$TMP/watch-install.out" || return 1
  grep -q 'launchctl unload' "$STUB_LOG" && grep -q 'launchctl load' "$STUB_LOG"
}
check_ok "install --watch proves the first automatic pass read its config" install_proves_pass
install_proves_fail() { # a pass that never logs the proof line fails the install
  rm -f "$STUB_WATCH_LOG"
  if watch_install_loaded_no_proof >"$TMP/watch-install.out"; then return 1; fi
  grep -q '^FAIL: first automatic run could not read its config; see .*watch.err$' "$TMP/watch-install.out"
}
check_ok "install --watch exits nonzero and names watch.err when the first pass cannot read its config" \
  install_proves_fail
check_ok "belt unwatch removes the plist" watch_uninstall
check_no "the watch plist is gone after unwatch" test -f "$TMP/launchagents/com.belt.watch.acme.widget.plist"

# a pass that cannot read belt.conf must alert the owner itself and fail, hourly
watch_bad_proj="$TMP/watch-bad-proj"
mkdir -p "$watch_bad_proj"
printf '. "%s/not-here"\n' "$TMP" >"$watch_bad_proj/belt.conf"
watch_bad_home="$TMP/watch-bad-home"
watch_bad_notify="$TMP/watch-bad-notify.txt"
: >"$watch_bad_notify"
watch_bad_exit() ( # exit status of one pass whose config cannot be sourced
  export BELT_HOME="$watch_bad_home" STUB_NOTIFY="$watch_bad_notify"
  cmd_watch "$watch_bad_proj" >/dev/null 2>&1
  printf '%s' "$?"
)
check_eq "a watch pass that cannot read belt.conf exits nonzero" 1 \
  "$(rm -rf "$watch_bad_home"; watch_bad_exit)"
check_eq "it alerts the owner through osascript directly" 1 \
  "$(grep -c 'display notification' "$watch_bad_notify" 2>/dev/null || echo 0)"
check_eq "its hourly marker sits in the state dir derived from the project path" 1 \
  "$(find "$watch_bad_home/watch-config" -name config-alert.stamp 2>/dev/null | grep -c .)"
check_eq "a second failing pass within the hour does not alert again" 1 \
  "$(watch_bad_exit >/dev/null; grep -c 'display notification' "$watch_bad_notify")"

# ------------------------------------------------------------- full suite ---

suite_remote="$TMP/suite-remote.git"
suite_proj="$TMP/suite-proj"
git init -q --bare "$suite_remote"
git clone -q "$suite_remote" "$suite_proj"
git -C "$suite_proj" config user.email belt@example.com
git -C "$suite_proj" config user.name belt
printf 'base\n' >"$suite_proj/base.txt"
git -C "$suite_proj" add base.txt
git -C "$suite_proj" commit -qm base
git -C "$suite_proj" branch -M main
git -C "$suite_proj" push -q -u origin main
printf 'REPO="acme/widget"\nFULL_SUITE_CMD="false"\n' >"$suite_proj/belt.conf"

suite_pass() { # run one foreground suite pass with a fake gh
  BELT_HOME="$TMP/suite-home"; export BELT_HOME
  WATCH_CREATES="$TMP/suite-creates"; export WATCH_CREATES
  gh() {
    case "$*" in
      *'issue create'*)
        printf '%s\n' "$*" >>"$WATCH_CREATES"
        printf 'https://github.com/acme/widget/issues/88\n'
        ;;
      *) return 0 ;;
    esac
  }
  LOG="$TMP/suite-test.log"
  load_config "$suite_proj" >/dev/null || return 1
  SLUG="acme/widget"
  suite_run
}
suite_gate() { # --must-pass in a subshell with this project's config
  BELT_HOME="$TMP/suite-home"; export BELT_HOME
  load_config "$suite_proj" >/dev/null || return 1
  SLUG="acme/widget"
  suite_must_pass
}
rm -f "$TMP/suite-creates"
check_eq "a red suite pass exits 0" 0 "$(suite_pass >/dev/null 2>&1; printf '%s' "$?")"
check_eq "a second red suite pass exits 0" 0 "$(suite_pass >/dev/null 2>&1; printf '%s' "$?")"
check_eq "a red base opens one issue per SHA" 1 "$(grep -c '^issue create' "$TMP/suite-creates")"
check_eq "the suite state records red" "red" \
  "$(sed -n 's/^result=//p' "$TMP/suite-home/acme__widget/suite.state")"

# exit 124 is infra: UNKNOWN, no red issue and no bisect
printf 'next\n' >"$suite_proj/next.txt"
git -C "$suite_proj" add next.txt
git -C "$suite_proj" commit -qm next
git -C "$suite_proj" push -q origin main
printf 'REPO="acme/widget"\nFULL_SUITE_CMD="exit 124"\n' >"$suite_proj/belt.conf"
suite_pass >/dev/null 2>&1
check_eq "a suite timeout records UNKNOWN" "unknown" \
  "$(sed -n 's/^result=//p' "$TMP/suite-home/acme__widget/suite.state")"
check_eq "a suite timeout opens no red issue" 1 "$(grep -c '^issue create' "$TMP/suite-creates")"
check_no "a suite timeout leaves the release gate closed" suite_gate

# green is recorded for the SHA the worktree actually tested
printf 'green\n' >"$suite_proj/green.txt"
git -C "$suite_proj" add green.txt
git -C "$suite_proj" commit -qm green
git -C "$suite_proj" push -q origin main
green_sha=$(git -C "$suite_proj" rev-parse origin/main)
printf 'REPO="acme/widget"\nFULL_SUITE_CMD="true"\n' >"$suite_proj/belt.conf"
suite_pass >/dev/null 2>&1
check_eq "a green suite records the tested SHA" "green:$green_sha" \
  "$(printf '%s:%s' "$(sed -n 's/^result=//p' "$TMP/suite-home/acme__widget/suite.state")" "$(sed -n 's/^sha=//p' "$TMP/suite-home/acme__widget/suite.state")")"
check_ok "--must-pass is green at the tested base SHA" suite_gate

# ---------------------------------------------------------- slot guard ---

guard_realhome=$(guard_real_home)
check_eq "guard reads the real home from passwd" "$(eval echo "~$(id -un)")" "$guard_realhome"

# the profile prints physical paths, so the expected paths must be physical too
# ($TMP may sit behind /var -> /private/var)
guard_tmp=$(cd -P "$TMP" && pwd)
guard_repo="$guard_tmp/guard-repo"
mkdir -p "$guard_repo/ticket"
git -C "$guard_repo" init -q
git -C "$guard_repo" config user.email belt@example.com
git -C "$guard_repo" config user.name belt
guard_common=$(cd -P "$guard_repo/.git" && pwd)
guard_tools="$guard_tmp/guard-tools"
guard_extra="$guard_tmp/guard-extra"
mkdir -p "$guard_tools" "$guard_extra"

guard_profile_for() ( # <role>; one profile for the guard repo
  BELT_HOME="$guard_tmp/guard-belt-home"
  PROJECT="$guard_repo"
  TOOLS_DIR="$guard_tools"
  SLOT_WRITE_ALLOW="$guard_extra"
  BELT_PROMPT_FILE="$guard_repo/ticket/prompt.txt"
  BELT_OUT_FILE="$guard_repo/ticket/verdict.txt"
  mkdir -p "$BELT_HOME"
  : >"$BELT_PROMPT_FILE"
  : >"$BELT_OUT_FILE"
  guard_profile "$1" "$guard_repo"
)

guard_profile_rules() ( # the home/volume/tool/belt.conf rules are in every profile
  local p
  p=$(guard_profile_for worker) || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_realhome\")" || return 1
  printf '%s\n' "$p" | grep -qF '(subpath "/Volumes")' || return 1
  printf '%s\n' "$p" | grep -qF "deny file-read* (subpath \"$guard_realhome/.appstoreconnect\")" || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_tools\")" || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_extra\")" || return 1
  printf '%s\n' "$p" | grep -qF "(literal \"$guard_repo/belt.conf\")" || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_tmp/guard-belt-home\")" || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_common/hooks\")" || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_common/config\")" || return 1
  printf '%s\n' "$p" | grep -qF "(subpath \"$guard_realhome/.ssh\")" || return 1
  printf '%s\n' "$p" | grep -qF "(literal \"$guard_realhome/.ssh/known_hosts\")"
)
check_ok "the profile denies home, /Volumes, tools, belt.conf and git hooks" guard_profile_rules

guard_profile_order() ( # the final deny must come after the re-allows it blocks
  local p allow_slot deny_conf deny_ssh allow_kh
  p=$(guard_profile_for worker) || return 1
  allow_slot=$(printf '%s\n' "$p" | grep -nF "(allow file-write* (subpath \"$guard_repo\")" | head -n 1 | cut -d: -f1)
  deny_conf=$(printf '%s\n' "$p" | grep -nF "(literal \"$guard_repo/belt.conf\")" | head -n 1 | cut -d: -f1)
  deny_ssh=$(printf '%s\n' "$p" | grep -nF "(subpath \"$guard_realhome/.ssh\")" | head -n 1 | cut -d: -f1)
  allow_kh=$(printf '%s\n' "$p" | grep -nF "(literal \"$guard_realhome/.ssh/known_hosts\")" | head -n 1 | cut -d: -f1)
  [ -n "$allow_slot" ] && [ -n "$deny_conf" ] && [ "$allow_slot" -lt "$deny_conf" ] || return 1
  [ -n "$deny_ssh" ] && [ -n "$allow_kh" ] && [ "$deny_ssh" -lt "$allow_kh" ]
)
check_ok "belt.conf and .ssh denies come after the re-allows they block" guard_profile_order

guard_profile_roles() ( # reviewer: no common write but hooks denied; check: no agent env
  local w r c
  w=$(guard_profile_for worker) || return 1
  r=$(guard_profile_for reviewer) || return 1
  c=$(guard_profile_for check) || return 1
  printf '%s\n' "$w" | grep -qF "(subpath \"$guard_common\")" || return 1
  # the reviewer gets a deny, never a write allow, for the common dir
  ! printf '%s\n' "$r" | grep -F '(allow file-write*' | grep -qF "(subpath \"$guard_common\")" || return 1
  printf '%s\n' "$r" | grep -qF "(subpath \"$guard_common/hooks\")" || return 1
  printf '%s\n' "$w" | grep -qF "(subpath \"$guard_realhome/.pi\")" || return 1
  ! printf '%s\n' "$c" | grep -qF "(subpath \"$guard_realhome/.pi\")" || return 1
  printf '%s\n' "$c" | grep -qF "(subpath \"$guard_realhome/.cache\")"
)
check_ok "the reviewer gets no common dir and checks get no agent dirs" guard_profile_roles

guard_profile_common_deny() ( # the reviewer's very last rule denies the common dir
  local r w c last
  r=$(guard_profile_for reviewer) || return 1
  w=$(guard_profile_for worker) || return 1
  c=$(guard_profile_for check) || return 1
  last=$(printf '%s\n' "$r" | tail -n 1)
  # last so no earlier allow (slot dir, SLOT_WRITE_ALLOW) can win it back
  [ "$last" = "(deny file-write* (subpath \"$guard_common\"))" ] || return 1
  # roles that may write the common dir keep it
  ! printf '%s\n' "$w" | grep -qxF "(deny file-write* (subpath \"$guard_common\"))" || return 1
  ! printf '%s\n' "$c" | grep -qxF "(deny file-write* (subpath \"$guard_common\"))" || return 1
  # the reviewer still writes its own worktree
  printf '%s\n' "$r" | grep -qF "(subpath \"$guard_repo\")"
)
check_ok "the reviewer's last rule denies the whole git common dir" guard_profile_common_deny

guard_profile_browser() ( # model slots may not start a browser; checks may
  local role
  for role in worker reviewer oncall; do
    guard_profile_for "$role" | grep -q '^(deny process-exec .*Google Chrome' || return 1
  done
  ! guard_profile_for check | grep -q 'process-exec'
)
check_ok "worker, reviewer and on-call profiles deny browser exec, checks do not" guard_profile_browser

guard_browser_live() ( # the deny really stops Chrome and nothing else
  local chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" sb="$TMP/browser.sb"
  if guard_nested || ! guard_sandbox_usable || [ ! -x "$chrome" ]; then
    printf 'note: no sandbox or no Chrome here; live browser deny skipped\n'
    return 0
  fi
  guard_profile_for worker >"$sb" || return 1
  sandbox-exec -f "$sb" /bin/echo ok >/dev/null 2>&1 || return 1
  ! sandbox-exec -f "$sb" "$chrome" --version >/dev/null 2>&1
)
check_ok "inside a worker sandbox Chrome is refused and other programs run" guard_browser_live

guard_detection() ( # nested detection answers with a real probe
  if guard_nested; then
    printf 'note: already inside a sandbox; real-sandbox tests will skip\n'
    guard_sandbox_usable && return 1
    return 0
  fi
  guard_sandbox_usable && ! guard_nested
)
check_ok "nested sandbox detection uses a real probe" guard_detection

guard_probe_classification() ( # nested only for sandbox_apply's EPERM; else fail closed
  local bin="$TMP/guard-probe-bin" slot="$TMP/guard-probe-slot"
  local ran="$TMP/guard-probe-ran" err="$TMP/guard-probe.err" rc
  unset CHECKS_UNSANDBOXED
  mkdir -p "$bin" "$slot"
  PATH="$bin:$PATH"

  cat >"$bin/sandbox-exec" <<'SB'
#!/usr/bin/env bash
exit 0
SB
  chmod +x "$bin/sandbox-exec"
  guard_sandbox_usable || return 1
  guard_nested && return 1

  cat >"$bin/sandbox-exec" <<'SB'
#!/usr/bin/env bash
printf '%s\n' 'sandbox-exec: sandbox_apply: Operation not permitted' >&2
exit 71
SB
  chmod +x "$bin/sandbox-exec"
  guard_nested || return 1
  guard_sandbox_usable && return 1
  # nested is usable: the sandbox is dropped but the slot still runs
  rm -f "$ran"
  guard_exec check "$slot" "printf ran >'$ran'" || return 1
  [ -f "$ran" ] || return 1

  cat >"$bin/sandbox-exec" <<'SB'
#!/usr/bin/env bash
printf '%s\n' 'sandbox-exec: Operation not permitted' >&2
exit 71
SB
  chmod +x "$bin/sandbox-exec"
  # the words alone are not enough: it must come from sandbox_apply
  guard_nested && return 1
  guard_sandbox_usable && return 1
  rm -f "$ran"
  guard_exec check "$slot" "printf ran >'$ran'" 2>"$err"
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ ! -e "$ran" ] || return 1
  grep -q 'refusing to run the check slot' "$err" || return 1
  grep -q 'Operation not permitted' "$err" || return 1

  cat >"$bin/sandbox-exec" <<'SB'
#!/usr/bin/env bash
printf '%s\n' 'sandbox-exec: sandbox_apply: invalid profile' >&2
exit 65
SB
  chmod +x "$bin/sandbox-exec"
  # any other probe failure is broken, never nested, and the slot must not run
  guard_nested && return 1
  guard_sandbox_usable && return 1
  rm -f "$ran"
  guard_exec check "$slot" "printf ran >'$ran'" 2>"$err"
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ ! -e "$ran" ] || return 1
  grep -q 'refusing to run the check slot' "$err" || return 1
  grep -q 'invalid profile' "$err"
)
check_ok "the sandbox probe tells nested from broken and fails closed" guard_probe_classification

guard_slot_home="$TMP/guard-slot-home"
guard_slot_dir="$TMP/guard-slot-dir"
guard_slot_prompt="$TMP/guard-slot.prompt"
guard_slot_out="$TMP/guard-slot.out"
mkdir -p "$guard_slot_dir"
printf 'Guard test\n' >"$guard_slot_prompt"

guard_slot_writes() ( # the slot writes its dir and out file; HOME is throwaway and gone
  local rc h
  rm -f "$guard_slot_dir/home.txt" "$guard_slot_dir/own.txt" "$guard_slot_out"
  slot_run 'printf "%s\n" "$HOME" >own.txt.home; printf mine >own.txt; printf answer >"$BELT_OUT_FILE"' \
    "$guard_slot_dir" "$guard_slot_prompt" "$guard_slot_out" "$TMP/guard-slot.stdout"
  rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ "$(cat "$guard_slot_dir/own.txt")" = "mine" ] || return 1
  [ "$(cat "$guard_slot_out")" = "answer" ] || return 1
  h=$(cat "$guard_slot_dir/own.txt.home")
  [ -n "$h" ] || return 1
  [ "$h" != "$HOME" ] || return 1
  [ "$h" != "$guard_realhome" ] || return 1
  # the throwaway HOME is removed when the call ends
  [ ! -e "$h" ]
)
check_ok "a slot writes its own dir and out file with a throwaway HOME" guard_slot_writes

guard_pi_wrapper() ( # a bare `pi` wrapper still sees the real agent dir
  local bin="$TMP/guard-bin"
  mkdir -p "$bin"
  cat >"$bin/pi" <<'PI'
#!/usr/bin/env bash
printf 'env:%s\n' "${PI_CODING_AGENT_DIR:-unset}"
printf 'arg:%s\n' "$1"
PI
  chmod +x "$bin/pi"
  slot_run "PATH=\"$bin:\$PATH\" pi hello" "$guard_slot_dir" "$guard_slot_prompt" \
    "$guard_slot_out" "$TMP/guard-pi.stdout" || return 1
  grep -Fxq "env:$guard_realhome/.pi/agent" "$TMP/guard-pi.stdout" || return 1
  grep -Fxq 'arg:hello' "$TMP/guard-pi.stdout"
)
check_ok "a bare pi wrapper gets PI_CODING_AGENT_DIR and runs" guard_pi_wrapper

guard_conf_home() ( # a belt.conf trying to set HOME cannot change the slot's HOME
  local proj="$TMP/guard-home-proj"
  mkdir -p "$proj" "$TMP/evil-home"
  printf 'REPO="acme/widget"\nHOME="%s"\n' "$TMP/evil-home" >"$proj/belt.conf"
  BELT_PROJECT="$proj"
  load_config "$proj" >/dev/null || return 1
  slot_run 'printf "%s\n" "$HOME"' "$guard_slot_dir" "$guard_slot_prompt" \
    "$guard_slot_out" "$TMP/guard-confhome.stdout" || return 1
  h=$(cat "$TMP/guard-confhome.stdout")
  [ "$h" != "$TMP/evil-home" ] && [ "$h" != "$guard_realhome" ] && [ ! -e "$h" ]
)
check_ok "a belt.conf HOME setting never reaches the slot" guard_conf_home

guard_check_env() ( # checks get a throwaway HOME and no harness env
  local out="$TMP/guard-check-env"
  rm -f "$out"
  (
    PI_CODING_AGENT_DIR="/wrong/pi"
    CLAUDE_CONFIG_DIR="/wrong/claude"
    CODEX_HOME="/wrong/codex"
    export PI_CODING_AGENT_DIR CLAUDE_CONFIG_DIR CODEX_HOME
    guard_exec check "$guard_slot_dir" \
      "printf '%s\n%s\n%s\n%s\n' \"\$HOME\" \"\${PI_CODING_AGENT_DIR:-none}\" \"\${CODEX_HOME:-none}\" \"\${GIT_CONFIG_GLOBAL:-none}\" >'$out'"
  ) || return 1
  [ "$(sed -n 2p "$out")" = "none" ] || return 1
  [ "$(sed -n 3p "$out")" = "none" ] || return 1
  [ "$(sed -n 4p "$out")" = "$guard_realhome/.gitconfig" ] || return 1
  h=$(sed -n 1p "$out")
  [ "$h" != "$HOME" ] && [ ! -e "$h" ]
)
check_ok "a check gets a throwaway HOME and no harness env" guard_check_env

guard_gh_access() ( # only the on-call sees the token and the gh credential helper
  local bin="$TMP/guard-gh-bin" out="$TMP/guard-gh-env" role
  # earlier review tests leave a gh shell function behind (review_case runs in
  # this shell), and a function shadows PATH. Drop it so the stub on PATH is
  # what guard_exec's `gh auth token` really runs.
  unset -f gh 2>/dev/null || true
  mkdir -p "$bin"
  cat >"$bin/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1 $2" = "auth token" ]; then
  printf 'stub-token\n'
  exit 0
fi
exit 1
GH
  chmod +x "$bin/gh"
  PATH="$bin:$PATH"
  GH_TOKEN="parent-token"
  GITHUB_TOKEN="parent-github-token"
  GIT_CONFIG_COUNT=2
  GIT_CONFIG_KEY_0=credential.helper
  GIT_CONFIG_VALUE_0='!printf injected'
  GIT_CONFIG_KEY_1=credential.helper
  GIT_CONFIG_VALUE_1='!printf injected-too'
  export PATH GH_TOKEN GITHUB_TOKEN GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
    GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
  for role in worker reviewer check oncall; do
    rm -f "$out"
    guard_exec "$role" "$guard_slot_dir" \
      "printf '%s\n' \"\${GH_TOKEN:-none}\" \"\${GITHUB_TOKEN:-none}\" \"\${GIT_CONFIG_COUNT:-none}\" \"\${GIT_CONFIG_KEY_0:-none}\" \"\${GIT_CONFIG_VALUE_0-none}\" \"\${GIT_CONFIG_KEY_1:-none}\" \"\${GIT_CONFIG_VALUE_1:-none}\" \"\${GIT_TERMINAL_PROMPT:-none}\" >'$out'" || return 1
    case "$role" in
      oncall)
        [ "$(sed -n 1p "$out")" = "stub-token" ] || return 1
        [ "$(sed -n 2p "$out")" = "none" ] || return 1
        [ "$(sed -n 3p "$out")" = "2" ] || return 1
        # the empty helper comes first: it resets the osxkeychain list
        [ "$(sed -n 4p "$out")" = "credential.helper" ] || return 1
        [ "$(sed -n 5p "$out")" = "" ] || return 1
        [ "$(sed -n 6p "$out")" = "credential.helper" ] || return 1
        [ "$(sed -n 7p "$out")" = '!gh auth git-credential' ] || return 1
        [ "$(sed -n 8p "$out")" = "0" ] || return 1
        ;;
      *)
        [ "$(sed -n 1p "$out")" = "none" ] || return 1
        [ "$(sed -n 2p "$out")" = "none" ] || return 1
        [ "$(sed -n 3p "$out")" = "none" ] || return 1
        [ "$(sed -n 4p "$out")" = "none" ] || return 1
        [ "$(sed -n 5p "$out")" = "none" ] || return 1
        [ "$(sed -n 6p "$out")" = "none" ] || return 1
        [ "$(sed -n 7p "$out")" = "none" ] || return 1
        [ "$(sed -n 8p "$out")" = "0" ] || return 1
        ;;
    esac
  done
)
check_ok "only the on-call slot gets GH_TOKEN and the gh git helper" guard_gh_access

guard_tools_survive() ( # a sandboxed slot cannot delete TOOLS_DIR
  local tools="$TMP/guard-tools-live" rc
  if guard_nested; then
    printf 'note: skipped the real-sandbox TOOLS_DIR test (already inside a sandbox)\n'
    return 0
  fi
  mkdir -p "$tools"
  printf 'keep me\n' >"$tools/sentinel"
  (
    TOOLS_DIR="$tools"
    BELT_HOME="$TMP/guard-belt-home"
    slot_run "rm -rf '$tools'" "$guard_slot_dir" "$guard_slot_prompt" \
      "$guard_slot_out" "$TMP/guard-tools.stdout" "$TMP/guard-tools.stderr"
  )
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ -f "$tools/sentinel" ]
)
check_ok "a sandboxed slot cannot delete TOOLS_DIR" guard_tools_survive

guard_reviewer_refs_survive() ( # a sandboxed reviewer cannot delete a ref
  local proj="$TMP/guard-reviewer-proj" rc ref sha
  if guard_nested; then
    printf 'note: skipped the real-sandbox reviewer ref test (already inside a sandbox)\n'
    return 0
  fi
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$proj" config user.email belt@example.com
  git -C "$proj" config user.name belt
  printf 'keep\n' >"$proj/tracked.txt"
  git -C "$proj" add tracked.txt
  git -C "$proj" commit -qm base
  ref=$(git -C "$proj" symbolic-ref --short HEAD) || return 1
  sha=$(git -C "$proj" rev-parse "refs/heads/$ref") || return 1
  # the project sits under $TMP, outside the real home and /Volumes
  (
    BELT_HOME="$TMP/guard-belt-home"
    PROJECT="$proj"
    TOOLS_DIR="$guard_tools"
    slot_run "git update-ref -d refs/heads/$ref" "$proj" "$guard_slot_prompt" \
      "$guard_slot_out" "$TMP/guard-reviewer.stdout" "$TMP/guard-reviewer.stderr" reviewer
  )
  rc=$?
  [ "$rc" -ne 0 ] || return 1
  [ "$(git -C "$proj" rev-parse "refs/heads/$ref" 2>/dev/null)" = "$sha" ]
)
check_ok "a sandboxed reviewer cannot delete a ref in a TMP project" guard_reviewer_refs_survive

# ------------------------------------------------------------------ backup ---

backup_proj="$TMP/backup-proj"
backup_tools="$TMP/backup-tools"
backup_tn=backup-tools
backup_home="$TMP/backup-home"
backup_dest="$TMP/backup-dest"
backup_notify="$TMP/backup-notify"
backup_notify_script="$TMP/backup-notify.sh"
mkdir -p "$backup_proj"
printf '# belt\n' >"$backup_proj/BELT.md"
cat >"$backup_notify_script" <<NOTIFY
#!/usr/bin/env bash
printf '%s\n' "\$BELT_MESSAGE" >>"$backup_notify"
NOTIFY
cat >"$backup_proj/belt.conf" <<EOF
REPO="acme/widget"
BACKUP_DIR="$backup_dest"
TOOLS_DIR="$backup_tools"
OWNER_NOTIFY_CMD="bash '$backup_notify_script'"
EOF

backup_reset() {
  rm -rf "$backup_home" "$backup_dest" "$backup_tools"
  rm -f "$backup_notify"
  mkdir -p "$backup_tools/bin/asc-secrets" "$backup_tools/bin/_work" "$backup_tools/bin/_diag"
  printf 'tool\n' >"$backup_tools/bin/tool"
  printf 'SECRET=one\n' >"$backup_tools/bin/secret.env"
  printf 'key\n' >"$backup_tools/bin/key.pem"
  printf 'creds\n' >"$backup_tools/bin/.credentials"
  printf 'runner\n' >"$backup_tools/bin/.runner"
  printf 'asc\n' >"$backup_tools/bin/asc-secrets/asc.json"
  printf 'work\n' >"$backup_tools/bin/_work/x"
  printf 'diag\n' >"$backup_tools/bin/_diag/x"
  printf 'log\n' >"$backup_tools/bin/build.log"
}

backup_run_once() ( # one snapshot for the backup project
  BELT_HOME="$backup_home"
  LOG="$TMP/backup-test.log"
  load_config "$backup_proj" >/dev/null || return 1
  SLUG="acme/widget"
  backup_run
)

backup_snaps() { ls -1d "$backup_dest"/acme__widget/* 2>/dev/null; }

backup_noglob() ( # latest and prune still glob when the caller has noglob on
  local root="$TMP/backup-noglob" latest
  rm -rf "$root"
  mkdir -p "$root/20200101-0001" "$root/20200101-0002" "$root/20200101-0003" \
    "$root/not-a-snapshot"
  set -f
  latest=$(backup_latest "$root")
  backup_prune "$root" 2
  set +f
  [ "$(basename "$latest")" = "20200101-0003" ] || return 1
  [ ! -e "$root/20200101-0001" ] || return 1
  [ -d "$root/20200101-0002" ] || return 1
  [ -d "$root/20200101-0003" ] || return 1
  [ -d "$root/not-a-snapshot" ]
)
check_ok "a caller's noglob does not break the latest snapshot or pruning" backup_noglob

backup_snapshot_contents() ( # belt.conf, BELT.md and tools in; secrets out
  local snaps s
  backup_reset
  backup_run_once || return 1
  snaps=$(backup_snaps)
  [ "$(printf '%s\n' "$snaps" | grep -c '')" -eq 1 ] || return 1
  s=$(printf '%s\n' "$snaps" | sed -n 1p)
  [ -f "$s/belt.conf" ] && [ -f "$s/BELT.md" ] || return 1
  [ -f "$s/tools/$backup_tn/bin/tool" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/secret.env" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/key.pem" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.credentials" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.runner" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/asc-secrets" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/_work" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/_diag" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/build.log" ]
)
check_ok "a snapshot holds belt.conf, BELT.md and tools, never secrets" backup_snapshot_contents

backup_excludes_env_files() ( # .env variants, npmrc, netrc and git credentials stay out
  local s
  backup_reset
  printf 'SECRET=one\n' >"$backup_tools/bin/secret.env.local"
  printf 'SECRET=one\n' >"$backup_tools/bin/.env"
  printf 'SECRET=one\n' >"$backup_tools/bin/.env.production"
  printf 'registry=https://npm.example\n' >"$backup_tools/bin/.npmrc"
  printf 'machine example\n' >"$backup_tools/bin/.netrc"
  printf 'https://user:pass@example\n' >"$backup_tools/bin/.git-credentials"
  backup_run_once || return 1
  s=$(backup_snaps | sed -n 1p)
  [ -f "$s/tools/$backup_tn/bin/tool" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/secret.env.local" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.env" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.env.production" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.npmrc" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.netrc" ] || return 1
  [ ! -e "$s/tools/$backup_tn/bin/.git-credentials" ]
)
check_ok "a snapshot excludes .env variants, npmrc, netrc and git credentials" backup_excludes_env_files

backup_no_delete() ( # removing a source file never removes it from older snapshots
  local a b c ino1 ino2
  backup_reset
  backup_run_once || return 1
  printf 'extra\n' >"$backup_tools/bin/extra.txt"
  backup_run_once || return 1
  rm -f "$backup_tools/bin/extra.txt"
  backup_run_once || return 1
  a=$(backup_snaps | sed -n 1p)
  b=$(backup_snaps | sed -n 2p)
  c=$(backup_snaps | sed -n 3p)
  [ ! -e "$a/tools/$backup_tn/bin/extra.txt" ] || return 1
  [ -f "$b/tools/$backup_tn/bin/extra.txt" ] || return 1
  [ ! -e "$c/tools/$backup_tn/bin/extra.txt" ] || return 1
  # unchanged files are hardlinks to the previous snapshot
  ino1=$(stat -f '%i' "$a/tools/$backup_tn/bin/tool" 2>/dev/null || stat -c '%i' "$a/tools/$backup_tn/bin/tool")
  ino2=$(stat -f '%i' "$b/tools/$backup_tn/bin/tool" 2>/dev/null || stat -c '%i' "$b/tools/$backup_tn/bin/tool")
  [ -n "$ino1" ] && [ "$ino1" = "$ino2" ]
)
check_ok "a backup never --deletes and hardlinks unchanged files" backup_no_delete

backup_keeps_14() ( # the newest 14 snapshots survive, older ones are pruned
  local i
  backup_reset
  mkdir -p "$backup_dest/acme__widget"
  i=1
  while [ "$i" -le 14 ]; do
    mkdir -p "$(printf '%s/acme__widget/20200101-%04d' "$backup_dest" "$i")"
    i=$((i + 1))
  done
  backup_run_once || return 1
  [ "$(backup_snaps | grep -c '')" -eq 14 ] || return 1
  [ ! -e "$backup_dest/acme__widget/20200101-0001" ]
)
check_ok "a backup keeps the newest 14 snapshots" backup_keeps_14

backup_missing_tools() ( # gone tools: no pruning, and one deduped owner ping
  local i
  backup_reset
  backup_run_once || return 1
  i=1
  while [ "$i" -le 14 ]; do
    mkdir -p "$(printf '%s/acme__widget/20200101-%04d' "$backup_dest" "$i")"
    i=$((i + 1))
  done
  rm -rf "$backup_tools"
  backup_run_once || return 1
  backup_run_once || return 1
  [ "$(backup_snaps | grep -c '')" -gt 14 ] || return 1
  [ "$(grep -c '' "$backup_notify" 2>/dev/null || echo 0)" -eq 1 ]
)
check_ok "missing tools stop pruning and ping the owner once" backup_missing_tools

backup_empty_dir() ( # BACKUP_DIR empty: fail, one deduped ping, no snapshot
  local proj="$TMP/backup-nodir-proj"
  mkdir -p "$proj"
  printf '# belt\n' >"$proj/BELT.md"
  cat >"$proj/belt.conf" <<EOF
REPO="acme/widget"
OWNER_NOTIFY_CMD="bash '$backup_notify_script'"
EOF
  cleanup_backup_home="$TMP/backup-nodir-home"
  rm -rf "$cleanup_backup_home"
  rm -f "$backup_notify"
  BELT_HOME="$cleanup_backup_home"
  LOG="$TMP/backup-nodir.log"
  load_config "$proj" >/dev/null || return 1
  SLUG="acme/widget"
  backup_run && return 1
  backup_run && return 1
  [ "$(grep -c '' "$backup_notify" 2>/dev/null || echo 0)" -eq 1 ]
)
check_ok "an empty BACKUP_DIR fails with one deduped owner ping" backup_empty_dir

backup_same_volume_warns() ( # BACKUP_DIR on the tools' volume only warns
  backup_reset
  backup_run_once || return 1
  grep -q 'same volume' "$TMP/backup-test.log"
)
check_ok "a BACKUP_DIR on the tools' volume warns" backup_same_volume_warns

backup_cli() ( # belt backup <project> writes one snapshot
  backup_reset
  BELT_HOME="$backup_home" "$ROOT/belt" backup "$backup_proj" >/dev/null 2>&1 || return 1
  [ "$(backup_snaps | grep -c '')" -eq 1 ]
)
check_ok "belt backup <project> writes one snapshot" backup_cli

# ---------------------------------------------------- on-call restart ---

restart_verdict_files() ( # oncall_verdict_of and oncall_restart_issue
  local f="$TMP/restart-verdict.txt"
  printf 'doing it\nONCALL: RESTART 61\n' >"$f"
  [ "$(oncall_verdict_of "$f")" = "restart" ] || return 1
  [ "$(oncall_restart_issue "$f")" = "61" ] || return 1
  printf 'ONCALL: RESTART 61a\n' >"$f"
  [ "$(oncall_verdict_of "$f")" = "none" ] || return 1
  [ -z "$(oncall_restart_issue "$f")" ] || return 1
  printf 'ONCALL: RESTART\n' >"$f"
  [ "$(oncall_verdict_of "$f")" = "none" ] || return 1
  printf 'ONCALL: WAITING\n' >"$f"
  [ "$(oncall_verdict_of "$f")" = "waiting" ]
)
check_ok "ONCALL: RESTART is parsed only with a numeric issue" restart_verdict_files

restart_proj="$TMP/restart-verdict-proj"
restart_home="$TMP/restart-verdict-home"
restart_count="$TMP/restart-verdict-count"
restart_oncalls="$TMP/restart-verdict-oncalls"
restart_cmd_script="$TMP/restart-verdict-cmd.sh"
restart_oncall_script="$TMP/restart-verdict-oncall.sh"
mkdir -p "$restart_proj"
printf '# belt\n' >"$restart_proj/BELT.md"
cat >"$restart_cmd_script" <<'CMD'
#!/usr/bin/env bash
printf 'restart %s\n' "$BELT_ISSUE" >>"$RESTART_COUNT"
CMD
cat >"$restart_oncall_script" <<'ONCALL'
#!/usr/bin/env bash
printf 'call\n' >>"$RESTART_ONCALLS"
printf 'restarting the ticket\nONCALL: RESTART 61\n'
ONCALL
cat >"$restart_proj/belt.conf" <<EOF
REPO="acme/widget"
ONCALL_CMD="bash '$restart_oncall_script'"
TICKET_RESTART_CMD="bash '$restart_cmd_script'"
OWNER_NOTIFY_CMD="true"
BACKUP_DIR="$TMP/restart-verdict-backup"
EOF

restart_waits() { # <count> <seconds>; wait until the detached restart landed
  local want=${1:-1} limit=${2:-15} i=0 have
  while [ "$i" -lt "$limit" ]; do
    have=$(grep -c '' "$restart_count" 2>/dev/null) || have=0
    [ "$have" -ge "$want" ] && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

restart_once_capped() ( # one restart per verdict, and the 2-call cap still applies
  local i=0 creates="$TMP/restart-verdict-creates"
  rm -rf "$restart_home"; rm -f "$restart_count" "$restart_oncalls" "$creates"
  : >"$TMP/restart-verdict-flag"
  : >"$creates"
  BELT_HOME="$restart_home"; export BELT_HOME
  STUCK_FLAG="$TMP/restart-verdict-flag"; export STUCK_FLAG
  WATCH_CREATES="$creates"; export WATCH_CREATES
  WATCH_TITLES="$TMP/restart-verdict-titles"; : >"$WATCH_TITLES"; export WATCH_TITLES
  RESTART_COUNT="$restart_count"; export RESTART_COUNT
  RESTART_ONCALLS="$restart_oncalls"; export RESTART_ONCALLS
  gh() { watch_gh "$@"; }
  cmd_watch "$restart_proj" >/dev/null 2>&1 || return 1
  restart_waits 1 || return 1
  cmd_watch "$restart_proj" >/dev/null 2>&1 || return 1
  restart_waits 2 || return 1
  cmd_watch "$restart_proj" >/dev/null 2>&1 || return 1
  sleep 2
  [ "$(grep -c '' "$restart_count")" -eq 2 ] || return 1
  [ "$(grep -c '' "$restart_oncalls")" -eq 2 ] || return 1
  grep -Fxq 'restart 61' "$restart_count" || return 1
  grep -q 'keeps failing' "$creates"
)
check_ok "ONCALL: RESTART runs the command once and stays under the cap" restart_once_capped

restart_wrong_issue() ( # a restart for another issue is ignored
  local proj="$TMP/restart-wrong-proj" home="$TMP/restart-wrong-home"
  local count="$TMP/restart-wrong-count" err="$TMP/restart-wrong.err"
  mkdir -p "$proj"
  printf '# belt\n' >"$proj/BELT.md"
  printf '#!/usr/bin/env bash\nprintf "ONCALL: RESTART 99\\n"\n' >"$TMP/restart-wrong-oncall.sh"
  cat >"$proj/belt.conf" <<EOF
REPO="acme/widget"
ONCALL_CMD="bash '$TMP/restart-wrong-oncall.sh'"
TICKET_RESTART_CMD="printf wrong >> '$count'"
OWNER_NOTIFY_CMD="true"
EOF
  rm -rf "$home"; rm -f "$count" "$err"
  (
    BELT_HOME="$home"
    LOG="$TMP/restart-wrong.log"
    load_config "$proj" >/dev/null || exit 1
    SLUG="acme/widget"
    gh() { watch_gh "$@"; }
    oncall_run_problem "stuck:61" 61 stuck
  ) >/dev/null 2>"$err" || return 1
  [ ! -e "$count" ] || return 1
  grep -q 'ignoring it' "$err"
)
check_ok "a restart verdict for another issue is ignored" restart_wrong_issue

# ------------------------------------------------------------------- syntax ---

check_syntax() {
  local f
  for f in "$ROOT/belt" "$ROOT"/lib/*.sh "$ROOT/tests/selftest.sh"; do
    bash -n "$f" || return 1
  done
  return 0
}
check_ok "bash -n on every script" check_syntax

# ------------------------------------------------------------- hung workers ---
# Real processes, stopped only by the exact pid they wrote. Never use pkill or
# pgrep patterns here: one such line once signalled the owner's whole desktop.
# Any test that could reach a kill with a bad pid shadows `kill`.

hang_proj="$TMP/hang-proj"
hang_home="$TMP/hang-home"
hang_claim="$TMP/hang-claim"
hang_creates="$TMP/hang-creates"
hang_notes="$TMP/hang-notes"
HANG_LOCK="$TMP/hang.lock"; export HANG_LOCK
HANG_LOG="$TMP/hang-logs/420/run.log"; export HANG_LOG
HANG_PIDFILE="$TMP/hang.pid"; export HANG_PIDFILE
HANG_WORKER="$TMP/hang-worker.sh"; export HANG_WORKER
HANG_NOTES="$hang_notes"; export HANG_NOTES
hang_starts="$TMP/hang-starts"
hang_worktree="$hang_proj/.worktrees/pipeline-420"
hang_verdict="$TMP/hang-verdict"
mkdir -p "$hang_worktree" "$(dirname "$HANG_LOG")"
: >"$HANG_LOCK"
cat >"$HANG_WORKER" <<WORKER
#!/usr/bin/env bash
# a hung worker: logs once, then waits on a child that does nothing
cd '$hang_worktree' || exit 1
printf '%s\n' "\$\$" >"\$HANG_PIDFILE"
printf 'start\n' >>'$hang_starts'
printf 'worker started\n' >>"\$HANG_LOG"
sleep 120 &
wait
WORKER
cat >"$TMP/hang-oncall.sh" <<ONCALL
#!/usr/bin/env bash
# what on-call did on #420: it took the label off, then asked for a restart
rm -f '$hang_claim'
printf 'ONCALL: %s\n' "\$(cat '$hang_verdict')"
ONCALL
printf '# hang project\n' >"$hang_proj/BELT.md"
{
  printf 'REPO="acme/widget"\nSILENT_MIN="1"\nCLAIM_LABEL="claimed:pipeline"\nBRANCH_PREFIX="pipeline/"\n'
  printf 'ONCALL_CMD="bash %s"\n' "'$TMP/hang-oncall.sh'"
  cat <<'CONF'
OWNER_NOTIFY_CMD='printf "%s\n" "$BELT_MESSAGE" >>"$HANG_NOTES"'
TICKET_LOG_CMD='printf "%s\n" "$HANG_LOG"'
TICKET_ALIVE_CMD='p=$(cat "$HANG_PIDFILE" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && printf "%s\n" "$p"'
TICKET_RESTART_CMD='nohup lockf -t 0 "$HANG_LOCK" bash "$HANG_WORKER" $BELT_ISSUE >/dev/null 2>&1 &'
CONF
} >"$hang_proj/belt.conf"
hang_gh() {
  case "$*" in
    *'label create'*) return 0 ;;
    *'--label claimed:pipeline'*)
      if [ -f "$hang_claim" ]; then
        printf '[{"number":420,"labels":[{"name":"claimed:pipeline"}]}]\n'
      else
        printf '[]\n'
      fi ;;
    *'issue edit'*) rm -f "$hang_claim" ;;
    *'issue view'*'--json state'*) printf 'OPEN\n' ;;
    *'issue view'*) if [ -f "$hang_claim" ]; then printf 'claimed:pipeline\n'; fi ;;
    *'issue create'*) printf '%s\n' "$*" >>"$hang_creates"; printf 'https://github.com/acme/widget/issues/90\n' ;;
    *'issue list'*|*'issues'*) printf '[]\n' ;;
    *) return 0 ;;
  esac
}
hang_start() { # a fresh hung run that holds the lock
  rm -f "$HANG_PIDFILE"
  nohup lockf -t 0 "$HANG_LOCK" bash "$HANG_WORKER" 420 >/dev/null 2>&1 &
  sleep 1
}
hang_pid() { cat "$HANG_PIDFILE" 2>/dev/null; }
hang_stop() { # only the worker that wrote the pid file, and its children
  local p kids
  p=$(hang_pid)
  case "$p" in ''|*[!0-9]*|0|1) rm -f "$HANG_PIDFILE"; return 0 ;; esac
  kill -0 "$p" 2>/dev/null || { rm -f "$HANG_PIDFILE"; return 0; }
  kids=$(pgrep -P "$p" 2>/dev/null)
  # shellcheck disable=SC2086
  kill -KILL "$p" $kids 2>/dev/null
  rm -f "$HANG_PIDFILE"
  sleep 1
  return 0
}
hang_age() { touch -t 202001010000 "$HANG_LOG" "$(dirname "$HANG_LOG")" "$hang_worktree"; }
hang_pass() (
  BELT_HOME="$hang_home"; export BELT_HOME
  BELT_TIME_SCALE=60; export BELT_TIME_SCALE
  gh() { hang_gh "$@"; }
  cmd_watch "$hang_proj" >/dev/null 2>&1
)
hang_load() {
  BELT_HOME="$hang_home"; export BELT_HOME
  LOG="$TMP/hang.log"
  load_config "$hang_proj" >/dev/null || return 1
  SLUG="acme/widget"
  gh() { hang_gh "$@"; }
}
hang_reset() {
  hang_stop
  rm -rf "$hang_home"; rm -f "$hang_notes"
  : >"$hang_claim"; : >"$hang_creates"; : >"$hang_starts"; : >"$HANG_LOG"
  printf 'RESTART 420\n' >"$hang_verdict"
}

hang_replay() ( # #420, start to finish: a hang is flagged, stopped, restarted and verified
  hang_reset; hang_start
  old=$(hang_pid); [ -n "$old" ] || { echo "no worker"; return 1; }
  hang_age
  hang_pass  # first sample: no evidence yet
  [ "$(hang_pid)" = "$old" ] || { echo "first pass acted on no evidence"; hang_stop; return 1; }
  sleep 2; hang_age
  hang_pass  # low CPU across two samples: hung
  sleep 2
  kill -0 "$old" 2>/dev/null && { echo "old run survived"; hang_stop; return 1; }
  new=$(hang_pid); [ -n "$new" ] && [ "$new" != "$old" ] || { echo "no new run"; hang_stop; return 1; }
  [ "$(grep -c start "$hang_starts")" -eq 2 ] || { echo "restart never got the lock"; hang_stop; return 1; }
  [ ! -f "$hang_claim" ] || { echo "label kept"; hang_stop; return 1; }
  sleep 6
  hang_pass
  grep -q 'restart of #420 verified' "$hang_home/acme__widget/watch.log" 2>/dev/null \
    || grep -q 'restart of #420 verified' "$LOG" 2>/dev/null \
    || { echo "restart not verified"; tail -12 "$hang_home/acme__widget/watch.log"; tail -5 "$LOG"; ls "$hang_home/acme__widget"; hang_stop; return 1; }
  [ ! -s "$hang_creates" ] || { echo "false alarm"; hang_stop; return 1; }
  # the second run hangs too, and it has no label: it must still be seen
  sleep 2; hang_age
  hang_pass
  sleep 2; new2=$(hang_pid)
  [ "$(grep -c '' "$hang_home/acme__widget/oncall-attempts/420")" -eq 2 ] \
    || { echo "unlabelled hung run went unseen"; hang_stop; return 1; }
  # and past the cap the owner hears about it, whatever happens to the label
  hang_age; hang_pass; sleep 2; hang_age; hang_pass
  grep -q 'keeps failing' "$hang_creates" || { echo "owner issue missing"; hang_stop; return 1; }
  grep -q 'keeps failing' "$hang_notes" || { echo "owner alert missing"; hang_stop; return 1; }
  hang_stop
)
check_ok "a hung worker that loses its label is stopped, restarted and verified (#420)" hang_replay

hang_tracked_ends() ( # a run that has ended leaves the watch list
  hang_reset; hang_load || return 1
  mkdir -p "$(watch_state_dir)"
  hang_start
  watch_runner_tickets | grep -q '^420' || { hang_stop; return 1; }
  rm -f "$hang_claim"
  watch_runner_tickets | grep -q '^420' || { hang_stop; return 1; }
  hang_stop
  watch_runner_tickets | grep -q '^420' && return 1
  [ ! -s "$(watch_state_dir)/watch.tracked" ]
)
check_ok "a ticket stays watched until its run has ended, not until its label goes" hang_tracked_ends

hang_worktree_busy() ( # a file changing in the run's own folder is not a hang
  hang_reset; hang_load || return 1
  mkdir -p "$(watch_state_dir)"; hang_start
  # a 10-second hang window: at 1 second the edit can age out before the check
  BELT_TIME_SCALE=6; export BELT_TIME_SCALE
  old=$(hang_pid)
  printf '%s:%s:1\n' "$old" "$(slot_cpu_cs "$old")" >"$(watch_state_dir)/watch-cpu.420"
  hang_age
  sleep 2
  [ "$(watch_silent_key 420)" = "silent:420" ] || { hang_stop; return 1; }
  printf '%s:%s:1\n' "$old" "$(slot_cpu_cs "$old")" >"$(watch_state_dir)/watch-cpu.420"
  : >"$hang_worktree/edit.txt"
  out=$(watch_silent_key 420)
  rm -f "$hang_worktree/edit.txt"
  hang_stop
  [ -z "$out" ]
)
check_ok "a change in the run's worktree keeps a custom-runner ticket from being flagged" hang_worktree_busy

hang_no_kill_unless_hung() ( # only silent kills: a budget overrun on a live run does not
  hang_reset; hang_load || return 1
  mkdir -p "$(watch_state_dir)"; hang_start
  old=$(hang_pid)
  oncall_run_problem "budget:420:impl:1" 420 budget >/dev/null 2>&1
  kill -0 "$old" 2>/dev/null; rc=$?
  hang_stop
  [ "$rc" -eq 0 ]
)
check_ok "a restart verdict on a live run that is not hung kills nothing" hang_no_kill_unless_hung

hang_cpu_case() ( # <prev-pid> <prev-cs> <now-cs> <secs-ago>; the watch_cpu_used status
  hang_load || return 1
  mkdir -p "$(watch_state_dir)"
  WATCH_TICKET_PID=4242
  HANG_NOW_CS=$3
  slot_cpu_cs() { printf '%s\n' "$HANG_NOW_CS"; }
  printf '%s:%s:%s\n' "$1" "$2" "$(($(date '+%s') - $4))" >"$(watch_state_dir)/watch-cpu.420"
  watch_cpu_used 420 60
)
hang_cpu_no_sample() (
  hang_load || return 1
  mkdir -p "$(watch_state_dir)"; rm -f "$(watch_state_dir)/watch-cpu.420"
  WATCH_TICKET_PID=4242
  slot_cpu_cs() { printf '100\n'; }
  watch_cpu_used 420 60
)
check_no "the CPU a hung worker uses is not busy (#420's 7 cs a minute)" hang_cpu_case 4242 100 170 600
check_ok "real CPU use is busy" hang_cpu_case 4242 100 1100 600
check_ok "no sample yet is no evidence of a hang" hang_cpu_no_sample
check_ok "a changed pid is no evidence of a hang" hang_cpu_case 1111 100 100 600
check_ok "a sample too fresh to compare is no evidence of a hang" hang_cpu_case 4242 100 100 5
check_ok "a total that dropped means a child finished: busy" hang_cpu_case 4242 900 100 600

hang_tree_scoped() ( # the bug that nearly listed every process on the Mac
  sleep 60 & root=$!
  out=$(watch_tree_pids "$root")
  kill "$root" 2>/dev/null
  [ "$out" = "$root" ]
)
check_ok "the process tree of a lone process is that process, nothing else" hang_tree_scoped

hang_kill_tree() ( # the whole tree goes, child too
  hang_reset; hang_load || return 1
  BELT_TIME_SCALE=60; export BELT_TIME_SCALE
  hang_start
  old=$(hang_pid); kids=$(watch_tree_pids "$old")
  [ "$(printf '%s\n' "$kids" | grep -c '')" -ge 2 ] || { hang_stop; return 1; }
  watch_kill_ticket 420 || { hang_stop; return 1; }
  for p in $kids; do kill -0 "$p" 2>/dev/null && return 1; done
  return 0
)
check_ok "stopping a ticket stops its whole process tree" hang_kill_tree

hang_refuses() ( # <alive-cmd>; 1 from watch_kill_ticket, and no signal sent
  hang_load || return 1
  TICKET_ALIVE_CMD=$1
  called="$TMP/hang-kill-called"; rm -f "$called"
  kill() { [ "${1:-}" = "-0" ] && return 0; : >"$called"; return 0; }
  sleep() { :; }
  watch_kill_ticket 420 && return 1
  [ ! -e "$called" ]
)
check_ok "pid 1 is never killed" hang_refuses 'printf "1\n"'
check_ok "pid 0 is never killed" hang_refuses 'printf "0\n"'
check_ok "a tree holding the watcher itself is never killed" hang_refuses "printf '%s\n' $$"

hang_stale_lock() ( # a custom runner with no pid must not fall back to an old lock's pid
  hang_load || return 1
  mkdir -p "$(watch_state_dir)/420/ticket.lock"
  sleep 60 & other=$!
  printf '%s\n' "$other" >"$(watch_state_dir)/420/ticket.lock/pid"
  TICKET_ALIVE_CMD='true'
  watch_kill_ticket 420; rc=$?
  kill -0 "$other" 2>/dev/null; alive=$?
  kill "$other" 2>/dev/null
  rm -rf "$(watch_state_dir)/420"
  [ "$rc" -ne 0 ] && [ "$alive" -eq 0 ]
)
check_ok "a custom runner's stale lock pid is never killed" hang_stale_lock

hang_reused_pid() ( # belt's own lock, whose pid now belongs to something else
  hang_load || return 1
  TICKET_ALIVE_CMD=""
  mkdir -p "$(watch_state_dir)/420/ticket.lock"
  sleep 60 & other=$!
  printf '%s\n' "$other" >"$(watch_state_dir)/420/ticket.lock/pid"
  watch_kill_ticket 420; rc=$?
  kill -0 "$other" 2>/dev/null; alive=$?
  kill "$other" 2>/dev/null
  rm -rf "$(watch_state_dir)/420"
  [ "$rc" -ne 0 ] && [ "$alive" -eq 0 ]
)
check_ok "a lock pid reused by another program is never killed" hang_reused_pid

hang_verify() ( # <log-moved 0|1> <live 0|1> <issue-state> <head-then> <head-now> [old]
  hang_load || return 1
  state=$(watch_state_dir); mkdir -p "$state"
  at=$(($(date '+%s') - 400))
  printf '%s %s\n' "$at" "$4" >"$state/restart-verify.420"
  [ "${6:-}" = "old" ] && printf '%s\n' "$at" >"$state/restart-verify.420"
  : >"$HANG_LOG"
  [ "$1" = 1 ] || touch -t 202001010000 "$HANG_LOG"
  VERIFY_LIVE=$2 VERIFY_STATE=$3 VERIFY_HEAD=$5
  watch_ticket_live() { [ "$VERIFY_LIVE" = 1 ]; }
  watch_pr_for_issue() { [ -z "$VERIFY_HEAD" ] || printf '7\t%s\n' "$VERIFY_HEAD"; }
  gh() { case "$*" in *'--json state'*) printf '%s\n' "$VERIFY_STATE" ;; esac; }
  create_owner_issue() { printf '%s\n' "$2" >"$TMP/hang-verify-title"; }
  owner_notify_once() { :; }
  rm -f "$TMP/hang-verify-title"
  watch_verify_restarts >/dev/null 2>&1
  [ ! -e "$TMP/hang-verify-title" ]  # 0 = verified, 1 = owner alerted
)
check_ok "restart check: alive with a moved log passes" hang_verify 1 1 OPEN aaa aaa
check_no "restart check: alive with a still log fails" hang_verify 0 1 OPEN aaa aaa
check_no "restart check: nothing running and a still log fails" hang_verify 0 0 OPEN aaa aaa
check_no "restart check: ended with an unchanged open PR fails" hang_verify 1 0 OPEN aaa aaa
check_ok "restart check: ended having pushed new work passes" hang_verify 1 0 OPEN aaa bbb
check_ok "restart check: ended with the issue closed passes" hang_verify 1 0 CLOSED aaa aaa
check_no "restart check: an old marker with no head still fails a dead run" hang_verify 1 0 OPEN "" "" old

hang_playbook() (
  hang_load || return 1
  p=$(watch_playbook)
  printf '%s\n' "$p" | grep -q 'Leave `claimed:pipeline` alone and kill nothing' || return 1
  ! printf '%s\n' "$p" | grep -qi 'kill the whole tree'
)
check_ok "the playbook leaves the label and the kill to belt" hang_playbook

# ---------------------------------------------------------------- batch CI ---
bci_proj="$TMP/bci-proj"; bci_home="$TMP/bci-home"
mkdir -p "$bci_proj"
printf 'REPO="acme/widget"\nOWNER_NOTIFY_CMD="true"\n' >"$bci_proj/belt.conf"
bci_run() { # <status> <conclusion> <started> <jobs-json> [gh-fails]
  BELT_HOME="$bci_home"; export BELT_HOME
  LOG="$TMP/bci.log"
  load_config "$bci_proj" >/dev/null || return 1
  SLUG="acme/widget"
  mkdir -p "$(watch_state_dir)"
  BCI_RUNS=$(printf '[{"databaseId":5,"headBranch":"batch/1","status":"completed","conclusion":"success","startedAt":"2020-01-01T00:00:00Z","attempt":1},{"databaseId":9,"headBranch":"batch/1","status":"%s","conclusion":"%s","startedAt":"%s","attempt":1},{"databaseId":7,"headBranch":"feature","status":"completed","conclusion":"failure","startedAt":"2020-01-01T00:00:00Z","attempt":1}]' "$1" "$2" "$3")
  BCI_JOBS=$4; BCI_FAIL=${5:-}
  gh() {
    printf '%s\n' "$*" >>"$TMP/bci-calls"
    [ -z "$BCI_FAIL" ] || return 1
    case "$*" in
      *'pr list'*) printf 'batch/1\nfeature\n' ;;
      *'run list'*) printf '%s\n' "$BCI_RUNS" ;;
      *'run view'*) printf '%s\n' "$BCI_JOBS" ;;
    esac
  }
  owner_notify_once() { printf '%s\n' "$3" >>"$TMP/bci-notes"; }
  : >"$TMP/bci-calls"; : >"$TMP/bci-notes"
  watch_batch_ci
}
bci_reset() { rm -rf "$bci_home"; }
bci_infra='{"jobs":[{"conclusion":"failure","steps":[{"conclusion":"success"}]}]}'
bci_real='{"jobs":[{"conclusion":"failure","steps":[{"conclusion":"failure"}]}]}'
bci_now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
bci_infra_once() ( # re-run once, then the owner hears
  bci_reset
  bci_run completed failure "$bci_now" "$bci_infra" || return 1
  grep -q 'run rerun 9' "$TMP/bci-calls" && [ ! -s "$TMP/bci-notes" ] || return 1
  bci_run completed failure "$bci_now" "$bci_infra" || return 1
  ! grep -q 'run rerun' "$TMP/bci-calls" && grep -q 'again after one re-run' "$TMP/bci-notes"
)
check_ok "batch CI: an infrastructure failure is re-run once, then the owner is alerted" bci_infra_once
bci_real_fail() ( bci_reset; bci_run completed failure "$bci_now" "$bci_real" || return 1; ! grep -q 'run rerun' "$TMP/bci-calls" && grep -q 'batch CI failed on batch/1' "$TMP/bci-notes" )
check_ok "batch CI: a real test failure is never re-run and alerts the owner" bci_real_fail
bci_cancelled() ( bci_reset; bci_run completed cancelled "$bci_now" '{}' || return 1; ! grep -q 'run rerun' "$TMP/bci-calls" && grep -q 'cancelled' "$TMP/bci-notes" )
check_ok "batch CI: a cancelled run is reported, not re-run" bci_cancelled
bci_overdue() ( bci_reset; bci_run in_progress "" 2020-01-01T00:00:00Z '{}' || return 1; grep -q 'has been running' "$TMP/bci-notes" )
check_ok "batch CI: an overdue run alerts the owner" bci_overdue
bci_fine() ( bci_reset; bci_run in_progress "" "$bci_now" '{}' || return 1; [ ! -s "$TMP/bci-notes" ] || return 1; bci_run completed success "$bci_now" '{}' || return 1; [ ! -s "$TMP/bci-notes" ] && ! grep -q 'run view' "$TMP/bci-calls" )
check_ok "batch CI: a healthy run is left alone, and other branches are ignored" bci_fine
bci_unread() ( # a network drop alerts after an hour and acts on nothing
  bci_reset
  bci_run completed failure "$bci_now" "$bci_infra" 1 || return 1
  [ ! -s "$TMP/bci-notes" ] || return 1
  printf '%s\n' "$(($(date '+%s') - 4000))" >"$(watch_state_dir)/batch-ci.unread"
  bci_run completed failure "$bci_now" "$bci_infra" 1 || return 1
  grep -q 'unreadable for an hour' "$TMP/bci-notes" && ! grep -q 'run rerun' "$TMP/bci-calls"
)
check_ok "batch CI: GitHub being unreadable alerts after an hour and re-runs nothing" bci_unread

# ------------------------------------------------------------------ summary ---

printf '\n%d/%d checks passed\n' "$((total - fails))" "$total"
[ "$fails" -eq 0 ] || exit 1
exit 0

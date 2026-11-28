#!/usr/bin/env bash
# lib/guard.sh - the one choke point every model slot and check runs through.
# A slot runs with a throwaway HOME and, on macOS, under sandbox-exec: it may
# write only its own work folder, never the real home, /Volumes, TOOLS_DIR or
# belt.conf. There is no opt-out key and no env var. Bash 3.2 only.
# Requires: BELT_HOME (optional), SLOT_WRITE_ALLOW and TOOLS_DIR from belt.conf.

if [ -n "${BELT_GUARD_LOADED:-}" ]; then
  return 0
fi
BELT_GUARD_LOADED=1

guard_real_home() { # the passwd home of this user, never $HOME
  local h
  h=$(eval echo "~$(id -un)" 2>/dev/null) || h=""
  case "$h" in
    /*) printf '%s\n' "$h"; return 0 ;;
  esac
  return 1
}

guard_sandbox_probe() { # 0 usable, 1 nested, 2 unusable; the stderr decides
  local out
  GUARD_SANDBOX_PROBE_ERR=""
  command -v sandbox-exec >/dev/null 2>&1 || {
    GUARD_SANDBOX_PROBE_ERR="sandbox-exec is not on PATH"
    return 2
  }
  # capture only stderr: a working probe prints nothing, a nested one says
  # sandbox_apply: Operation not permitted, and anything else is broken
  if out=$(sandbox-exec -p '(version 1)(allow default)' true 2>&1 >/dev/null); then
    return 0
  fi
  GUARD_SANDBOX_PROBE_ERR=$out
  case "$out" in
    *sandbox_apply*) ;;
    *) return 2 ;;
  esac
  case "$out" in
    *"Operation not permitted"*) return 1 ;;
  esac
  return 2
}

guard_sandbox_usable() { # 0 when sandbox-exec can start a sandbox here
  local rc
  guard_sandbox_probe
  rc=$?
  [ "$rc" -eq 0 ]
}

guard_nested() { # 0 when we are already inside a sandbox (a nested one fails)
  local rc
  guard_sandbox_probe
  rc=$?
  [ "$rc" -eq 1 ]
}

guard_sb_str() { # guard_sb_str <path>; an SBPL string literal
  local p=${1:-}
  p=${p//\\/\\\\}
  p=${p//\"/\\\"}
  printf '"%s"' "$p"
}

guard_git_common_dir() { # guard_git_common_dir <dir>; printable absolute common dir
  local dir=${1:-} common
  [ -n "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 1
  [ -n "$common" ] || return 1
  case "$common" in
    /*) ;;
    *) common="$dir/$common" ;;
  esac
  physical_path "$common" 2>/dev/null
}

guard_dir_of() { # guard_dir_of <file>; the physical directory holding file
  local f=${1:-}
  [ -n "$f" ] || return 1
  physical_path "$(dirname "$f")" 2>/dev/null
}

guard_role_common_write() { # worker and on-call may write the git common dir
  case "${1:-}" in
    worker|oncall|check) return 0 ;;
  esac
  return 1
}

guard_role_harness_env() { # checks get no harness env, only GIT_CONFIG_GLOBAL
  case "${1:-}" in
    check) return 1 ;;
  esac
  return 0
}

guard_profile() { # guard_profile <role> <dir>; print the sandbox profile
  local role=${1:-worker} dir=${2:-} real sd common allow_common=0 proj pd od hb d had_f=0
  real=$(guard_real_home) || {
    warn "guard: cannot resolve the real home from passwd"
    return 1
  }
  [ -n "$dir" ] || { warn "guard: empty slot dir"; return 1; }
  sd=$(physical_path "$dir" 2>/dev/null) || sd=$dir
  # the common dir is computed for every role: the final deny always covers its
  # hooks and config, but only worker, on-call and checks may write it
  common=$(guard_git_common_dir "$dir") || common=""
  if [ -n "$common" ] && guard_role_common_write "$role"; then
    allow_common=1
  fi
  proj=""
  if [ -n "${PROJECT:-}" ]; then
    proj=$(physical_path "$PROJECT" 2>/dev/null) || proj=""
  fi
  pd=$(guard_dir_of "${BELT_PROMPT_FILE:-}") || pd=""
  od=$(guard_dir_of "${BELT_OUT_FILE:-}") || od=""
  hb=""
  if [ -n "${BELT_HOME:-}" ]; then
    hb=$(physical_path "$BELT_HOME" 2>/dev/null) || hb=""
  fi

  printf '(version 1)\n'
  printf '(allow default)\n'

  # nothing may write the real home or another volume ...
  printf '(deny file-write* (subpath %s) (subpath "/Volumes"))\n' \
    "$(guard_sb_str "$real")"
  # ... the secrets store may not even be read
  printf '(deny file-read* (subpath %s))\n' \
    "$(guard_sb_str "$real/.appstoreconnect")"
  # a model slot may not start a browser: under the throwaway HOME it finds no
  # keychain and puts a "Keychain Not Found" prompt on the owner's screen
  if [ "$role" != "check" ]; then
    printf '(deny process-exec (regex #"^/Applications/(Google Chrome|Chromium|Microsoft Edge|Brave Browser|Firefox)[^/]*\\.app/") (regex #"/(ms-playwright|puppeteer)/") (regex #"chrome-headless-shell"))\n'
  fi

  # ... except the slot's own work folder and the caches its tools need
  printf '(allow file-write*'
  printf ' (subpath %s)' "$(guard_sb_str "$sd")"
  if [ "$allow_common" = "1" ] && [ -n "$common" ]; then
    printf ' (subpath %s)' "$(guard_sb_str "$common")"
  fi
  for d in "$pd" "$od"; do
    [ -n "$d" ] && printf ' (subpath %s)' "$(guard_sb_str "$d")"
  done
  for d in .pi .claude .codex .cache .npm .swiftpm .cargo \
    Library/Caches Library/Developer Library/Logs; do
    if [ "$role" = "check" ]; then
      case "$d" in
        .pi|.claude|.codex) continue ;;
      esac
    fi
    printf ' (subpath %s)' "$(guard_sb_str "$real/$d")"
  done
  case "$-" in *f*) had_f=1 ;; esac
  set -f # SLOT_WRITE_ALLOW is a list of paths, never a glob
  for d in ${SLOT_WRITE_ALLOW:-}; do
    [ -n "$d" ] || continue
    local wp
    wp=$(physical_path "$d" 2>/dev/null) || wp=$d
    printf ' (subpath %s)' "$(guard_sb_str "$wp")"
  done
  [ "$had_f" -eq 1 ] || set +f
  printf ')\n'

  # the final deny: nothing below may be re-opened by a later rule
  printf '(deny file-write* (subpath %s) (subpath %s))\n' \
    "$(guard_sb_str "$real/Library/LaunchAgents")" \
    "$(guard_sb_str "$real/.appstoreconnect")"
  if [ -n "$hb" ]; then
    printf '(deny file-write* (subpath %s))\n' "$(guard_sb_str "$hb")"
    # ... except the slot's own folders inside it
    printf '(allow file-write* (subpath %s)' "$(guard_sb_str "$sd")"
    for d in "$pd" "$od"; do
      [ -n "$d" ] && printf ' (subpath %s)' "$(guard_sb_str "$d")"
    done
    printf ')\n'
  fi
  set -f
  for d in ${TOOLS_DIR:-}; do
    [ -n "$d" ] || continue
    local tp
    tp=$(physical_path "$d" 2>/dev/null) || tp=$d
    printf '(deny file-write* (subpath %s))\n' "$(guard_sb_str "$tp")"
  done
  [ "$had_f" -eq 1 ] || set +f
  # a slot may never rewrite the config belt is reading
  printf '(deny file-write* (literal %s))\n' "$(guard_sb_str "$sd/belt.conf")"
  if [ -n "$proj" ] && [ "$proj" != "$sd" ]; then
    printf '(deny file-write* (literal %s))\n' "$(guard_sb_str "$proj/belt.conf")"
  fi
  if [ -n "$common" ]; then
    # no slot may plant a hook or move core.hooksPath
    printf '(deny file-write* (subpath %s) (subpath %s))\n' \
      "$(guard_sb_str "$common/hooks")" "$(guard_sb_str "$common/config")"
  fi
  # .ssh is write-denied (git over ssh still reads it) ...
  printf '(deny file-write* (subpath %s))\n' "$(guard_sb_str "$real/.ssh")"
  # ... except the one file ssh has to add host keys to
  printf '(allow file-write* (literal %s) (literal %s))\n' \
    "$(guard_sb_str "$real/.ssh/known_hosts")" \
    "$(guard_sb_str "$real/.ssh/known_hosts.old")"
  # the very last rule: a role that may not write the common dir loses all of
  # it, wherever the project lives, so no earlier allow can win it back
  if [ -n "$common" ] && [ "$allow_common" != "1" ]; then
    printf '(deny file-write* (subpath %s))\n' "$(guard_sb_str "$common")"
  fi
  return 0
}

guard_exec() { # guard_exec <role> <dir> <cmd>
  # role: worker|reviewer|oncall|check. Runs cmd with bash -c inside dir, with a
  # throwaway HOME and the harness env, sandboxed unless CHECKS_UNSANDBOXED=1
  # (checks only) or we are already inside a sandbox. Fails closed when the
  # sandbox is unavailable.
  local role=${1:-worker} dir=${2:-} cmd=${3:-} real tmp rc use_sandbox=1 probe gh_token=""
  case "$role" in
    worker|reviewer|oncall|check) ;;
    *) role=worker ;;
  esac
  [ -n "$dir" ] && [ -n "$cmd" ] || { warn "guard: empty dir or command"; return 1; }
  real=$(guard_real_home) || {
    warn "guard: cannot resolve the real home from passwd; refusing to run"
    return 1
  }
  if [ "$role" = "check" ] && [ "${CHECKS_UNSANDBOXED:-0}" = "1" ]; then
    use_sandbox=0
  fi
  if [ "$use_sandbox" = "1" ]; then
    guard_sandbox_probe
    probe=$?
    if [ "$probe" -eq 1 ]; then
      # already inside a sandbox: a nested sandbox-exec cannot start. Only the
      # sandbox is dropped; the throwaway HOME and env still apply.
      use_sandbox=0
    elif [ "$probe" -ne 0 ]; then
      # a probe that failed for any other reason means the sandbox is broken;
      # never fall back to running the slot unsandboxed
      warn "guard: sandbox-exec cannot start a sandbox (${GUARD_SANDBOX_PROBE_ERR:-no detail}); refusing to run the $role slot"
      return 1
    fi
  fi
  # The slot's HOME is throwaway, so macOS keychain lookups cannot work there.
  # Read the on-call token now, while the real HOME still applies. A failed
  # lookup is not fatal: the slot simply gets no GitHub access. The token is
  # only ever an environment variable for that one slot, never printed or saved.
  if [ "$role" = "oncall" ]; then
    gh_token=$(gh auth token 2>/dev/null) || gh_token=""
  fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/belt-slot-home.XXXXXX" 2>/dev/null) || {
    warn "guard: cannot create a throwaway HOME; refusing to run"
    return 1
  }
  (
    GUARD_TMP_HOME=$tmp
    trap 'rm -rf "$GUARD_TMP_HOME"' EXIT
    trap 'exit 143' INT TERM HUP
    HOME=$tmp
    GIT_CONFIG_GLOBAL="$real/.gitconfig"
    GH_CONFIG_DIR="$real/.config/gh"
    export HOME GIT_CONFIG_GLOBAL GH_CONFIG_DIR
    # GitHub access belongs to the on-call slot only. Every other role loses
    # both token vars, and no slot inherits injected git config, so workers,
    # reviewers and checks cannot reach GitHub. belt does every gh write/push.
    # GIT_TERMINAL_PROMPT=0 is for every role: git must never sit on a prompt.
    unset GH_TOKEN GITHUB_TOKEN GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
      GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
    GIT_TERMINAL_PROMPT=0
    export GIT_TERMINAL_PROMPT
    if [ "$role" = "oncall" ] && [ -n "$gh_token" ]; then
      GH_TOKEN=$gh_token
      # The real git config has an osxkeychain helper, which hangs on `store`
      # under the throwaway HOME. An empty helper value resets the whole list,
      # so it must come first; the gh helper then handles the credential.
      GIT_CONFIG_COUNT=2
      GIT_CONFIG_KEY_0=credential.helper
      GIT_CONFIG_VALUE_0=''
      GIT_CONFIG_KEY_1=credential.helper
      GIT_CONFIG_VALUE_1='!gh auth git-credential'
      export GH_TOKEN GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
        GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
    fi
    if guard_role_harness_env "$role"; then
      PI_CODING_AGENT_DIR="$real/.pi/agent"
      CLAUDE_CONFIG_DIR="$real/.claude"
      CODEX_HOME="$real/.codex"
      export PI_CODING_AGENT_DIR CLAUDE_CONFIG_DIR CODEX_HOME
    else
      # checks get no harness env at all, not even one inherited from belt
      unset PI_CODING_AGENT_DIR CLAUDE_CONFIG_DIR CODEX_HOME
    fi
    cd "$dir" || exit 1
    if [ "$use_sandbox" = "1" ]; then
      guard_profile "$role" "$dir" >"$tmp/profile.sb" || exit 1
      sandbox-exec -f "$tmp/profile.sb" bash -c "$cmd"
    else
      bash -c "$cmd"
    fi
  )
  rc=$?
  rm -rf "$tmp" 2>/dev/null || true
  return $rc
}

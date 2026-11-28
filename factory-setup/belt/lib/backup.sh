#!/usr/bin/env bash
# lib/backup.sh - snapshot the project config and the owner's tools.
# Runs outside the sandbox: belt itself does the backup, no model is involved.
# A snapshot is never deleted to make room (no --delete); only the oldest
# snapshots beyond the newest 14 are pruned. Requires: PROJECT, SLUG,
# BACKUP_DIR, TOOLS_DIR, BELT_HOME.

backup_slug() { # the snapshot folder name: owner__repo, like the state dir
  printf '%s\n' "$(basename "$(state_dir_for "${SLUG:?}")")"
}

backup_state_dir() { state_dir_for "${SLUG:?}"; }
backup_marker() { printf '%s/backup.last\n' "$(backup_state_dir)"; }

backup_root() { # BACKUP_DIR/<slug>; 1 when BACKUP_DIR is empty
  [ -n "${BACKUP_DIR:-}" ] || return 1
  printf '%s/%s\n' "${BACKUP_DIR%/}" "$(backup_slug)"
}

backup_is_snapshot() { # <name>; YYYYMMDD-HHMM[-n]
  case "${1:-}" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]*) return 0 ;;
  esac
  return 1
}

backup_latest() { # <root>; newest snapshot dir, empty when there is none
  local root=${1:-} d had_f=0
  [ -d "$root" ] || return 0
  # the caller may have noglob on (TOOLS_DIR is data): a glob must expand here
  case "$-" in *f*) had_f=1; set +f ;; esac
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    backup_is_snapshot "$(basename "$d")" || continue
    printf '%s\n' "$d"
  done | sort | tail -n 1
  [ "$had_f" -eq 0 ] || set -f
}

backup_epoch() { # <file>; a non-negative epoch from the file, 0 when unusable
  local n
  n=$(cat "${1:-}" 2>/dev/null) || n=""
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

backup_due() { # 0 when the watch pass may run a backup (once per 24h)
  local last now
  last=$(backup_epoch "$(backup_marker)")
  now=$(date '+%s' 2>/dev/null) || now=0
  [ "$last" -eq 0 ] && return 0
  [ "$now" -ge "$last" ] || return 0
  [ $((now - last)) -ge 86400 ]
}

backup_mark() { # record the attempt time in BELT_HOME, whatever its outcome
  local f tmp
  f=$(backup_marker)
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  tmp="$f.tmp.$$"
  date '+%s' >"$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

backup_ping() { # <reason>; one deduped owner ping per slug
  local reason=${1:-backup failed}
  owner_notify_once "$(backup_state_dir)" "backup:$(backup_slug)" \
    "belt: backup for ${SLUG:-?}: $reason"
}

backup_dev() { # <path>; device number, empty when unknown
  local d
  if d=$(stat -c '%d' "$1" 2>/dev/null); then :
  elif d=$(stat -f '%d' "$1" 2>/dev/null); then :
  else return 0
  fi
  case "$d" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s\n' "$d"
}

backup_check_volume() { # warn when BACKUP_DIR sits on the same volume as a tools dir
  local root=${1:-} td rdev tdev
  [ -n "$root" ] && [ -d "$root" ] || return 0
  rdev=$(backup_dev "$root")
  [ -n "$rdev" ] || return 0
  set -f # TOOLS_DIR is a list of paths, never a glob
  for td in ${TOOLS_DIR:-}; do
    [ -n "$td" ] || continue
    [ -d "$td" ] || continue
    tdev=$(backup_dev "$td")
    [ -n "$tdev" ] || continue
    if [ "$tdev" = "$rdev" ]; then
      warn "backup: BACKUP_DIR and TOOLS_DIR ($td) are on the same volume"
    fi
  done
  set +f
  return 0
}

backup_excludes() { # <file>; rsync pattern list: secrets and bulk
  local f=${1:?} p
  : >"$f" || return 1
  for p in '*.env' '*.env.*' '.env' '.env.*' '.npmrc' '.netrc' \
    '.git-credentials' '*.p8' '*.pem' '.credentials*' '.runner' 'asc-secrets/' \
    '_work/' '_diag/' '*.log' 'worktrees/'; do
    printf '%s\n' "$p" >>"$f" || return 1
  done
  return 0
}

backup_rsync() { # backup_rsync <previous|""> <src> <dest> <excludes>
  local prev=${1:-} src=${2:?} dest=${3:?} excl=${4:?}
  if [ -n "$prev" ]; then
    rsync -a --link-dest="$prev" --exclude-from="$excl" "$src" "$dest"
  else
    rsync -a --exclude-from="$excl" "$src" "$dest"
  fi
}

backup_any_snapshot_has() { # <root> <relative-path>; 0 when an old snapshot holds it
  local root=${1:-} rel=${2:-} d had_f=0 rc=1
  [ -n "$rel" ] || return 1
  [ -d "$root" ] || return 1
  # the caller may have noglob on (TOOLS_DIR is data): a glob must expand here
  case "$-" in *f*) had_f=1; set +f ;; esac
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    backup_is_snapshot "$(basename "$d")" || continue
    if [ -e "$d/$rel" ]; then rc=0; break; fi
  done
  [ "$had_f" -eq 0 ] || set -f
  return $rc
}

backup_prune() { # <root> <keep>; delete only snapshots older than the newest <keep>
  local root=${1:?} keep=${2:-14} list drop n d had_f=0
  list=$(mktemp "${TMPDIR:-/tmp}/belt-backup-list.XXXXXX" 2>/dev/null) || return 0
  # the caller may have noglob on (TOOLS_DIR is data): a glob must expand here
  case "$-" in *f*) had_f=1; set +f ;; esac
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    backup_is_snapshot "$(basename "$d")" || continue
    printf '%s\n' "$d" >>"$list"
  done
  [ "$had_f" -eq 0 ] || set -f
  n=$(grep -c '' "$list" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt "$keep" ]; then
    drop=$((n - keep))
    sort "$list" | head -n "$drop" | while IFS= read -r d || [ -n "$d" ]; do
      [ -n "$d" ] || continue
      rm -rf "$d" 2>/dev/null || warn "backup: could not prune $d"
    done
  fi
  rm -f "$list" 2>/dev/null || true
  return 0
}

backup_run() { # one snapshot with the loaded config; 0 ok, 1 failed
  local root prev stamp dest n=2 tmp excl name td missing=0
  if [ -z "${BACKUP_DIR:-}" ]; then
    warn "backup: BACKUP_DIR is empty in belt.conf; nothing was backed up"
    backup_ping "BACKUP_DIR is not set"
    return 1
  fi
  if [ ! -f "$PROJECT/belt.conf" ]; then
    warn "backup: $PROJECT/belt.conf is missing; nothing was backed up"
    backup_ping "the project belt.conf is missing"
    backup_mark
    return 1
  fi
  root=$(backup_root) || return 1
  if ! mkdir -p "$root" 2>/dev/null; then
    warn "backup: cannot create $root"
    backup_ping "cannot create $root"
    backup_mark
    return 1
  fi
  backup_check_volume "$root"
  prev=$(backup_latest "$root")
  stamp=$(date '+%Y%m%d-%H%M' 2>/dev/null) || stamp=""
  case "$stamp" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]) ;;
    *)
      warn "backup: cannot read the clock"
      backup_ping "cannot read the clock"
      backup_mark
      return 1
      ;;
  esac
  dest="$root/$stamp"
  while [ -e "$dest" ]; do
    dest="$root/$stamp-$n"
    n=$((n + 1))
  done
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/belt-backup.XXXXXX" 2>/dev/null) || {
    warn "backup: cannot create a temp dir"
    backup_ping "cannot create a temp dir"
    backup_mark
    return 1
  }
  excl="$tmp/excludes"
  if ! backup_excludes "$excl" || ! mkdir -p "$dest" 2>/dev/null; then
    warn "backup: cannot prepare $dest"
    backup_ping "cannot prepare the snapshot"
    rm -rf "$tmp" "$dest" 2>/dev/null || true
    backup_mark
    return 1
  fi

  # the project's config is always in every snapshot
  if ! backup_rsync "$prev" "$PROJECT/belt.conf" "$dest/" "$excl" >>"$tmp/rsync.log" 2>&1; then
    warn "backup: could not copy belt.conf into $dest"
    backup_ping "could not copy belt.conf"
    rm -rf "$tmp" "$dest" 2>/dev/null || true
    backup_mark
    return 1
  fi
  if [ -f "$PROJECT/BELT.md" ] \
    && ! backup_rsync "$prev" "$PROJECT/BELT.md" "$dest/" "$excl" >>"$tmp/rsync.log" 2>&1; then
    warn "backup: could not copy BELT.md into $dest"
    backup_ping "could not copy BELT.md"
    rm -rf "$tmp" "$dest" 2>/dev/null || true
    backup_mark
    return 1
  fi

  set -f # TOOLS_DIR is a list of paths, never a glob
  for td in ${TOOLS_DIR:-}; do
    [ -n "$td" ] || continue
    name=$(basename "$td")
    if [ ! -d "$td" ] || [ -z "$(ls -A "$td" 2>/dev/null)" ]; then
      # the tools may be gone: never prune, and tell the owner
      backup_any_snapshot_has "$root" "tools/$name" && missing=1
      continue
    fi
    mkdir -p "$dest/tools/$name" 2>/dev/null || {
      warn "backup: cannot create $dest/tools/$name"
      backup_ping "cannot prepare the tools folder"
      rm -rf "$tmp" "$dest" 2>/dev/null || true
      set +f
      backup_mark
      return 1
    }
    if [ -n "$prev" ] && [ -d "$prev/tools/$name" ]; then
      backup_rsync "$prev/tools/$name" "$td/" "$dest/tools/$name/" "$excl" \
        >>"$tmp/rsync.log" 2>&1 || {
        warn "backup: could not copy $td into $dest"
        backup_ping "could not copy $td"
        rm -rf "$tmp" "$dest" 2>/dev/null || true
        set +f
        backup_mark
        return 1
      }
    else
      backup_rsync "" "$td/" "$dest/tools/$name/" "$excl" \
        >>"$tmp/rsync.log" 2>&1 || {
        warn "backup: could not copy $td into $dest"
        backup_ping "could not copy $td"
        rm -rf "$tmp" "$dest" 2>/dev/null || true
        set +f
        backup_mark
        return 1
      }
    fi
  done
  set +f

  rm -rf "$tmp" 2>/dev/null || true
  if [ "$missing" = "1" ]; then
    warn "backup: a TOOLS_DIR is missing or empty but a previous snapshot had it; not pruning"
    backup_ping "a TOOLS_DIR is missing or empty; the tools may be gone"
  else
    backup_prune "$root" 14
  fi
  log "backup: snapshot $dest"
  backup_mark
  return 0
}

backup_maybe() { # the watch pass: at most once per 24h, never fails the pass
  if [ -z "${BACKUP_DIR:-}" ]; then
    warn "backup: BACKUP_DIR is empty in belt.conf; no backup ran"
    backup_ping "BACKUP_DIR is not set"
    return 0
  fi
  backup_due || return 0
  backup_run || true
  return 0
}

cmd_backup() { # belt backup [project-dir]
  local dir=${1:-}
  load_config "${dir:-}" || die "could not load config (no belt.conf and BELT_PROJECT not set?)"
  SLUG=$(repo_slug) || die "could not resolve the repo slug (set REPO in belt.conf)"
  backup_run
}

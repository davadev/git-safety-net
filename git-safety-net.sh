#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DEFAULT_BASE="${HOME}/.git-safety-net"
DEFAULT_INTERVAL=180

QUIET=0
SETUP=0
ONCE=0
NO_ALIAS_SETUP=0

SOURCE_INPUT=""
BACKUP_INPUT=""
META_INPUT=""
INTERVAL_INPUT=""
EXPIRE_INPUT=""
NAME_INPUT=""

META_NAME=""
META_SOURCE=""
META_BACKUP=""
META_INTERVAL=""
META_EXPIRE_AT=""
META_LAST_RUN=""
META_LAST_COMMIT=""

LOCK_DIR=""

ONB_SOURCE=""
ONB_BACKUP_ROOT=""
ONB_INTERVAL=""
ONB_EXPIRE=""

EXCLUDE_DEFAULTS=(
  ".git/" ".venv/" "venv/" "env/" "node_modules/" "dist/" "build/" "target/" "out/"
  "__pycache__/" ".cache/" ".mypy_cache/" ".pytest_cache/" ".ruff_cache/"
  ".next/" ".nuxt/" ".svelte-kit/" "coverage/"
  "*.pyc" "*.pyo" "*.log" "*.tmp" "*.swp" "*.swo" "*.tsbuildinfo" ".DS_Store" "Thumbs.db"
)

USER_EXCLUDES=()

usage() {
  cat <<'EOF'
git-safety-net: protect a project with automatic hidden snapshots.

Usage:
  git-safety-net.sh [options]

Options:
  --help                 Show this help
  --setup                Run interactive setup
  --source PATH          Project directory (default: current directory)
  --backup PATH          Backup directory override
  --meta PATH            Metadata file override
  --interval SECONDS     Snapshot interval (default: 180)
  --expire VALUE         Expire at end-of-day, in duration (3h), or time string
  --once                 Run one sync pass and exit
  --exclude PATTERN      Extra exclude pattern (repeatable)
  --name NAME            Override derived project name
  --quiet                Reduce normal output
  --no-alias-setup       Skip alias prompt in setup

Examples:
  ./git-safety-net.sh
  ./git-safety-net.sh --source ~/code/backend
  ./git-safety-net.sh --expire 3h
  ./git-safety-net.sh --once
EOF
}

log() {
  if [ "$QUIET" -eq 0 ]; then
    printf '%s\n' "$*"
  fi
  return 0
}
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

iso_now() {
  local raw
  raw="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s:%s\n' "${raw%??}" "${raw#${raw%??}}"
}

epoch_now() { date '+%s'; }

epoch_to_iso() {
  local epoch="$1"
  local raw
  if date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z' >/dev/null 2>&1; then
    raw="$(date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z')"
  else
    raw="$(date -r "$epoch" '+%Y-%m-%dT%H:%M:%S%z')"
  fi
  printf '%s:%s\n' "${raw%??}" "${raw#${raw%??}}"
}

resolve_abs_dir() {
  local p="$1"
  [ -n "$p" ] || die "Path is empty"
  [ -d "$p" ] || die "Not a directory: $p"
  (cd "$p" >/dev/null 2>&1 && pwd -P)
}

resolve_abs_path() {
  local p="$1"
  [ -n "$p" ] || die "Path is empty"
  if [ -d "$p" ]; then
    (cd "$p" >/dev/null 2>&1 && pwd -P)
  else
    local d b
    d="$(dirname "$p")"
    b="$(basename "$p")"
    [ -d "$d" ] || die "Parent directory does not exist: $d"
    (cd "$d" >/dev/null 2>&1 && printf '%s/%s\n' "$(pwd -P)" "$b") || die "Could not resolve path: $p"
  fi
}

sanitize_name() {
  local s="$1"
  s="$(printf '%s' "$s" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
  [ -n "$s" ] || s="project"
  printf '%s\n' "$s"
}

derive_project_name() {
  local source="$1"
  local base hash
  base="$(sanitize_name "$(basename "$source")")"
  hash="$(printf '%s' "$source" | git hash-object --stdin | cut -c1-8)"
  printf '%s-%s\n' "$base" "$hash"
}

parse_absolute_time_to_epoch() {
  local in="$1"
  local out
  if out="$(date -d "$in" '+%s' 2>/dev/null)"; then printf '%s\n' "$out"; return 0; fi
  if out="$(date -j -f '%Y-%m-%d %H:%M:%S' "$in" '+%s' 2>/dev/null)"; then printf '%s\n' "$out"; return 0; fi
  if out="$(date -j -f '%Y-%m-%d %H:%M' "$in" '+%s' 2>/dev/null)"; then printf '%s\n' "$out"; return 0; fi
  if out="$(date -j -f '%Y-%m-%d' "$in" '+%s' 2>/dev/null)"; then printf '%s\n' "$out"; return 0; fi
  return 1
}

compute_expire_epoch() {
  local in="$1"
  local now
  now="$(epoch_now)"

  if [ -z "$in" ] || [ "$in" = "end-of-day" ] || [ "$in" = "eod" ]; then
    parse_absolute_time_to_epoch "$(date '+%Y-%m-%d') 23:59:59" || die "Cannot compute end-of-day"
    return 0
  fi

  if printf '%s' "$in" | grep -Eq '^[0-9]+$'; then
    printf '%s\n' "$((now + in))"
    return 0
  fi

  if printf '%s' "$in" | grep -Eq '^[0-9]+[smhd]$'; then
    local n unit mul
    n="${in%[smhd]}"
    unit="${in#$n}"
    mul=1
    [ "$unit" = "m" ] && mul=60
    [ "$unit" = "h" ] && mul=3600
    [ "$unit" = "d" ] && mul=86400
    printf '%s\n' "$((now + n * mul))"
    return 0
  fi

  parse_absolute_time_to_epoch "$in" || die "Invalid --expire value: $in"
}

is_within() {
  local child="$1"
  local parent="$2"
  [ "$child" = "$parent" ] && return 0
  case "$child" in "$parent"/*) return 0 ;; esac
  return 1
}

validate_paths() {
  local source="$1"
  local backup="$2"
  [ -d "$source" ] || die "Source directory does not exist: $source"
  mkdir -p "$(dirname "$backup")" || die "Cannot create backup parent"
  [ -w "$(dirname "$backup")" ] || die "Backup parent is not writable"
  if is_within "$backup" "$source"; then
    die "Invalid configuration: backup cannot be inside source"
  fi
  if is_within "$source" "$backup"; then
    die "Invalid configuration: source cannot be inside backup"
  fi
  return 0
}

load_metadata() {
  local file="$1"
  [ -f "$file" ] || return 1
  META_NAME=""; META_SOURCE=""; META_BACKUP=""; META_INTERVAL=""; META_EXPIRE_AT=""; META_LAST_RUN=""; META_LAST_COMMIT=""

  while IFS='=' read -r key value; do
    case "$key" in
      NAME) META_NAME="$value" ;;
      SOURCE) META_SOURCE="$value" ;;
      BACKUP) META_BACKUP="$value" ;;
      INTERVAL) META_INTERVAL="$value" ;;
      EXPIRE_AT) META_EXPIRE_AT="$value" ;;
      LAST_RUN) META_LAST_RUN="$value" ;;
      LAST_COMMIT) META_LAST_COMMIT="$value" ;;
    esac
  done < "$file"

  [ -n "$META_NAME" ] && [ -n "$META_SOURCE" ] && [ -n "$META_BACKUP" ]
}

write_metadata() {
  local file="$1" name="$2" source="$3" backup="$4" interval="$5" expire="$6" last_run="$7" last_commit="$8"
  local tmp
  mkdir -p "$(dirname "$file")"
  tmp="${file}.tmp.$$"
  {
    printf 'NAME=%s\n' "$name"
    printf 'SOURCE=%s\n' "$source"
    printf 'BACKUP=%s\n' "$backup"
    printf 'INTERVAL=%s\n' "$interval"
    printf 'EXPIRE_AT=%s\n' "$expire"
    printf 'LAST_RUN=%s\n' "$last_run"
    printf 'LAST_COMMIT=%s\n' "$last_commit"
  } > "$tmp"
  mv "$tmp" "$file"
}

detect_rc_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  if [ "$shell_name" = "zsh" ] && [ -f "${HOME}/.zshrc" ]; then printf '%s\n' "${HOME}/.zshrc"; return; fi
  if [ "$shell_name" = "bash" ] && [ -f "${HOME}/.bashrc" ]; then printf '%s\n' "${HOME}/.bashrc"; return; fi
  [ -f "${HOME}/.zshrc" ] && { printf '%s\n' "${HOME}/.zshrc"; return; }
  [ -f "${HOME}/.bashrc" ] && { printf '%s\n' "${HOME}/.bashrc"; return; }
  [ -f "${HOME}/.profile" ] && { printf '%s\n' "${HOME}/.profile"; return; }
  printf '%s\n' "${HOME}/.profile"
}

setup_aliases() {
  local rc="$1"
  mkdir -p "$(dirname "$rc")"
  touch "$rc"
  if grep -Fq '>>> git-safety-net aliases >>>' "$rc"; then
    log "Aliases already present in $rc"
    return
  fi
  {
    printf '\n# >>> git-safety-net aliases >>>\n'
    printf "alias gsn='bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/main/git-safety-net.sh)'\n"
    printf "alias gsnr='bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/main/git-safety-net-restore.sh)'\n"
    printf '# <<< git-safety-net aliases <<<\n'
  } >> "$rc"
  log "Alias added to $rc"
  log "Reload your shell config or open a new terminal."
}

prompt_yes_no() {
  local prompt="$1" default_yes="$2" answer
  while true; do
    [ "$default_yes" = "yes" ] && printf '%s [Y/n]: ' "$prompt" || printf '%s [y/N]: ' "$prompt"
    read -r answer || return 1
    case "${answer:-}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      '') [ "$default_yes" = "yes" ] && return 0 || return 1 ;;
      *) printf 'Please answer yes or no.\n' ;;
    esac
  done
}

run_onboarding() {
  local source_default="$1"
  local interval_default="$2"
  local source_in root_in interval_in expire_in add_aliases rc

  printf 'Welcome to git-safety-net.\n\n'
  printf 'Project directory to protect [%s]: ' "$source_default"
  read -r source_in || die "Input aborted"
  ONB_SOURCE="$(resolve_abs_dir "${source_in:-$source_default}")"

  printf 'Hidden backup root [%s]: ' "$DEFAULT_BASE"
  read -r root_in || die "Input aborted"
  ONB_BACKUP_ROOT="$(resolve_abs_path "${root_in:-$DEFAULT_BASE}")"

  add_aliases="no"
  if [ "$NO_ALIAS_SETUP" -eq 0 ] && prompt_yes_no "Add gsn/gsnr aliases to your shell config?" "yes"; then
    add_aliases="yes"
  fi

  printf 'Snapshot interval in seconds [%s]: ' "$interval_default"
  read -r interval_in || die "Input aborted"
  ONB_INTERVAL="${interval_in:-$interval_default}"

  printf 'Expiration (empty for end-of-day, e.g. 3h) [end-of-day]: '
  read -r expire_in || die "Input aborted"
  ONB_EXPIRE="${expire_in:-}"

  printf '\nSetup summary:\n'
  printf '  Source:   %s\n' "$ONB_SOURCE"
  printf '  Root:     %s\n' "$ONB_BACKUP_ROOT"
  printf '  Interval: %s seconds\n' "$ONB_INTERVAL"
  [ -n "$ONB_EXPIRE" ] && printf '  Expire:   %s\n' "$ONB_EXPIRE" || printf '  Expire:   end of local day\n'
  printf '  Aliases:  %s\n' "$add_aliases"

  prompt_yes_no "Start protection now?" "yes" || die "Setup cancelled"
  if [ "$add_aliases" = "yes" ]; then
    rc="$(detect_rc_file)"
    setup_aliases "$rc"
  fi
}

init_backup_repo() {
  local backup="$1"
  mkdir -p "$backup"
  [ -d "$backup/.git" ] || git -C "$backup" init -q
}

acquire_lock() {
  local d="$1" pid_file="$1/pid"
  if mkdir "$d" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file"
    LOCK_DIR="$d"
    return 0
  fi
  if [ -f "$pid_file" ]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      die "Another watcher is already running for this project (pid $pid)."
    fi
  fi
  warn "Found stale lock, recovering: $d"
  rm -rf "$d"
  mkdir "$d" || die "Could not create lock: $d"
  printf '%s\n' "$$" > "$pid_file"
  LOCK_DIR="$d"
}

release_lock() { [ -n "$LOCK_DIR" ] && [ -d "$LOCK_DIR" ] && rm -rf "$LOCK_DIR"; }

sync_once() {
  local source="$1" backup="$2" meta="$3" name="$4" interval="$5" expire_iso="$6"
  shift 6
  local extra excludes status_text now commit_id prev_commit

  excludes=("${EXCLUDE_DEFAULTS[@]}")
  for extra in "$@"; do excludes+=("$extra"); done

  local rsync_args
  rsync_args=( -a --delete --filter=':- .gitignore' )
  for extra in "${excludes[@]}"; do rsync_args+=("--exclude=${extra}"); done
  rsync_args+=("${source}/" "${backup}/")
  rsync "${rsync_args[@]}"

  git -C "$backup" add -A
  now="$(iso_now)"

  if git -C "$backup" diff --cached --quiet; then
    prev_commit="$(git -C "$backup" rev-parse --short HEAD 2>/dev/null || true)"
    write_metadata "$meta" "$name" "$source" "$backup" "$interval" "$expire_iso" "$now" "$prev_commit"
    log "No changes detected, skipping snapshot"
    return 0
  fi

  status_text="$(git -C "$backup" status --porcelain | LC_ALL=C sort)"
  {
    printf 'snapshot: %s\n\n' "$now"
    printf '%s\n' "$status_text"
  } | git -C "$backup" commit -q -F -

  commit_id="$(git -C "$backup" rev-parse --short HEAD)"
  write_metadata "$meta" "$name" "$source" "$backup" "$interval" "$expire_iso" "$now" "$commit_id"
  log "Snapshot created at $now"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --setup) SETUP=1 ;;
      --source) [ "$#" -ge 2 ] || die "--source requires a value"; SOURCE_INPUT="$2"; shift ;;
      --backup) [ "$#" -ge 2 ] || die "--backup requires a value"; BACKUP_INPUT="$2"; shift ;;
      --meta) [ "$#" -ge 2 ] || die "--meta requires a value"; META_INPUT="$2"; shift ;;
      --interval) [ "$#" -ge 2 ] || die "--interval requires a value"; INTERVAL_INPUT="$2"; shift ;;
      --expire) [ "$#" -ge 2 ] || die "--expire requires a value"; EXPIRE_INPUT="$2"; shift ;;
      --once) ONCE=1 ;;
      --exclude) [ "$#" -ge 2 ] || die "--exclude requires a value"; USER_EXCLUDES+=("$2"); shift ;;
      --name) [ "$#" -ge 2 ] || die "--name requires a value"; NAME_INPUT="$2"; shift ;;
      --quiet) QUIET=1 ;;
      --no-alias-setup) NO_ALIAS_SETUP=1 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  require_cmd git
  require_cmd rsync

  parse_args "$@"

  local source name meta_path backup interval expire_input expire_epoch expire_iso
  local source_guess
  source_guess="$(resolve_abs_dir "${SOURCE_INPUT:-.}")"
  name="${NAME_INPUT:-$(derive_project_name "$source_guess")}" 

  mkdir -p "$DEFAULT_BASE"
  meta_path="${META_INPUT:-$DEFAULT_BASE/$name.env}"
  meta_path="$(resolve_abs_path "$meta_path")"

  if load_metadata "$meta_path" && [ "$SETUP" -eq 0 ]; then
    source="$META_SOURCE"
    backup="$META_BACKUP"
    interval="${META_INTERVAL:-$DEFAULT_INTERVAL}"

    [ -n "$SOURCE_INPUT" ] && source="$source_guess"
    [ -n "$BACKUP_INPUT" ] && backup="$(resolve_abs_path "$BACKUP_INPUT")"
    [ -n "$INTERVAL_INPUT" ] && interval="$INTERVAL_INPUT"
    expire_input="$EXPIRE_INPUT"
    name="$META_NAME"
  else
    run_onboarding "$source_guess" "${INTERVAL_INPUT:-$DEFAULT_INTERVAL}"

    source="$ONB_SOURCE"
    [ -n "$NAME_INPUT" ] && name="$NAME_INPUT" || name="$(derive_project_name "$source")"
    backup="${BACKUP_INPUT:-$ONB_BACKUP_ROOT/$name}"
    backup="$(resolve_abs_path "$backup")"
    interval="${ONB_INTERVAL:-$DEFAULT_INTERVAL}"
    expire_input="${EXPIRE_INPUT:-$ONB_EXPIRE}"
    meta_path="${META_INPUT:-$DEFAULT_BASE/$name.env}"
    meta_path="$(resolve_abs_path "$meta_path")"
  fi

  printf '%s' "$interval" | grep -Eq '^[0-9]+$' || die "Interval must be an integer in seconds"
  [ "$interval" -gt 0 ] || die "Interval must be greater than zero"

  source="$(resolve_abs_dir "$source")"
  backup="$(resolve_abs_path "$backup")"
  validate_paths "$source" "$backup"
  init_backup_repo "$backup"

  expire_epoch="$(compute_expire_epoch "$expire_input")"
  expire_iso="$(epoch_to_iso "$expire_epoch")"

  acquire_lock "$DEFAULT_BASE/$name.lock"
  trap 'release_lock; log "Stopped."; exit 0' INT TERM
  trap 'release_lock' EXIT

  log "Protecting project: $source"
  log "Hidden backup store: $backup"
  log "Interval: ${interval}s"
  log "Expiration: $expire_iso"

  while true; do
    [ "$(epoch_now)" -ge "$expire_epoch" ] && { log "Stopping: expiration time reached"; break; }
    sync_once "$source" "$backup" "$meta_path" "$name" "$interval" "$expire_iso" "${USER_EXCLUDES[@]}"
    [ "$ONCE" -eq 1 ] && break
    [ "$(epoch_now)" -ge "$expire_epoch" ] && { log "Stopping: expiration time reached"; break; }
    sleep "$interval"
  done
}

main "$@"

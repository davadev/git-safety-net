#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DEFAULT_BASE="${HOME}/.git-safety-net"

SOURCE_INPUT=""
META_INPUT=""
FILE_INPUT=""
TIME_INPUT=""
DRY_RUN=0
LIST_MODE=0
LIST_FILES_MODE=0
RESTORE_ALL_MODE=0
FORCE=0

META_NAME=""
META_SOURCE=""
META_BACKUP=""

usage() {
  cat <<'EOF'
git-safety-net-restore: restore one file from protected history by time.

Usage:
  git-safety-net-restore.sh [options]

Options:
  --help               Show this help
  --source PATH        Project directory (default: current directory)
  --meta PATH          Metadata file override
  --file RELATIVE_PATH File to restore from history
  --time VALUE         Restore file as of this time (default: latest snapshot)
  --dry-run            Show what would be restored
  --list               Show recent snapshot times
  --list-files         List files in selected snapshot
  --restore-all        Restore full project tree from snapshot (requires --force)
  --force              Overwrite an existing different file

Examples:
  ./git-safety-net-restore.sh --list
  ./git-safety-net-restore.sh --file src/auth.py --time "2026-04-01 14:30"
  ./git-safety-net-restore.sh --source ~/code/backend --file app/main.py --dry-run
  ./git-safety-net-restore.sh --list-files --time "2026-04-01 14:30"
  ./git-safety-net-restore.sh --restore-all --time "2026-04-01 14:30" --dry-run
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

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

load_metadata() {
  local file="$1"
  [ -f "$file" ] || return 1
  META_NAME=""; META_SOURCE=""; META_BACKUP=""
  while IFS='=' read -r key value; do
    case "$key" in
      NAME) META_NAME="$value" ;;
      SOURCE) META_SOURCE="$value" ;;
      BACKUP) META_BACKUP="$value" ;;
    esac
  done < "$file"
  [ -n "$META_NAME" ] && [ -n "$META_SOURCE" ] && [ -n "$META_BACKUP" ]
}

validate_relative_file() {
  local f="$1"
  local segment
  local -a segments
  [ -n "$f" ] || die "--file is required unless --list is used"
  case "$f" in
    /*) die "--file must be relative to the source project" ;;
  esac

  IFS='/' read -r -a segments <<< "$f"
  for segment in "${segments[@]}"; do
    if [ "$segment" = ".." ]; then
      die "--file cannot contain parent traversal"
    fi
  done
  return 0
}

find_commit_for_time() {
  local backup="$1" time_value="$2"
  local commit
  if [ -z "$time_value" ]; then
    commit="$(git -C "$backup" rev-parse HEAD 2>/dev/null || true)"
  else
    commit="$(git -C "$backup" rev-list -1 --before="$time_value" HEAD 2>/dev/null || true)"
  fi
  [ -n "$commit" ] || return 1
  printf '%s\n' "$commit"
}

print_selected_snapshot() {
  local backup="$1"
  local commit="$2"
  local commit_time="$3"
  local short
  short="$(git -C "$backup" rev-parse --short "$commit")"
  log "Selected snapshot: $commit_time ($short)"
  if [ -n "$TIME_INPUT" ]; then
    log "Note: restore uses the latest snapshot at or before the requested time."
  fi
}

restore_all() {
  local backup="$1"
  local source="$2"
  local commit="$3"
  local commit_time="$4"
  local short
  local tmp_dir
  local file_count

  require_cmd rsync
  require_cmd tar

  short="$(git -C "$backup" rev-parse --short "$commit")"

  if [ "$FORCE" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
    die "Refusing full-project restore without --force. Use --dry-run to preview or --force to apply."
  fi

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/gsnr.XXXXXX")"

  git -C "$backup" archive "$commit" | tar -x -C "$tmp_dir"
  file_count="$(git -C "$backup" ls-tree -r --name-only "$commit" | wc -l | tr -d ' ')"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run: would restore full project tree from snapshot at $commit_time ($short)"
    log "Dry run: snapshot contains $file_count files"
    rsync -a --delete --dry-run "$tmp_dir/" "$source/" >/dev/null
    rm -rf "$tmp_dir"
    return 0
  fi

  rsync -a --delete "$tmp_dir/" "$source/"
  rm -rf "$tmp_dir"
  log "Restored project tree from snapshot at $commit_time ($short)"
  log "Restored files: $file_count"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --source) [ "$#" -ge 2 ] || die "--source requires a value"; SOURCE_INPUT="$2"; shift ;;
      --meta) [ "$#" -ge 2 ] || die "--meta requires a value"; META_INPUT="$2"; shift ;;
      --file) [ "$#" -ge 2 ] || die "--file requires a value"; FILE_INPUT="$2"; shift ;;
      --time) [ "$#" -ge 2 ] || die "--time requires a value"; TIME_INPUT="$2"; shift ;;
      --dry-run) DRY_RUN=1 ;;
      --list) LIST_MODE=1 ;;
      --list-files) LIST_FILES_MODE=1 ;;
      --restore-all|-a) RESTORE_ALL_MODE=1 ;;
      --force) FORCE=1 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  require_cmd git
  parse_args "$@"

  local source name meta backup commit commit_time target
  source="$(resolve_abs_dir "${SOURCE_INPUT:-.}")"

  if [ -n "$META_INPUT" ]; then
    meta="$(resolve_abs_path "$META_INPUT")"
  else
    name="$(derive_project_name "$source")"
    meta="$DEFAULT_BASE/$name.env"
  fi

  load_metadata "$meta" || die "Metadata not found or invalid: $meta"
  [ "$META_SOURCE" = "$source" ] || die "Metadata source does not match --source: $META_SOURCE"

  backup="$(resolve_abs_path "$META_BACKUP")"
  [ -d "$backup/.git" ] || die "Backup repository is missing: $backup"

  if [ "$LIST_MODE" -eq 1 ]; then
    log "Recent snapshots for $source"
    git -C "$backup" log -n 20 --date=local --pretty=format:'- %ad' || true
    exit 0
  fi

  commit="$(find_commit_for_time "$backup" "$TIME_INPUT" || true)"
  [ -n "$commit" ] || die "No snapshot found at or before requested time"
  commit_time="$(git -C "$backup" show -s --date=local --format='%ad' "$commit")"

  if [ "$LIST_FILES_MODE" -eq 1 ]; then
    git -C "$backup" ls-tree -r --name-only "$commit" | LC_ALL=C sort
    exit 0
  fi

  print_selected_snapshot "$backup" "$commit" "$commit_time"

  if [ "$RESTORE_ALL_MODE" -eq 1 ]; then
    restore_all "$backup" "$source" "$commit" "$commit_time"
    exit 0
  fi

  validate_relative_file "$FILE_INPUT"

  if ! git -C "$backup" cat-file -e "$commit:$FILE_INPUT" 2>/dev/null; then
    die "File '$FILE_INPUT' did not exist in the selected snapshot. Use --list-files or try a different --time."
  fi

  target="$source/$FILE_INPUT"
  log "Restoring $FILE_INPUT as it existed at $commit_time"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run: would write to $target"
    exit 0
  fi

  mkdir -p "$(dirname "$target")"
  local tmp
  tmp="${target}.tmp.$$"
  git -C "$backup" show "$commit:$FILE_INPUT" > "$tmp"

  if [ -f "$target" ] && [ "$FORCE" -ne 1 ]; then
    if cmp -s "$target" "$tmp"; then
      rm -f "$tmp"
      log "Current file already matches the selected snapshot; nothing to restore"
      exit 0
    fi
    rm -f "$tmp"
    die "Refusing to overwrite existing file: $target (use --force to overwrite)"
  fi

  mv "$tmp" "$target"
  log "Restored to $target"
}

main "$@"

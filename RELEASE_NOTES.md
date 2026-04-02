# Release Notes

## v1.0.4

### Highlights

- `gsnr` now supports full-project snapshot restore with `--restore-all`.
- `gsnr --list-files` lists files available in the selected snapshot.
- Restore messaging now shows selected snapshot timestamp and commit short hash.

### Safety

- Full-project restore is exact (includes deletions) and requires `--force` to apply.
- `--dry-run` is supported for both single-file and full-project restore.

## v1.0.3

### Fixes

- macOS Bash 3.2 compatibility fix for empty `USER_EXCLUDES` with `set -u`.
- `gsn` now starts normally when no `--exclude` flags are provided.

### Notes

- No changes to snapshot, restore, retention, locking, onboarding flow, or backup format.

## v1.0.2

### Highlights

- Setup alias mode now defaults to local install for stronger onboarding trust.
- `--setup` supports switching alias target mode between:
  - local scripts under `~/.git-safety-net/`
  - remote GitHub/raw execution

### Notes

- Core backup/watch/restore behavior is unchanged.
- Alias block remains update-in-place and reusable on setup reruns.

## v1.0.1

### Highlights

- Setup now includes alias target mode selection:
  - `remote` (most convenient): aliases execute via GitHub raw URL
  - `local`: aliases execute local installed scripts in `~/.git-safety-net/bin/`
- `--setup` can be rerun anytime to switch alias modes cleanly.

### Notes

- Existing backup/snapshot/restore core behavior is unchanged.
- Alias block remains idempotent and is updated in place when setup is rerun.

## v1.0.0

### Highlights

- Tiny Bash safety net for coding projects with two commands:
  - `gsn` to protect a project with automatic hidden snapshots
  - `gsnr` to restore one file by time
- First-run usage is curl-friendly and onboarding can add aliases automatically.
- Persistent local state is kept under `~/.git-safety-net/`.
- Source project Git is never touched (`.git/` is always excluded from sync).

### What's Included

- Automatic snapshot loop with interval + expiration support
- Per-project lock handling for safe parallel usage
- Restore UX with:
  - `--list` for recent snapshot times
  - `--dry-run` preview mode
  - overwrite guard requiring `--force` to replace a different existing file

### Stable Curl URLs (v1.0.0)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.0/git-safety-net.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.0/git-safety-net-restore.sh) --file src/auth.py --time "2026-04-01 14:30"
```

## Highlights

- Tiny Bash safety net for coding projects with two commands:
  - `gsn` to protect a project with automatic hidden snapshots
  - `gsnr` to restore one file by time
- First-run usage is curl-friendly and onboarding can add aliases automatically.
- Persistent local state is kept under `~/.git-safety-net/`.
- Source project Git is never touched (`.git/` is always excluded from sync).

## What's Included

- Automatic snapshot loop with interval + expiration support
- Per-project lock handling for safe parallel usage
- Restore UX with:
  - `--list` for recent snapshot times
  - `--dry-run` preview mode
  - overwrite guard requiring `--force` to replace a different existing file

## Stable Curl URLs (v1.0.0)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.0/git-safety-net.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.0/git-safety-net-restore.sh) --file src/auth.py --time "2026-04-01 14:30"
```

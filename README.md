# git-safety-net

`git-safety-net` is a tiny, production-minded Bash utility that protects coding projects with automatic local snapshots.

Many projects already have their own Git repositories, but modern LLM-assisted workflows introduce a new risk profile: an agent can accidentally perform a destructive action, rewrite history, or simply work for long stretches without committing. `git-safety-net` adds a separate, hidden, continuously-updated safety layer so you can recover file state by time even when the main project repo becomes messy or damaged.

It has two scripts:

- `git-safety-net.sh` (`gsn`): protect a project and keep snapshots up to date.
- `git-safety-net-restore.sh` (`gsnr`): restore one file as it existed at a chosen time.

You interact with it as **protect** and **restore by time**. Git is used internally, but hidden from normal usage.

First-time usage is meant to start directly from `curl` against this repository.

## Why use it

- very small: Bash + `git` + `rsync`
- local-first: no cloud account, no daemon, no database
- safe by default: source project Git is never touched
- efficient: incremental sync, commits only when files changed
- easy to trust: plain files, readable metadata

## Quick start

First use is intentionally one-off via `curl` from this repository. From the project you want to protect, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.3/git-safety-net.sh)
```

That first run starts onboarding and can optionally install `gsn` / `gsnr` aliases in your shell rc so future use is shorter.

If you already have the script locally, you can also run:

```bash
./git-safety-net.sh
```

On first run, onboarding asks you to confirm source path, backup root, interval, expiration, and optional aliases.

Then restore a file by time:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.3/git-safety-net-restore.sh) --file src/auth.py --time "2026-04-01 14:30"
```

## Remote-use model (curl-friendly)

These scripts are designed to be fetched on demand (no permanent installation required).

Example aliases:

```bash
alias gsn='bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.3/git-safety-net.sh)'
alias gsnr='bash <(curl -fsSL https://raw.githubusercontent.com/davadev/git-safety-net/v1.0.3/git-safety-net-restore.sh)'
```

`gsn` can add aliases automatically during onboarding (idempotently, in a marked block).
Setup now lets you choose alias mode: remote URL (most convenient) or local installed scripts under `~/.git-safety-net/`.
You can rerun `--setup` later to switch alias mode.

## Typical workflow

1. Start protection once from `curl` (or use `gsn` alias after onboarding).
2. Keep coding while snapshots are recorded in the hidden store.
3. Use `gsnr --list`, then restore a specific file by time when needed.

## Default local storage

By default, all persistent data is under:

`~/.git-safety-net/`

Per protected project (example `backend-a1b2c3d4`):

- hidden backup repo: `~/.git-safety-net/backend-a1b2c3d4/`
- metadata file: `~/.git-safety-net/backend-a1b2c3d4.env`
- lock directory: `~/.git-safety-net/backend-a1b2c3d4.lock`

Only these artifacts are persisted, plus optional alias lines in your shell rc.

## First-run onboarding behavior

Onboarding runs when metadata is missing for the project (or when `--setup` is passed):

1. confirm project directory (default: current directory)
2. confirm hidden backup root (default: `~/.git-safety-net`)
3. choose alias auto-setup (`gsn`, `gsnr`)
4. confirm interval (default: `180` seconds)
5. confirm expiration (default: end of local day)
6. review and confirm summary before starting

After onboarding, normal runs are non-interactive.

## Safety model

- never runs Git in your source project
- always excludes source `.git/` from sync
- backup repository is fully separate and hidden
- rejects unsafe path relationships (source inside backup, backup inside source)
- per-project lock prevents duplicate watchers for the same project
- different projects can be watched in parallel

## Snapshot behavior

- source files sync into hidden backup via `rsync --delete`
- `.gitignore` is used as an exclusion source where practical
- common build/cache/junk paths are excluded by default
- extra excludes can be added with repeatable `--exclude`
- snapshot commit is created only when changes exist
- no-op runs clearly report: "No changes detected, skipping snapshot"

## Restore behavior

`gsnr` restores one file, from the latest snapshot at or before your requested time.

- `--list` shows recent snapshot times
- `--list` shows recent snapshot times in local time
- `--dry-run` previews what would be restored
- restore refuses to overwrite an existing different file unless `--force` is passed
- restore does not mutate the hidden backup repo
- if file did not exist at that time, you get a clear message and no write occurs

Safety default: restore will not overwrite a different existing file unless you pass `--force`.

## Common commands

Protect current directory:

```bash
./git-safety-net.sh
```

Protect another directory:

```bash
./git-safety-net.sh --source ~/code/backend
```

Protect for 3 hours:

```bash
./git-safety-net.sh --expire 3h
```

Single run (no loop):

```bash
./git-safety-net.sh --once
```

Re-run interactive setup:

```bash
./git-safety-net.sh --setup
```

List recent snapshots:

```bash
./git-safety-net-restore.sh --list
```

Restore one file by time:

```bash
./git-safety-net-restore.sh --file src/auth.py --time "2026-04-01 14:30"
```

Dry-run restore:

```bash
./git-safety-net-restore.sh --file src/auth.py --time "2026-04-01 14:30" --dry-run
```

Force overwrite during restore:

```bash
./git-safety-net-restore.sh --file src/auth.py --time "2026-04-01 14:30" --force
```

## Requirements

- Bash (macOS or Linux)
- `git`
- `rsync`

## Notes

- Hidden Git is an implementation detail for reliable snapshots.
- You do not need commit hashes or Git commands to use the tool.
- Your source project's existing Git history remains untouched.

## Troubleshooting

- `Another watcher is already running...` means a watcher lock exists for that project.
- Stop the other watcher (Ctrl+C in its terminal) and run again.
- If a watcher crashed, rerun `gsn`; stale lock recovery is handled automatically.

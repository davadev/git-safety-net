# git-safety-net

`git-safety-net` is a tiny Bash safety net for coding projects.

It gives you two commands:

- `gsn` (`git-safety-net.sh`): protect a project by syncing it into a hidden store and recording snapshots.
- `gsnr` (`git-safety-net-restore.sh`): restore one file as it existed at a chosen time.

You use it in plain language (protect/restore by time). Hidden Git is used internally as an implementation detail.

## Remote-use model

The scripts are designed for curl-based usage; they do not need permanent installation.

Example aliases:

```bash
alias gsn='bash <(curl -fsSL https://example.com/git-safety-net.sh)'
alias gsnr='bash <(curl -fsSL https://example.com/git-safety-net-restore.sh)'
```

On first run, `gsn` can add these aliases to your shell rc file for you.

## First-run onboarding

When project metadata does not exist yet (or if `--setup` is passed), `gsn` runs interactive onboarding:

1. pick project directory (default: current directory)
2. confirm hidden backup root (default: `~/.git-safety-net`)
3. choose whether aliases should be added
4. confirm interval (default: `180` seconds)
5. confirm expiration (default: end of local day)
6. review summary and confirm start

After onboarding, normal runs are non-interactive.

## Local persistence

By default, persistent state lives under:

`~/.git-safety-net/`

Per project (example `backend-a1b2c3d4`):

- hidden backup repo: `~/.git-safety-net/backend-a1b2c3d4/`
- metadata file: `~/.git-safety-net/backend-a1b2c3d4.env`
- lock directory: `~/.git-safety-net/backend-a1b2c3d4.lock`

No files are written into your source project.

## Important behavior

- source project `.git` is never touched
- source `.git/` is always excluded from syncing
- hidden backup repo is fully separate from your project git
- snapshots are created only when files changed
- restore writes only the requested file

## Example commands

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

Run one sync pass only:

```bash
./git-safety-net.sh --once
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

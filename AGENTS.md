# AGENTS

## Working with git (git-safety-net)

- Keep changes minimal and scoped to the request.
- Do not refactor unrelated code.
- Run quick checks before commit:
  - `bash -n git-safety-net.sh`
  - `bash -n git-safety-net-restore.sh`
- Use clear commit messages focused on intent.
- Never use destructive git commands unless explicitly requested.

## Release flow

1. Ensure `main` is clean and up to date.
2. Run pre-release checks:
   - `bash -n git-safety-net.sh`
   - `bash -n git-safety-net-restore.sh`
   - `./git-safety-net.sh --help`
   - `./git-safety-net-restore.sh --help`
3. Create a temporary test project (never use a real project):
   - `TEST_DIR="$HOME/Documents/gsn-release-test-$(date +%Y%m%d-%H%M%S)"`
   - `mkdir -p "$TEST_DIR"`
4. Run functional smoke tests on that project:
   - optionally create a tiny mutator to generate changes while watcher runs:
     - `cat > "$TEST_DIR/mutate.sh" <<'EOF'`
     - `#!/usr/bin/env bash`
     - `set -euo pipefail`
     - `for i in 1 2 3; do`
     - `  printf 'tick=%s time=%s\n' "$i" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$TEST_DIR/state.txt"`
     - `  sleep 30`
     - `done`
     - `EOF`
     - `chmod +x "$TEST_DIR/mutate.sh"`
   - one watcher run (`--once` or short expiry)
   - `gsnr --list`
   - restore dry-run (`--dry-run`)
5. Clean up test artifacts after testing:
   - remove the test directory in `~/Documents`
   - remove matching `~/.git-safety-net/<name>/`, `.env`, and `.lock` for that test project
6. Bump patch version references (README/script URLs/release notes) only as needed.
7. Commit and push:
   - `git add ...`
   - `git commit -m "<message>"`
   - `git push`
8. Create and push annotated tag:
   - `git tag -a vX.Y.Z -m "git-safety-net vX.Y.Z"`
   - `git push origin vX.Y.Z`
9. Publish GitHub release:
   - `gh release create vX.Y.Z --title "git-safety-net vX.Y.Z" --notes-file RELEASE_NOTES.md`

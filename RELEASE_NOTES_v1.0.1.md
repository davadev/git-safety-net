## Highlights

- Setup now includes alias target mode selection:
  - `remote` (most convenient): aliases execute via GitHub raw URL
  - `local`: aliases execute local installed scripts in `~/.git-safety-net/bin/`
- `--setup` can be rerun anytime to switch alias modes cleanly.

## Notes

- Existing backup/snapshot/restore core behavior is unchanged.
- Alias block remains idempotent and is updated in place when setup is rerun.

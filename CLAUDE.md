# slate-bridge-mac

A macOS menu-bar app that writes calendars and contacts into a Slate vault as
Markdown. **Read `docs/PLAN.md` first.** It holds the decisions and the
progress checklist.

The format contract is in msalty/slate, cloned at `../slate` (branch
`claude/fervent-cannon-09hiz7` until it merges; fixtures pinned at `bfa8752`):
`docs/calendar-contacts.md`, `docs/examples/`, `src/core/eventname.ts`,
`src/core/util.ts`. The owner's brief and that doc win over this repo.

## Rules

- Never touch a vault file without `source:` + `uid:`, or one whose hash the
  manifest doesn't recognise. Never delete on a failed, partial or
  suspiciously empty read.
- Output is deterministic: no timestamps, fixed key order and quoting, and no
  write at all when the bytes are identical.
- Tell the owner **before** running anything that triggers a macOS permission
  prompt (Calendars, Contacts). Until asked otherwise, test against a scratch
  folder, never the real vault.
- Keep commits small and descriptive. **Ask before pushing or opening a PR.**

## Commands

- `swift build`, `swift test`
- `scripts/build-app.sh` builds and signs `build/Slate Bridge.app` (needs the
  owner's Apple Development identity).
- `swift run slate-bridge sync --vault DIR --records FILE` or `--live`, and
  `slate-bridge dump contacts|calendars --summary`. Live reads need Terminal
  or the app to have been granted access, not this session's shell.
- `node scripts/name-vectors.mjs ../slate > Tests/Fixtures/name-vectors.json`
  regenerates the filename vectors from Slate's TypeScript.

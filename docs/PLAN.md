# slate-bridge-mac: plan and decisions

The working plan, agreed with the owner before code was written. Update the
checklist at the bottom as steps land.

**Precedence:** the owner's brief and `docs/calendar-contacts.md` in msalty/slate
win over anything here. Where they disagree with each other, the doc wins, and
the owner is told.

## The contract

In msalty/slate, branch `claude/fervent-cannon-09hiz7` until it merges, then
`main`. Clone it next to this repo as `../slate`. Pinned at **`bfa8752`**: the
fixtures in `Tests/Fixtures/vault` and `Tests/Fixtures/name-vectors.json` came
from that commit.

- `docs/calendar-contacts.md` is the spec. Binding: §1.1, §2.1–§2.3, §3, §5.5,
  §6.1–§6.5, §7, §10 Phase C.
- `docs/examples/vault/` is copied to `Tests/Fixtures/vault/`. Files under
  `backstage/calendar/` and `Contacts/Address Book/` must come out byte for byte.
  The rest are the user's files, and are fixtures for "never touch".
- `src/core/eventname.ts` (`importedNoteName`) and `src/core/util.ts`
  (`safeSegment`, `fitSegment`) are ported exactly. They are checked against
  vectors from the TypeScript itself: `node scripts/name-vectors.mjs ../slate`.

## Layout written into the vault

- Meetings: `backstage/calendar/<Account>/<year>/<month>/<title> (<tag>).md`.
- Contacts: `Contacts/Address Book/<Account>/<name>.md`.
- The account folder is always there, even with one account.

## Package

| Target | Holds |
| --- | --- |
| `BridgeCore` | Foundation + CryptoKit only. Records, the name port, the frontmatter writer, event and contact files, attendee linking, naming, time arithmetic. |
| `BridgeWriter` | §6.2 and §6.5 against a real folder: manifest, three-condition rule, following by `uid:`, deletion, atomic byte-compared writes. Runs one sync from records. |
| `BridgeSources` | EventKit and Contacts to records, and the `CNLabel*` map. |
| `slate-bridge` | CLI: `sync --vault DIR [--records FILE] [--state DIR]` and `dump`. |
| App | `MenuBarExtra`, settings, scheduling, `SMAppService`: a thin Xcode project over the package. |

## Decisions

1. **`tz:`** is written whenever EventKit has a zone. `timeZone == nil` is
   floating, with no `tz:`. Most Google/Exchange events will carry `tz:`, which
   contradicts §3's "~95% floating" estimate but loses nothing.
2. **A meeting's path is fixed at first write**, folder included. A meeting
   moved upstream to another month keeps its file, because moving it would
   break path links (`meeting:`). An upstream rename changes `title:` only.
3. **Tag clash** means another file in the folder with that name, ignoring
   case. Lengthen to 8 hex digits, then add a counter.
4. **Occurrence `uid:`**: a single event uses its external identifier as is.
   A recurring occurrence is `<id>/<original start>`, as UTC `20260921T133000Z`
   or `20260921` for all-day. A missing or duplicated external id is
   reported, never guessed.
5. **Contact names**: the clash check runs only when a name is chosen (first
   write, or an upstream rename). A clash is any `.md`/`.txt` outside
   `backstage/` with the same stem, ignoring case. Try `org`, then the email
   local part, then ` 2`. On a first run the order is account (settings order),
   then name, then uid. A later clash with a user note is reported, not renamed.
6. **Upstream contact rename** renames the file only while it still has the
   helper's name and place. The old stem is added to `aliases:`, oldest first,
   and prior names are kept in the manifest.
7. **Quoting**: phones are always quoted. Attendees are a block list with every
   item quoted. Anything else is plain unless YAML or Slate's `parseFrontmatter`
   would misread it (including any comma), and then it is JSON-quoted.
8. **Not sandboxed**, hardened runtime, signed with the owner's free Personal
   Team so permissions survive rebuilds. The manifest lives at
   `~/Library/Application Support/slate-bridge-mac/<vault-id>.json` and the
   vault is kept as a security-scoped bookmark anyway. The vault id is a hash
   of the vault's real path, so the app and the CLI share one manifest. When
   the bookmark finds the vault moved, the app moves the manifest to the new id.
9. **Provider slug** comes from the account name the first time an account is
   seen, then stays fixed in settings. Renaming a folder doesn't change it.
10. **Suspiciously empty read** (an account whose events, or contacts, had
    files and now returns none) is treated as a failed read for that kind: no
    deletions, reported, and a "Confirm deletions" action in the menu
    (`SyncOptions.confirmedEmpty`). This is checked per account, not per
    calendar. A selected calendar that is missing fails the whole account's
    read in the source.
11. **Deselecting** a calendar or container deletes its files on the next
    sync, still under the three-condition rule.
12. **No `Calendar/Subscribed/` migration**: no earlier helper wrote those files.
13. **Golden inputs are JSON records** (`Tests/Fixtures/records.json`), not
    `.ics`/`.vcf` files. That keeps the project free of parsers.
14. **Attendee email match** ignores case, otherwise it is exact. Where two
    contacts share an address, the first by path wins.
15. **Attendee cap** (default 12) is counted after removing yourself. Above the
    cap there is no `attendees:` key.
16. **Short bodies**: cut at the first line of conference boilerplate, lift the
    join link into `url:` and out of the prose, keep at most ~500 characters
    ending in `…`.

## Order of work

1. **Core + golden files.** Done when every helper-owned example file matches
   byte for byte and the name port matches the TypeScript vectors.
2. **Writer against temp folders.** One test per rule in §6.2 and §6.5:
   - a second run writes nothing, with mtimes unchanged;
   - a hand edit is left alone for good;
   - detach leads to the record being re-created;
   - a moved file is followed;
   - a trashed file is not followed, and the record is re-created;
   - a duplicate `uid:` is logged, and nothing is deleted;
   - failed, partial and suspiciously empty reads delete nothing;
   - cancelled means deleted;
   - sliding out of the window means deleted by generation;
   - an upstream title change keeps the filename;
   - a contact rename moves the file and adds an alias;
   - files without `source:` + `uid:` are never touched.

   Then a full sync from `records.json` into a vault holding the user's example
   files must reproduce the example vault exactly.
3. **CLI** with `--records`: the whole pipeline with no permissions.
4. **Contacts source.** ⚠️ Contacts permission prompt: tell the owner first.
   Per container, `uid:` = `CNContact.identifier`. Check with `dump` before
   trusting it.
5. **Events source.** ⚠️ Calendars permission prompt: tell the owner first.
   `dump` a scratch calendar holding a series with one moved occurrence,
   all-day events of one and two days, a floating event, a zoned event, and an
   Exchange event if possible.
6. **App**: menu bar, settings, login item, and scheduling at launch, every
   15 min, on Sync Now, and on store changes (debounced). Run against a
   scratch vault before the real one.

## Progress

- [x] 1 Core + golden files
- [x] 2 Writer
- [x] 3 CLI (`--records` only until the sources exist)
- [ ] 4 Contacts source
- [ ] 5 Events source
- [ ] 6 App

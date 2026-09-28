# Slate Bridge

A macOS menu-bar app that writes your calendars and contacts into your
[Slate](https://github.com/msalty/slate) vault as ordinary Markdown files, so
meetings show on Slate's agenda and `[[Jane Doe]]` links to a real person.

It reads through Apple's own frameworks (EventKit and Contacts), so it covers
every account already in System Settings, including iCloud, Google, Exchange
and Microsoft 365, and CalDAV/CardDAV. No passwords, no servers, no network code.
It only ever writes into the vault; your calendars and contacts are never
changed.

Slate and Slate Bridge share no code. They meet only at the file format,
which is specified in Slate's
[`docs/calendar-contacts.md`](https://github.com/msalty/slate/blob/claude/fervent-cannon-09hiz7/docs/calendar-contacts.md)
with worked examples in
[`docs/examples/`](https://github.com/msalty/slate/tree/claude/fervent-cannon-09hiz7/docs/examples).

## What it writes

```
<vault>/backstage/calendar/<Account>/<year>/<month>/Standup (a41b).md
<vault>/Contacts/Address Book/<Account>/Jane Doe.md
```

**Meetings** go in `backstage/`, so Slate keeps them out of search and note
lists and shows them on the agenda. There is one file per occurrence, from a
month back to three months ahead (the window is adjustable):

```markdown
---
title: Design review
start: 2026-09-21T09:30
end: 2026-09-21T10:00
tz: America/New_York
location: Room 4B
url: https://meet.example/abc
calendar: Work
attendees:
  - "[[Jane Doe]]"
  - "Sam Ortiz"
source: fastmail
uid: 3f2a9c@fastmail.com
---

# Design review

Walk through the onboarding flow before it goes to build.
```

- **The filename is fixed for the life of the meeting.** It is the title plus
  a short tag from the event's id. If the meeting is renamed or moved
  upstream, only the contents change, so links to the file keep working.
- **All-day events get an inclusive `end:`.**
- **A zoned event gets `tz:`,** with its times written on that zone's clock.
- **Attendees who are your contacts become links.** Anyone else is plain
  text, you are left out, and a meeting with more than 12 other attendees gets
  no list.
- **Descriptions are kept short.** Conference-call boilerplate is removed, the
  join link moves into `url:`, and at most about 500 characters are kept.

**Contacts** go in the vault proper, where links can reach them. Each file has
the details as frontmatter (`phone_mobile`, `email_work`, `birthday`, …) and
the same details laid out as Contacts shows them, with tappable `tel:` and
`mailto:` links. A clash with a name already in the vault is resolved with the
company or email, as in `Jane Doe (Example Corp).md`. When a contact is renamed
upstream, the file follows and its old name goes into `aliases:`. Photos,
notes and groups are not written.

## Your files are safe

Slate Bridge keeps a record of every file it wrote, in
`~/Library/Application Support/slate-bridge-mac/`, outside the vault.

- **What it touches.** It overwrites or deletes a file only when all three of
  these hold: the file is in that record, it still carries the same `source:`,
  and it is byte for byte what the app last wrote. So:
  - a file you edited is left alone for good;
  - a meeting you *Detach* in Slate is yours;
  - it never touches a note it didn't write.
- **Moved or renamed files.** A file you move or rename is followed by its
  `uid:`, except into `backstage/trash/`: a trashed meeting that is still on
  the calendar is written again.
- **When it deletes.** Only after a complete, successful read. No access, a
  missing calendar or account, or a suspiciously empty result deletes nothing,
  and the menu asks you to confirm before anything goes.
- **No needless writes.** It never adds timestamps and never rewrites an
  unchanged file (the mtime is left alone too), so your sync service only
  sees real changes.

## Install

**Build it yourself (recommended).** You need macOS 14 or later, Xcode, and a
free Apple ID signing identity. To get one, open Xcode → Settings → Accounts,
add your Apple ID, then Manage Certificates → + → Apple Development.

```bash
git clone https://github.com/msalty/slate-bridge-mac.git
cd slate-bridge-mac
scripts/build-app.sh
cp -R "build/Slate Bridge.app" /Applications/
```

Signing with your own identity lets macOS remember Slate Bridge's Calendars
and Contacts access across updates.

**Or download a build** from the
[Releases](https://github.com/msalty/slate-bridge-mac/releases) page, if one
is posted. It is not notarized by Apple, so the first time, right-click the
app → **Open** → **Open**.

## Setting up

1. Open **Slate Bridge**. A calendar icon appears in the menu bar, and macOS
   asks for access to Calendars and then Contacts.
2. Click the icon → **Settings…**
   - **General:** choose your vault folder. Also set the window, the attendee
     cap, and whether it opens at login.
   - **Accounts:** tick the calendars and contacts accounts to include. By
     default everything is ticked except birthday and subscribed calendars.
     You can also rename an account's folder here.
3. It syncs straight away, then every 15 minutes, when your calendars or
   contacts change, when the Mac wakes, and whenever you choose **Sync Now**.

The menu shows the last sync ("Synced 4 min ago · 312 events · 58 contacts")
and any problems. The full report of the last run is in
`~/Library/Logs/slate-bridge-mac/last-sync.log`.

Try it on an empty folder first if you like: choose a new folder as the
vault, sync, and look at what it wrote.

## Command line

The same engine runs from Terminal:

```bash
swift build
.build/debug/slate-bridge sync --live --vault ~/Notes            # this Mac's accounts
.build/debug/slate-bridge sync --records file.json --vault DIR   # from JSON, no permissions
.build/debug/slate-bridge dump calendars --summary               # counts only, no names
.build/debug/slate-bridge dump contacts --summary
```

`sync --explain` lists which keys changed in each updated file (names only,
no values). Run `slate-bridge` with no arguments for every option. Reading
live data from Terminal asks macOS for access on Terminal's behalf.

## Development

```bash
swift test
```

The package has five targets:

| Target | What it does |
| --- | --- |
| `BridgeCore` | Records to files: names, frontmatter, bodies, attendee links. Pure, with no Apple frameworks beyond Foundation and CryptoKit. |
| `BridgeWriter` | The ownership and deletion rules against a real folder: manifest, following files by `uid:`, atomic byte-compared writes. |
| `BridgeSources` | EventKit and Contacts, read into plain records. |
| `slate-bridge` | The command-line tool. |
| `SlateBridge` | The menu-bar app. `scripts/build-app.sh` bundles and signs it, and `scripts/make-icon.swift` draws its icon. |

`scripts/build-app.sh --release` makes the zip for a GitHub release. It is
signed ad hoc, so no certificate or name is in it, and it is stripped of the
build machine's paths.

How it is tested:

- **Golden files.** Slate's example vault is copied into `Tests/Fixtures/vault`.
  Core renders it byte for byte from `Tests/Fixtures/records.json`, and a full
  sync reproduces the whole vault.
- **Filenames.** The name functions are checked against vectors generated by
  running Slate's own TypeScript (`scripts/name-vectors.mjs`).
- **Writer.** Every ownership and deletion rule has a test against a temporary
  folder.
- **Sources.** The adapters are tested on records built in memory, so the
  tests need no permissions.

`docs/PLAN.md` records the design decisions and why they were made.

import BridgeCore
@testable import BridgeWriter
import Foundation
import Testing

/// §6.2 and §6.5 against real temporary folders.
@Suite struct SyncTests {
    // MARK: - The example vault

    @Test func fullSyncReproducesTheExampleVault() throws {
        let h = try Harness()
        try h.sync()
        let want = try Harness.fixtureTree()
        let got = h.tree()
        #expect(Set(got.keys) == Set(want.keys))
        for (path, text) in want { #expect(got[path] == text, "\(path)") }
    }

    // MARK: - Idempotence (§6.5)

    @Test func secondRunWritesNothingAndTouchesNothing() throws {
        let h = try Harness()
        let first = try h.sync()
        #expect(first.changes.count == 5)
        try h.ageAllFiles()
        let before = h.tree().keys.map { ($0, h.mtime($0)) }
        let second = try h.sync()
        #expect(second.changes.isEmpty)
        #expect(second.unchanged == 5)
        #expect(second.problems.isEmpty)
        for (path, mtime) in before { #expect(h.mtime(path) == mtime, "\(path)") }
        #expect(!h.tree().keys.contains { $0.contains(".slate-bridge.tmp") })
    }

    // MARK: - Ownership (§6.2)

    @Test func handEditIsLeftAloneForGood() throws {
        let h = try Harness()
        try h.sync()
        let original = h.read(designReview)!
        let edited = original + "\nMy own line.\n"
        try h.write(designReview, edited)
        h.editEvent("3f2a9c@fastmail.com") { $0.location = "Room 5A" }
        let r = try h.sync()
        #expect(h.read(designReview) == edited)
        #expect(r.problems.contains { $0.contains("edited by hand") })
        #expect(try h.manifest().entries["fastmail"]?["3f2a9c@fastmail.com"]?.released == true)
        // Even put back exactly as the helper wrote it, it stays the owner's.
        try h.write(designReview, original)
        let again = try h.sync()
        #expect(h.read(designReview) == original)
        #expect(again.changes.isEmpty)
        // No second copy beside it.
        #expect(h.tree().keys.filter { $0.hasPrefix("backstage/calendar/Fastmail/2026/09/Design review") }.count == 1)
        // And gone upstream, it is still not deleted.
        h.removeEvent("3f2a9c@fastmail.com")
        try h.sync()
        #expect(h.read(designReview) == original)
    }

    @Test func detachedMeetingIsWrittenAfresh() throws {
        let h = try Harness()
        try h.sync()
        // Detach as Slate does it: source: and uid: out, filed as a hand-made event.
        let detached = "Calendar/2026/09/Office closed - 2026-09-21.md"
        let text = h.read(officeClosed)!
            .replacingOccurrences(of: "source: fastmail\n", with: "")
            .replacingOccurrences(of: "uid: b7c1e0@fastmail.com\n", with: "")
        try h.write(detached, text)
        try FileManager.default.removeItem(at: h.url(officeClosed))
        h.editEvent("b7c1e0@fastmail.com") { $0.calendar = "Family" }
        let r = try h.sync()
        #expect(r.changes.contains(.created(officeClosed)))
        #expect(try #require(h.read(officeClosed)).contains("calendar: Family\n"))
        #expect(h.read(detached) == text)
    }

    @Test func detachedInPlaceIsLeftAndTheRecordTakesALongerTag() throws {
        let h = try Harness()
        try h.sync()
        let text = try #require(h.read(officeClosed)).replacingOccurrences(of: "uid: b7c1e0@fastmail.com\n", with: "")
        try h.write(officeClosed, text)
        try h.sync()
        #expect(h.read(officeClosed) == text)
        #expect(h.exists("backstage/calendar/Fastmail/2026/09/Office closed (3a770).md"))
    }

    @Test func movedFileIsFollowed() throws {
        let h = try Harness()
        try h.sync()
        try h.move(janeFastmail, "People/Jane.md")
        try h.move(tokyoSync, "backstage/calendar/Elsewhere/Tokyo.md")
        h.editContact("jane-doe@fastmail.com") { $0.department = "Research" }
        h.editEvent("0e9d44@work.example") { $0.location = "Shibuya" }
        let r = try h.sync()
        #expect(try #require(h.read("People/Jane.md")).contains("department: Research\n"))
        #expect(try #require(h.read("backstage/calendar/Elsewhere/Tokyo.md")).contains("location: Shibuya\n"))
        #expect(!h.exists(janeFastmail))
        #expect(!h.exists(tokyoSync))
        #expect(r.changes.contains(.moved(from: janeFastmail, to: "People/Jane.md")))
        let m = try h.manifest()
        #expect(m.entries["fastmail"]?["jane-doe@fastmail.com"]?.path == "People/Jane.md")
        // Attendees link to the contact by the name it has now.
        #expect(try #require(h.read(designReview)).contains(#"  - "[[Jane]]""#))
        // And the next run is quiet again.
        #expect(try h.sync().changes.isEmpty)
    }

    @Test func trashedFileIsNotFollowedAndIsWrittenAfresh() throws {
        let h = try Harness()
        try h.sync()
        let trashed = "backstage/trash/Design review (b361).md"
        let text = h.read(designReview)!
        try h.move(designReview, trashed)
        h.editEvent("3f2a9c@fastmail.com") { $0.title = "Design review, v2" }
        let r = try h.sync()
        // Written afresh, so named from the title it has now.
        let fresh = "backstage/calendar/Fastmail/2026/09/Design review, v2 (b361).md"
        #expect(r.changes == [.created(fresh)])
        #expect(try #require(h.read(fresh)).contains(#"title: "Design review, v2""#))
        #expect(h.read(trashed) == text)
    }

    @Test func duplicateUIDIsLoggedAndNothingDeleted() throws {
        let h = try Harness()
        try h.sync()
        let original = h.read(tokyoSync)!
        // A copy made outside Slate, edited; then the original moved.
        try h.write("Copies/Tokyo sync copy.md", original + "\nnotes\n")
        try h.move(tokyoSync, "backstage/calendar/Work/Tokyo sync (43ce).md")
        h.editEvent("0e9d44@work.example") { $0.title = "Tokyo sync (moved)" }
        let r = try h.sync()
        #expect(r.problems.contains { $0.contains("Copies/Tokyo sync copy.md") })
        #expect(h.read("Copies/Tokyo sync copy.md") == original + "\nnotes\n")
        #expect(h.read("backstage/calendar/Work/Tokyo sync (43ce).md")!.contains("title: Tokyo sync (moved)\n"))
    }

    @Test func identicalCopiesKeepTheFirstAndLeaveTheOther() throws {
        let h = try Harness()
        try h.sync()
        let original = h.read(tokyoSync)!
        try h.write("A/Tokyo.md", original)
        try h.move(tokyoSync, "B/Tokyo.md")
        h.editEvent("0e9d44@work.example") { $0.location = "Ginza" }
        let r = try h.sync()
        #expect(try #require(h.read("A/Tokyo.md")).contains("location: Ginza\n"))
        #expect(h.read("B/Tokyo.md") == original)
        #expect(r.problems.contains { $0.contains("B/Tokyo.md also claims") })
    }

    @Test func titleChangeKeepsTheFilename() throws {
        let h = try Harness()
        try h.sync()
        h.editEvent("3f2a9c@fastmail.com") { $0.title = "Design critique: onboarding" }
        let r = try h.sync()
        #expect(r.changes == [.updated(designReview)])
        let text = h.read(designReview)!
        #expect(text.hasPrefix("---\ntitle: \"Design critique: onboarding\"\n"))
        #expect(text.contains("\n# Design critique: onboarding\n"))
    }

    @Test func meetingMovedToAnotherMonthKeepsItsPath() throws {
        let h = try Harness()
        try h.sync()
        h.editEvent("3f2a9c@fastmail.com") {
            $0.timing = .timed(start: CivilDateTime(CivilDate(2026, 11, 2), 9, 30),
                               end: CivilDateTime(CivilDate(2026, 11, 2), 10, 0), zone: nil)
        }
        try h.sync()
        #expect(try #require(h.read(designReview)).contains("start: 2026-11-02T09:30\n"))
        #expect(!h.exists("backstage/calendar/Fastmail/2026/11"))
    }

    @Test func contactRenamedUpstreamMovesAndKeepsItsOldNames() throws {
        let h = try Harness(seedPriorNames: false)
        // Fastmail alone: with Work's Jane Doe here too, the bare name would be
        // hers by the time this one is renamed back to it.
        h.records.accounts.removeAll { $0.source == "work" }
        h.editContact("jane-doe@fastmail.com") { $0.name = "Jane Smith" }
        try h.sync()
        #expect(h.exists("Contacts/Address Book/Fastmail/Jane Smith.md"))
        #expect(try #require(h.read(designReview)).contains(#""[[Jane Smith]]""#))
        h.editContact("jane-doe@fastmail.com") { $0.name = "JD" }
        try h.sync()
        h.editContact("jane-doe@fastmail.com") { $0.name = "Jane Doe" }
        let r = try h.sync()
        #expect(r.changes.contains(.moved(from: "Contacts/Address Book/Fastmail/JD.md", to: janeFastmail)))
        #expect(!h.exists("Contacts/Address Book/Fastmail/Jane Smith.md"))
        #expect(!h.exists("Contacts/Address Book/Fastmail/JD.md"))
        // Byte for byte the example: aliases [Jane Smith, JD] included.
        #expect(h.read(janeFastmail) == (try String(contentsOf: fixtures.appendingPathComponent("vault/\(janeFastmail)"), encoding: .utf8)))
        #expect(try #require(h.read(designReview)).contains(#""[[Jane Doe]]""#))
    }

    @Test func contactTheOwnerRenamedKeepsTheOwnersName() throws {
        let h = try Harness()
        try h.sync()
        try h.move(janeFastmail, "Contacts/Address Book/Fastmail/Janey.md")
        h.editContact("jane-doe@fastmail.com") { $0.name = "Jane Q. Doe" }
        try h.sync()
        #expect(try #require(h.read("Contacts/Address Book/Fastmail/Janey.md")).hasPrefix("---\nname: Jane Q. Doe\n"))
        #expect(!h.exists("Contacts/Address Book/Fastmail/Jane Q. Doe.md"))
    }

    @Test func contactNamesClearTheOwnersNotes() throws {
        let h = try Harness()
        try h.write("Jane Doe.md", "# My own Jane Doe note\n")
        try h.sync()
        #expect(h.exists("Contacts/Address Book/Fastmail/Jane Doe (Example Corp).md"))
        #expect(h.exists("Contacts/Address Book/Work/Jane Doe (jane.doe).md"))
        #expect(h.read("Jane Doe.md") == "# My own Jane Doe note\n")
        #expect(try #require(h.read(tokyoSync)).contains(#""[[Jane Doe (jane.doe)]]""#))
    }

    @Test func aSharedNameLinksByPath() throws {
        let h = try Harness()
        try h.sync()
        // The owner makes a note with the contact's name afterwards: the
        // contact keeps its name, and links to it go by path.
        try h.write("Jane Doe.md", "# Another Jane\n")
        try h.sync()
        #expect(h.exists(janeFastmail))
        #expect(try #require(h.read(designReview)).contains(#""[[Contacts/Address Book/Fastmail/Jane Doe]]""#))
    }

    @Test func filesWithoutSourceAndUIDAreNeverTouched() throws {
        let h = try Harness()
        let squatter = "---\ntitle: Design review\nstart: 2026-09-21T09:30\n---\n\nMine.\n"
        try h.write(designReview, squatter)
        try h.sync()
        #expect(h.read(designReview) == squatter)
        #expect(h.exists("backstage/calendar/Fastmail/2026/09/Design review (b3617).md"))
        for f in userFiles { #expect(h.read(f) == (try String(contentsOf: fixtures.appendingPathComponent("vault/\(f)"), encoding: .utf8))) }
    }

    @Test func aFileClaimedByAnotherSourceIsNotOurs() throws {
        let h = try Harness()
        try h.sync()
        let text = try #require(h.read(officeClosed)).replacingOccurrences(of: "source: fastmail", with: "source: google")
        try h.write(officeClosed, text)
        try h.sync()
        #expect(h.read(officeClosed) == text)
        #expect(h.exists("backstage/calendar/Fastmail/2026/09/Office closed (3a770).md"))
    }

    // MARK: - Deletion (§6.2)

    @Test func cancelledUpstreamIsDeleted() throws {
        let h = try Harness()
        // A second Work event, so the read below is not an empty one.
        let other = EventRecord(uid: "later@work.example", title: "Later",
                                timing: .allDay(first: CivilDate(2026, 11, 3), last: CivilDate(2026, 11, 3)))
        for i in h.records.accounts.indices where h.records.accounts[i].source == "work" {
            h.records.accounts[i].events!.append(other)
        }
        try h.sync()
        h.removeEvent("0e9d44@work.example")
        let r = try h.sync()
        #expect(r.changes == [.deleted(tokyoSync, reason: "cancelled upstream")])
        #expect(!h.exists(tokyoSync))
        // The empty month and year folders go; the account folder stays.
        #expect(!h.exists("backstage/calendar/Work/2026/10"))
        #expect(h.exists("backstage/calendar/Work/2026/11/Later (\(Naming.sha256Hex("later@work.example").prefix(4))).md"))
        #expect(try h.manifest().entries["work"]?["0e9d44@work.example"] == nil)
    }

    @Test func emptiedFoldersArePrunedUpToTheAccount() throws {
        let h = try Harness()
        try h.sync()
        h.removeEvent("0e9d44@work.example")
        h.options.confirmedEmpty = ["work"]
        try h.sync()
        #expect(!h.exists("backstage/calendar/Work/2026"))
        #expect(h.exists("backstage/calendar/Work"))
    }

    @Test func slidOutOfTheWindowIsDeletedByGeneration() throws {
        let h = try Harness()
        try h.sync()
        h.removeEvent("b7c1e0@fastmail.com")
        h.options.windowStart = CivilDate(2026, 9, 22)
        let r = try h.sync()
        #expect(r.changes == [.deleted(officeClosed, reason: "slid out of the window")])
    }

    @Test func contactDeletedUpstreamIsDeleted() throws {
        let h = try Harness()
        try h.sync()
        for i in h.records.accounts.indices where h.records.accounts[i].source == "work" {
            h.records.accounts[i].contacts = [ContactRecord(uid: "other@work", name: "Someone Else")]
        }
        let r = try h.sync()
        #expect(r.changes.contains(.deleted(janeWork, reason: "deleted upstream")))
        // Tokyo sync's attendee is now plain text.
        #expect(try #require(h.read(tokyoSync)).contains(#"  - "Jane Doe""#))
    }

    @Test func failedReadDeletesNothing() throws {
        let h = try Harness()
        try h.sync()
        let before = h.tree()
        for i in h.records.accounts.indices { h.records.accounts[i].failed = "no permission" }
        let r = try h.sync()
        #expect(h.tree() == before)
        #expect(r.changes.isEmpty)
        #expect(r.problems.count == 4)
        // Attendees still link to contacts nobody could read this time.
        #expect(try #require(h.read(designReview)).contains(#""[[Jane Doe]]""#))
    }

    @Test func unreadKindDeletesNothing() throws {
        let h = try Harness()
        try h.sync()
        let before = h.tree()
        for i in h.records.accounts.indices { h.records.accounts[i].events = nil; h.records.accounts[i].contacts = nil }
        #expect(try h.sync().changes.isEmpty)
        #expect(h.tree() == before)
    }

    @Test func suspiciouslyEmptyReadDeletesNothingUntilConfirmed() throws {
        let h = try Harness()
        try h.sync()
        for i in h.records.accounts.indices where h.records.accounts[i].source == "fastmail" {
            h.records.accounts[i].events = []
        }
        let r = try h.sync()
        #expect(r.changes.isEmpty)
        #expect(r.problems == ["Fastmail: no events came back; nothing deleted until confirmed"])
        #expect(h.exists(designReview) && h.exists(officeClosed))
        h.options.confirmedEmpty = ["fastmail"]
        let confirmed = try h.sync()
        #expect(confirmed.changes.count == 2)
        #expect(!h.exists(designReview) && !h.exists(officeClosed))
    }

    @Test func duplicateUIDsInOneReadAreSkippedNotDeleted() throws {
        let h = try Harness()
        try h.sync()
        h.editEvent("b7c1e0@fastmail.com") { $0.calendar = "Changed" }
        for i in h.records.accounts.indices where h.records.accounts[i].source == "fastmail" {
            let dup = h.records.accounts[i].events!.first { $0.uid == "b7c1e0@fastmail.com" }!
            h.records.accounts[i].events!.append(dup)
        }
        let r = try h.sync()
        #expect(r.problems.contains { $0.contains("share the uid b7c1e0@fastmail.com") })
        #expect(try #require(h.read(officeClosed)).contains("calendar: Personal\n"))
    }

    @Test func unreadableManifestIsAnErrorNotAnEmptyOne() throws {
        let h = try Harness()
        try "not json".write(to: h.store.url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try h.sync() }
        #expect(!h.exists(designReview))
    }
}

extension Harness {
    static func fixtureTree() throws -> [String: String] {
        var out: [String: String] = [:]
        let root = fixtures.appendingPathComponent("vault")
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        let base = root.standardizedFileURL.path + "/"
        for case let u as URL in e where !u.hasDirectoryPath && u.lastPathComponent != ".DS_Store" {
            out[String(u.standardizedFileURL.path.dropFirst(base.count))] = try String(contentsOf: u, encoding: .utf8)
        }
        return out
    }
}

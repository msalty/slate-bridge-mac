@testable import BridgeCore
import Foundation
import Testing

/// Every helper-owned file in the example vault, rendered from `records.json`
/// and compared byte for byte.
@Suite struct GoldenTests {
    let records = try! fixtureRecords()
    let priorNames = try! fixturePriorNames()

    /// Both Janes, where they sit in the example vault.
    var directory: ContactDirectory {
        let contacts = records.accounts.flatMap { a in (a.contacts ?? []).map { (a.folder, $0) } }
        return ContactDirectory(contacts.map { folder, c in
            let stem = folder == "Work" ? "Jane Doe (Example Corp)" : "Jane Doe"
            return .init(emails: c.emails.map(\.value), stem: stem,
                         pathStem: "Contacts/Address Book/\(folder)/\(stem)", shared: false)
        })
    }

    func account(_ source: String) -> RecordSet.Account {
        records.accounts.first { $0.source == source }!
    }

    func event(_ source: String, _ uid: String) -> String {
        let e = account(source).events!.first { $0.uid == uid }!
        let items = AttendeeLinking.items(e.attendees, directory: directory, cap: AttendeeLinking.defaultCap)
        return EventFile.render(e, source: source, attendees: items)
    }

    func contact(_ source: String, _ uid: String) -> String {
        let c = account(source).contacts!.first { $0.uid == uid }!
        return ContactFile.render(c, source: source, aliases: priorNames[source]?[uid] ?? [])
    }

    @Test func timedFloatingEventWithEveryKey() throws {
        #expect(event("fastmail", "3f2a9c@fastmail.com")
            == (try fixtureText("vault/backstage/calendar/Fastmail/2026/09/Design review (b361).md")))
    }

    @Test func allDayEventOverTwoDays() throws {
        #expect(event("fastmail", "b7c1e0@fastmail.com")
            == (try fixtureText("vault/backstage/calendar/Fastmail/2026/09/Office closed (3a77).md")))
    }

    @Test func zonedEventInAnotherAccount() throws {
        #expect(event("work", "0e9d44@work.example")
            == (try fixtureText("vault/backstage/calendar/Work/2026/10/Tokyo sync (43ce).md")))
    }

    @Test func fullContact() throws {
        #expect(contact("fastmail", "jane-doe@fastmail.com")
            == (try fixtureText("vault/Contacts/Address Book/Fastmail/Jane Doe.md")))
    }

    @Test func contactWithABirthdayWithoutAYear() throws {
        #expect(contact("work", "jane-doe@work.example")
            == (try fixtureText("vault/Contacts/Address Book/Work/Jane Doe (Example Corp).md")))
    }

    @Test func namesAndFoldersOfTheExamples() {
        for (source, uid, title, name) in [
            ("fastmail", "3f2a9c@fastmail.com", "Design review", "Design review (b361)"),
            ("fastmail", "b7c1e0@fastmail.com", "Office closed", "Office closed (3a77)"),
            ("work", "0e9d44@work.example", "Tokyo sync", "Tokyo sync (43ce)"),
        ] {
            _ = source
            #expect(Naming.eventName(title: title, uid: uid, taken: { _ in false }) == name)
        }
        let tokyo = account("work").events![0]
        // Filed by the start as written: Tokyo's wall clock, in October.
        #expect(tokyo.timing.firstDay == CivilDate(2026, 10, 1))
    }
}

@testable import BridgeCore
import Testing

@Suite struct ContactTests {
    @Test func labelSlugs() {
        #expect(Labels.slug("Lake house") == "lake_house")
        #expect(Labels.slug("  Work -- Main!  ") == "work_main")
        #expect(Labels.slug("Café") == "caf")
        #expect(Labels.slug("日本") == nil)
        #expect(Labels.slug("") == nil)
        #expect(Labels.slug(nil) == nil)
    }

    @Test func keysForUnlabelledRepeatedAndCustomValues() {
        let c = ContactRecord(
            uid: "u", name: "Sam Ortiz",
            phones: [Labeled(nil, "5550143"), Labeled("lake_house", "+1 555 0199"), Labeled("lake_house", "0800 123")],
            emails: [Labeled("work", "sam@a.example")],
            addresses: [Labeled(nil, ["1 Main St", "Springfield"])],
            dates: [Labeled(nil, PartialDate(year: nil, month: 5, day: 1)), Labeled("other", PartialDate(year: 2001, month: 1, day: 2))],
            social: [Labeled("linkedin", "https://linkedin.com/in/sam")], im: [Labeled("skype", "sam.o")])
        let text = ContactFile.render(c, source: "icloud", aliases: [])
        #expect(text.hasPrefix("""
            ---
            name: Sam Ortiz
            phone: "5550143"
            phone_lake_house: ["+1 555 0199", "0800 123"]
            email_work: sam@a.example
            address: "1 Main St, Springfield"
            date_other: [--05-01, 2001-01-02]
            social_linkedin: https://linkedin.com/in/sam
            im_skype: sam.o
            source: icloud
            uid: u
            ---

            # Sam Ortiz

            ## Phone

            - [5550143](tel:5550143)
            - lake house · [+1 555 0199](tel:+15550199)
            - lake house · [0800 123](tel:0800123)

            ## Email

            - work · [sam@a.example](mailto:sam@a.example)

            ## Address

            - 1 Main St\u{20}\u{20}
              Springfield

            ## Dates

            - 1 May
            - other · 2 January 2001

            ## Social

            - linkedin · https://linkedin.com/in/sam

            ## Messaging

            - skype · sam.o

            """))
        #expect(!text.contains("\ndate:"))
        #expect(!text.contains("\ntitle:"))
    }

    @Test func nameOnly() {
        #expect(ContactFile.render(ContactRecord(uid: "u", name: "Mo"), source: "s", aliases: ["M"]) == """
            ---
            name: Mo
            aliases: [M]
            source: s
            uid: u
            ---

            # Mo

            """)
    }

    @Test func headingLineSkipsWhatIsMissing() {
        let c = ContactRecord(uid: "u", name: "A", org: "Acme", jobTitle: "CTO")
        #expect(ContactFile.render(c, source: "s", aliases: []).hasSuffix("# A\n\nCTO · Acme\n"))
    }

    @Test func telLinks() {
        #expect(ContactFile.telDigits("+1 (555) 014-3") == "+15550143")
        #expect(ContactFile.telDigits(" +44 20 7946 0958 ext. 12") == "+442079460958" + "12")
        #expect(ContactFile.telDigits("555.0143") == "5550143")
    }
}

@Suite struct AttendeeTests {
    let directory = ContactDirectory([
        .init(emails: ["jane@example.com", "JD@me.com"], stem: "Jane Doe", pathStem: "Contacts/Address Book/Fastmail/Jane Doe", shared: false),
        .init(emails: ["bo@x.example"], stem: "Bo", pathStem: "Contacts/Address Book/Work/Bo", shared: true),
    ])

    @Test func matchedLinkedUnmatchedPlainSelfSkipped() {
        let items = AttendeeLinking.items([
            Attendee(name: "Jane", email: "jd@ME.com"),
            Attendee(name: "Me", email: "me@x", isCurrentUser: true),
            Attendee(name: "Sam Ortiz", email: "sam@x"),
            Attendee(name: nil, email: "anon@x"),
            Attendee(name: "Bo B", email: "bo@x.example"),
            Attendee(name: "Jane again", email: "jane@example.com"),
        ], directory: directory, cap: 12)
        #expect(items == ["[[Jane Doe]]", "Sam Ortiz", "anon@x", "[[Contacts/Address Book/Work/Bo]]"])
    }

    @Test func noListAboveTheCap() {
        let many = (1...13).map { Attendee(name: "P\($0)", email: "p\($0)@x") }
        #expect(AttendeeLinking.items(many, directory: directory, cap: 12) == nil)
        // You do not count towards it.
        let twelve = Array(many.prefix(12)) + [Attendee(name: "Me", isCurrentUser: true)]
        #expect(AttendeeLinking.items(twelve, directory: directory, cap: 12)?.count == 12)
        #expect(AttendeeLinking.items([Attendee(name: "Me", isCurrentUser: true)], directory: directory, cap: 12) == nil)
    }
}

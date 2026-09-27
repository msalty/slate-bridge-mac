import BridgeCore
@testable import BridgeSources
import Contacts
import Foundation
import Testing

/// The Contacts adapter on cards built in memory, which needs no permission:
/// no store is opened and nothing is fetched.
@Suite struct ContactsSourceTests {
    @Test func builtInLabelsMapToPlainNames() {
        #expect(ContactLabels.slug(CNLabelHome) == "home")
        #expect(ContactLabels.slug(CNLabelPhoneNumberHomeFax) == "home_fax")
        #expect(ContactLabels.slug(CNLabelPhoneNumberiPhone) == "iphone")
        #expect(ContactLabels.slug(CNLabelURLAddressHomePage) == "homepage")
        #expect(ContactLabels.slug(CNLabelDateAnniversary) == "anniversary")
        #expect(ContactLabels.slug(CNLabelContactRelationSpouse) == "spouse")
        #expect(ContactLabels.slug(CNLabelContactRelationYoungerSibling) == "younger_sibling")
        // One the table does not know, by its code's name.
        #expect(ContactLabels.slug("_$!<GreatAuntFAX>!$_") == "great_aunt_fax")
        // Custom labels are the owner's own words.
        #expect(ContactLabels.slug("Lake house") == "lake_house")
        #expect(ContactLabels.slug(nil) == nil)
        #expect(ContactLabels.slug("") == nil)
    }

    @Test func everyBuiltInLabelHasASlug() {
        for (code, slug) in ContactLabels.builtIn {
            #expect(!code.isEmpty)
            #expect(Labels.slug(slug) == slug, "\(slug)")
        }
    }

    /// Jane's card from the example vault, put through the adapter and Core:
    /// it has to come out as the example file, byte for byte.
    @Test func janeDoeFromAContactsCard() throws {
        let c = CNMutableContact()
        c.givenName = "Jane"
        c.familyName = "Doe"
        c.nickname = "Janey"
        c.organizationName = "Example Corp"
        c.departmentName = "Design"
        c.jobTitle = "Head of Design"
        c.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 555 0143")),
            CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+1 555 0100")),
        ]
        c.emailAddresses = [
            CNLabeledValue(label: CNLabelHome, value: "jane@example.com" as NSString),
            CNLabeledValue(label: CNLabelHome, value: "jd@me.com" as NSString),
            CNLabeledValue(label: CNLabelWork, value: "j.doe@work.example" as NSString),
        ]
        let address = CNMutablePostalAddress()
        address.street = "12 Rua Augusta"
        address.postalCode = "1100-053"
        address.city = "Lisboa"
        address.country = "Portugal"
        address.isoCountryCode = "pt"
        c.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address)]
        c.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://jane.example" as NSString)]
        c.birthday = DateComponents(year: 1984, month: 3, day: 2)
        c.dates = [CNLabeledValue(label: CNLabelDateAnniversary, value: DateComponents(year: 2010, month: 6, day: 14) as NSDateComponents)]
        c.contactRelations = [CNLabeledValue(label: CNLabelContactRelationSpouse, value: CNContactRelation(name: "Sam Doe"))]

        var record = ContactsSource.record(c)
        #expect(record.name == "Jane Doe")
        #expect(record.addresses.first?.value == ["12 Rua Augusta", "1100-053 Lisboa", "Portugal"])
        record.uid = "jane-doe@fastmail.com" // a store's identifier is its own
        let want = try String(contentsOf: fixtures.appendingPathComponent("vault/Contacts/Address Book/Fastmail/Jane Doe.md"), encoding: .utf8)
        #expect(ContactFile.render(record, source: "fastmail", aliases: ["Jane Smith", "JD"]) == want)
    }

    @Test func birthdayWithoutAYear() {
        let c = CNMutableContact()
        c.givenName = "Jane"
        c.birthday = DateComponents(month: 3, day: 2)
        #expect(ContactsSource.record(c).birthday?.description == "--03-02")
    }

    @Test func companyCardIsNamedByItsCompany() {
        let c = CNMutableContact()
        c.contactType = .organization
        c.organizationName = "Example Corp"
        #expect(ContactsSource.record(c).name == "Example Corp")
        let nameless = CNMutableContact()
        nameless.emailAddresses = [CNLabeledValue(label: nil, value: "who@x.example" as NSString)]
        #expect(ContactsSource.record(nameless).name == "who@x.example")
    }

    @Test func socialAndMessagingByService() {
        let c = CNMutableContact()
        c.givenName = "Sam"
        c.socialProfiles = [
            CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: "sam_o", userIdentifier: nil, service: CNSocialProfileServiceTwitter)),
            CNLabeledValue(label: nil, value: CNSocialProfile(urlString: "https://linkedin.com/in/sam", username: nil, userIdentifier: nil, service: CNSocialProfileServiceLinkedIn)),
        ]
        c.instantMessageAddresses = [CNLabeledValue(label: nil, value: CNInstantMessageAddress(username: "sam.o", service: CNInstantMessageServiceSkype))]
        let r = ContactsSource.record(c)
        #expect(r.social == [Labeled("twitter", "sam_o"), Labeled("linkedin", "https://linkedin.com/in/sam")])
        #expect(r.im == [Labeled("skype", "sam.o")])
    }
}

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

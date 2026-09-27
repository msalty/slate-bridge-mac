import BridgeCore
@preconcurrency import Contacts
import Foundation

/// The Contacts framework, read into plain records (§2.2), one container
/// (account) at a time. Reads every account in System Settings — iCloud,
/// Google, Exchange, CardDAV — with no credentials of its own.
///
/// Never asks for the note field: reading it needs an entitlement Apple grants
/// case by case, and what you know about a person goes in your own note.
public final class ContactsSource: @unchecked Sendable {
    let store = CNContactStore()

    public init() {}

    public struct Container: Codable, Sendable {
        public var id: String
        public var name: String
        public var type: String
    }

    public static var authorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    /// Shows the system prompt the first time.
    public func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    public func containers() throws -> [Container] {
        try store.containers(matching: nil).map {
            Container(id: $0.identifier, name: $0.name, type: Self.typeName($0.type))
        }
    }

    /// Everything written, and nothing else: no note, no photo.
    static let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)] + [
        CNContactIdentifierKey, CNContactTypeKey, CNContactNicknameKey, CNContactOrganizationNameKey,
        CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey, CNContactPostalAddressesKey, CNContactUrlAddressesKey,
        CNContactBirthdayKey, CNContactDatesKey, CNContactRelationsKey, CNContactSocialProfilesKey,
        CNContactInstantMessageAddressesKey,
    ].map { $0 as CNKeyDescriptor }

    /// Every contact in one container. `.failed` for anything short of a
    /// complete read: no permission, the container gone, an error.
    public func read(container id: String) -> Read<[ContactRecord]> {
        guard Self.authorized else { return .failed("no permission to read contacts") }
        do {
            guard try store.containers(matching: CNContainer.predicateForContainers(withIdentifiers: [id])).first != nil else {
                return .failed("the contacts account is missing")
            }
            let request = CNContactFetchRequest(keysToFetch: Self.keys)
            request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: id)
            // One card per container: a card linked across accounts would
            // otherwise arrive with another account's details.
            request.unifyResults = false
            var out: [ContactRecord] = []
            try store.enumerateContacts(with: request) { contact, _ in out.append(Self.record(contact)) }
            return .complete(out)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Contact → record

    static func record(_ c: CNContact) -> ContactRecord {
        let emails = c.emailAddresses.map { Labeled(ContactLabels.slug($0.label), $0.value as String) }
        return ContactRecord(
            uid: c.identifier,
            name: displayName(c, emails: emails.map(\.value)),
            nickname: text(c.nickname),
            org: text(c.organizationName),
            department: text(c.departmentName),
            jobTitle: text(c.jobTitle),
            phones: c.phoneNumbers.map { Labeled(ContactLabels.slug($0.label), $0.value.stringValue) },
            emails: emails,
            addresses: c.postalAddresses.map { Labeled(ContactLabels.slug($0.label), addressLines($0.value)) },
            urls: c.urlAddresses.map { Labeled(ContactLabels.slug($0.label), $0.value as String) },
            birthday: c.birthday.flatMap(partialDate),
            dates: c.dates.compactMap { lv in
                partialDate(lv.value as DateComponents).map { Labeled(ContactLabels.slug(lv.label), $0) }
            },
            related: c.contactRelations.map { Labeled(ContactLabels.slug($0.label), $0.value.name) },
            social: c.socialProfiles.compactMap { lv in
                let p = lv.value
                guard let value = text(p.username) ?? text(p.urlString) else { return nil }
                return Labeled(Labels.slug(p.service) ?? ContactLabels.slug(lv.label), value)
            },
            im: c.instantMessageAddresses.compactMap { lv in
                let a = lv.value
                guard let value = text(a.username) else { return nil }
                return Labeled(Labels.slug(a.service) ?? ContactLabels.slug(lv.label), value)
            })
    }

    /// The name as Contacts shows it; a company card by its company.
    static func displayName(_ c: CNContact, emails: [String]) -> String {
        if c.contactType == .organization, let org = text(c.organizationName) { return org }
        return text(CNContactFormatter.string(from: c, style: .fullName))
            ?? text(c.organizationName) ?? text(c.nickname) ?? emails.first ?? "Untitled"
    }

    /// The address the way its country writes it, one line per line.
    static func addressLines(_ a: CNPostalAddress) -> [String] {
        CNPostalAddressFormatter.string(from: a, style: .mailingAddress)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func partialDate(_ d: DateComponents) -> PartialDate? {
        guard let m = d.month, let day = d.day, m != NSDateComponentUndefined, day != NSDateComponentUndefined else { return nil }
        let y = d.year.flatMap { $0 == NSDateComponentUndefined ? nil : $0 }
        return PartialDate(year: y, month: m, day: day)
    }

    static func text(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    static func typeName(_ t: CNContainerType) -> String {
        switch t {
        case .local: "local"
        case .exchange: "exchange"
        case .cardDAV: "cardDAV"
        default: "unassigned"
        }
    }
}

import BridgeCore
@preconcurrency import Contacts

/// Apple's built-in labels as their plain names (§2.2). A built-in label is
/// stored as a code like `_$!<HomeFAX>!$_`, not as text anybody chose, so it
/// is mapped here rather than slugged; everything else is the user's own and
/// goes through `Labels.slug`.
public enum ContactLabels {
    static let builtIn: [String: String] = {
        var map: [String: String] = [
            CNLabelHome: "home",
            CNLabelWork: "work",
            CNLabelSchool: "school",
            CNLabelOther: "other",
            CNLabelEmailiCloud: "icloud",
            CNLabelURLAddressHomePage: "homepage",
            CNLabelDateAnniversary: "anniversary",
            CNLabelPhoneNumberMobile: "mobile",
            CNLabelPhoneNumberiPhone: "iphone",
            CNLabelPhoneNumberAppleWatch: "apple_watch",
            CNLabelPhoneNumberMain: "main",
            CNLabelPhoneNumberHomeFax: "home_fax",
            CNLabelPhoneNumberWorkFax: "work_fax",
            CNLabelPhoneNumberOtherFax: "other_fax",
            CNLabelPhoneNumberPager: "pager",
        ]
        let relations: [(String, String)] = [
            (CNLabelContactRelationAssistant, "assistant"), (CNLabelContactRelationManager, "manager"),
            (CNLabelContactRelationColleague, "colleague"), (CNLabelContactRelationTeacher, "teacher"),
            (CNLabelContactRelationSibling, "sibling"), (CNLabelContactRelationYoungerSibling, "younger_sibling"),
            (CNLabelContactRelationElderSibling, "elder_sibling"), (CNLabelContactRelationSister, "sister"),
            (CNLabelContactRelationYoungerSister, "younger_sister"), (CNLabelContactRelationElderSister, "elder_sister"),
            (CNLabelContactRelationBrother, "brother"), (CNLabelContactRelationYoungerBrother, "younger_brother"),
            (CNLabelContactRelationElderBrother, "elder_brother"), (CNLabelContactRelationFriend, "friend"),
            (CNLabelContactRelationMaleFriend, "male_friend"), (CNLabelContactRelationFemaleFriend, "female_friend"),
            (CNLabelContactRelationSpouse, "spouse"), (CNLabelContactRelationWife, "wife"),
            (CNLabelContactRelationHusband, "husband"), (CNLabelContactRelationPartner, "partner"),
            (CNLabelContactRelationMalePartner, "male_partner"), (CNLabelContactRelationFemalePartner, "female_partner"),
            (CNLabelContactRelationGirlfriendOrBoyfriend, "girlfriend_or_boyfriend"),
            (CNLabelContactRelationGirlfriend, "girlfriend"), (CNLabelContactRelationBoyfriend, "boyfriend"),
            (CNLabelContactRelationParent, "parent"), (CNLabelContactRelationMother, "mother"),
            (CNLabelContactRelationFather, "father"), (CNLabelContactRelationChild, "child"),
            (CNLabelContactRelationDaughter, "daughter"), (CNLabelContactRelationSon, "son"),
            (CNLabelContactRelationGrandparent, "grandparent"), (CNLabelContactRelationGrandmother, "grandmother"),
            (CNLabelContactRelationGrandfather, "grandfather"), (CNLabelContactRelationGrandchild, "grandchild"),
            (CNLabelContactRelationGranddaughter, "granddaughter"), (CNLabelContactRelationGrandson, "grandson"),
            (CNLabelContactRelationParentInLaw, "parent_in_law"), (CNLabelContactRelationMotherInLaw, "mother_in_law"),
            (CNLabelContactRelationFatherInLaw, "father_in_law"), (CNLabelContactRelationChildInLaw, "child_in_law"),
            (CNLabelContactRelationSonInLaw, "son_in_law"), (CNLabelContactRelationDaughterInLaw, "daughter_in_law"),
            (CNLabelContactRelationSiblingInLaw, "sibling_in_law"), (CNLabelContactRelationSisterInLaw, "sister_in_law"),
            (CNLabelContactRelationBrotherInLaw, "brother_in_law"), (CNLabelContactRelationCousin, "cousin"),
            (CNLabelContactRelationAunt, "aunt"), (CNLabelContactRelationUncle, "uncle"),
            (CNLabelContactRelationNiece, "niece"), (CNLabelContactRelationNephew, "nephew"),
            (CNLabelContactRelationStepparent, "stepparent"), (CNLabelContactRelationStepmother, "stepmother"),
            (CNLabelContactRelationStepfather, "stepfather"), (CNLabelContactRelationStepchild, "stepchild"),
            (CNLabelContactRelationStepdaughter, "stepdaughter"), (CNLabelContactRelationStepson, "stepson"),
        ]
        for (k, v) in relations { map[k] = v }
        return map
    }()

    /// The slug for a label as the store holds it, or nil for none.
    public static func slug(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let known = builtIn[raw] { return known }
        // A built-in this table does not know yet: `_$!<SomeName>!$_` as
        // `some_name`, not the literal code.
        if raw.hasPrefix("_$!<"), raw.hasSuffix(">!$_") {
            return Labels.slug(snakeCase(String(raw.dropFirst(4).dropLast(4))))
        }
        return Labels.slug(raw)
    }

    /// `YoungerSibling` → `Younger Sibling`, `HomeFAX` → `Home FAX`.
    static func snakeCase(_ s: String) -> String {
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if i > 0, c.isUppercase,
               !chars[i - 1].isUppercase || (i + 1 < chars.count && chars[i + 1].isLowercase) {
                out += " "
            }
            out.append(c)
        }
        return out
    }
}

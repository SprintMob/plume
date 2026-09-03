import ApplicationServices
import XCTest

@testable import parrot

final class FocusRulesTests: XCTestCase {
    private func facts(
        role: String? = nil,
        subrole: String? = nil,
        roleDescription: String? = nil,
        valueSettable: Bool = false,
        selectedTextSettable: Bool = false,
        selectedTextRangeSettable: Bool = false
    ) -> ElementFacts {
        ElementFacts(
            role: role,
            subrole: subrole,
            roleDescription: roleDescription,
            valueSettable: valueSettable,
            selectedTextSettable: selectedTextSettable,
            selectedTextRangeSettable: selectedTextRangeSettable
        )
    }

    // MARK: - The role allow-list

    func testTextFieldIsEditable() {
        XCTAssertTrue(FocusRules.isEditable(facts(role: kAXTextFieldRole as String)))
    }

    func testTextAreaIsEditable() {
        XCTAssertTrue(FocusRules.isEditable(facts(role: kAXTextAreaRole as String)))
    }

    func testComboBoxIsEditable() {
        XCTAssertTrue(FocusRules.isEditable(facts(role: kAXComboBoxRole as String)))
    }

    func testSearchFieldSubroleIsEditable() {
        XCTAssertTrue(
            FocusRules.isEditable(
                facts(role: kAXTextFieldRole as String, subrole: kAXSearchFieldSubrole as String)))
    }

    /// The role allow-list is the cheap half the tree walk leans on, so it has
    /// to answer on its own for the roles above.
    func testRoleAloneSettlesTheAllowList() {
        XCTAssertTrue(FocusRules.isEditableByRole(facts(role: kAXTextFieldRole as String)))
        XCTAssertFalse(FocusRules.isEditableByRole(facts(role: "AXButton")))
    }

    /// A search field reporting no role at all is still a search field. The
    /// shape this replaced only reached the subrole test when a role was
    /// present, so this pins the widened behaviour.
    func testSearchFieldSubroleIsEditableWithNoRole() {
        XCTAssertTrue(
            FocusRules.isEditable(facts(subrole: kAXSearchFieldSubrole as String)))
    }

    // MARK: - Secure fields

    func testSecureTextFieldIsRefused() {
        XCTAssertTrue(FocusRules.isSecure(facts(subrole: kAXSecureTextFieldSubrole as String)))
        XCTAssertFalse(
            FocusRules.isEditable(facts(subrole: kAXSecureTextFieldSubrole as String)))
    }

    /// A password box looks exactly like a text field on every other signal.
    /// The refusal has to beat all of them.
    func testSecureTextFieldIsRefusedDespiteEveryOtherSignal() {
        let passwordBox = facts(
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String,
            roleDescription: "secure text field",
            valueSettable: true,
            selectedTextSettable: true,
            selectedTextRangeSettable: true
        )
        XCTAssertFalse(FocusRules.isEditable(passwordBox))
        XCTAssertFalse(FocusRules.isEditableByRole(passwordBox))
    }

    // MARK: - Settable selection

    func testSettableSelectedTextRangeIsEditableUnderAnUnknownRole() {
        XCTAssertTrue(
            FocusRules.isEditable(
                facts(role: "AXWebArea", selectedTextRangeSettable: true)))
    }

    func testSettableSelectedTextIsEditableUnderAnUnknownRole() {
        XCTAssertTrue(
            FocusRules.isEditable(facts(role: "AXGroup", selectedTextSettable: true)))
    }

    // MARK: - The role-description last resort

    func testRoleDescriptionMentioningTextNeedsASettableValue() {
        XCTAssertTrue(
            FocusRules.isEditable(
                facts(role: "AXGroup", roleDescription: "text entry area", valueSettable: true)))
        XCTAssertFalse(
            FocusRules.isEditable(
                facts(role: "AXGroup", roleDescription: "text entry area", valueSettable: false)))
    }

    /// Known limitation, pinned rather than fixed: the description comes back
    /// localised, so the last-resort rung only fires where the word for text
    /// starts with "text". French and German happen to qualify; Japanese does
    /// not, and such an element falls through to the popover.
    func testRoleDescriptionRungIsLocaleDependent() {
        XCTAssertTrue(
            FocusRules.isEditable(
                facts(role: "AXGroup", roleDescription: "zone de texte", valueSettable: true)),
            "French \"texte\" happens to contain \"text\"")
        XCTAssertFalse(
            FocusRules.isEditable(
                facts(role: "AXGroup", roleDescription: "テキストエリア", valueSettable: true)),
            "Japanese does not, so this rung cannot fire there")
    }

    // MARK: - Things that must stay out

    func testStaticTextIsNotEditable() {
        XCTAssertFalse(FocusRules.isEditable(facts(role: kAXStaticTextRole as String)))
    }

    func testButtonIsNotEditable() {
        XCTAssertFalse(
            FocusRules.isEditable(facts(role: kAXButtonRole as String, valueSettable: true)))
    }

    func testAnElementReportingNothingIsNotEditable() {
        XCTAssertFalse(FocusRules.isEditable(facts()))
    }
}

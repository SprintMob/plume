import AppKit
import ApplicationServices
import Foundation

/// What the accessibility API says about one element, flattened into plain
/// values so the rule below can be decided — and tested — without a live app.
struct ElementFacts: Equatable {
    var role: String?
    var subrole: String?
    var roleDescription: String?
    var valueSettable = false
    var selectedTextSettable = false
    var selectedTextRangeSettable = false
}

/// Whether a transcript may be delivered into an element. Pure: every input it
/// reads is in `ElementFacts`.
enum FocusRules {
    /// A password box. Refused outright, wherever it turns up in the walk —
    /// dictation must never end up in one.
    static func isSecure(_ facts: ElementFacts) -> Bool {
        facts.subrole == kAXSecureTextFieldSubrole as String
    }

    /// The cheap half of the rule: role and subrole settle most elements on
    /// their own, and reading them costs two calls rather than six. The tree
    /// walk leans on this before paying for the rest.
    static func isEditableByRole(_ facts: ElementFacts) -> Bool {
        if isSecure(facts) { return false }
        let editableRoles = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            kAXComboBoxRole as String,
        ]
        if let role = facts.role, editableRoles.contains(role) { return true }
        return facts.subrole == kAXSearchFieldSubrole as String
    }

    static func isEditable(_ facts: ElementFacts) -> Bool {
        if isSecure(facts) { return false }
        if isEditableByRole(facts) { return true }
        if facts.selectedTextSettable || facts.selectedTextRangeSettable { return true }
        // Last resort for controls reporting an app-specific role while still
        // being text underneath. Locale-dependent: the description comes back
        // localised, so this only fires where the word for text starts with
        // "text" — see FocusRulesTests.
        return facts.roleDescription?.lowercased().contains("text") == true
            && facts.valueSettable
    }
}

/// The outcome of one look at the focused element.
struct FocusProbe {
    enum Outcome: Equatable {
        case editable
        case notEditable
        case secureField
        /// The accessibility API would not answer at all.
        case unavailable(AXError)
    }

    enum Match: String {
        case element
        case ancestor
        case descendant
        case none
    }

    var outcome: Outcome
    var facts = ElementFacts()
    var app: String?
    var pid: pid_t?
    var matchedBy: Match = .none

    var isEditable: Bool { outcome == .editable }

    /// One line for `--debug-focus`, carrying everything needed to tell a
    /// missing accessibility tree apart from a genuinely unfocused screen.
    func debugLine(retried: Bool) -> String {
        var parts = ["focus: \(outcomeLabel)"]
        parts.append("app=\(app ?? "?")\(pid.map { "(\($0))" } ?? "")")
        parts.append("role=\(facts.role ?? "-")")
        parts.append("subrole=\(facts.subrole ?? "-")")
        parts.append("desc=\(facts.roleDescription ?? "-")")
        parts.append(
            "settable[value=\(facts.valueSettable) "
                + "selText=\(facts.selectedTextSettable) "
                + "selRange=\(facts.selectedTextRangeSettable)]")
        parts.append("via=\(matchedBy.rawValue)")
        if retried { parts.append("retried-after-wake") }
        return parts.joined(separator: " · ") + "\n"
    }

    private var outcomeLabel: String {
        switch outcome {
        case .editable: return "editable"
        case .notEditable: return "not-editable"
        case .secureField: return "secure-field"
        case .unavailable(let error): return "unavailable(\(error.rawValue))"
        }
    }
}

@MainActor
enum FocusedTextTarget {
    /// Ceiling for one whole probe. The walk below costs several synchronous
    /// cross-process calls per node and runs on the main actor, so a slow app
    /// must not be able to hold the UI hostage.
    private static let probeBudget: TimeInterval = 0.6
    /// Per-call ceiling. Set on the system-wide element, which makes it the
    /// default for every element this process creates.
    private static let messagingTimeout: Float = 0.5

    private static let ancestorHops = 6
    private static let descendantDepth = 4
    private static let descendantNodeBudget = 96

    static var isEditable: Bool { probe().isEditable }

    static func probe() -> FocusProbe {
        let deadline = Date().addingTimeInterval(probeBudget)

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)

        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard status == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return FocusProbe(outcome: .unavailable(status == .success ? .noValue : status))
        }
        let focused = focusedValue as! AXUIElement

        // The focused element is the one worth describing in full: it is what
        // --debug-focus reports, and the only element read six attributes deep.
        let focusedFacts = facts(of: focused)
        let owner = owningApplication(of: focused)
        var probe = FocusProbe(
            outcome: .notEditable,
            facts: focusedFacts,
            app: owner.name,
            pid: owner.pid
        )

        if FocusRules.isSecure(focusedFacts) {
            probe.outcome = .secureField
            return probe
        }
        if FocusRules.isEditable(focusedFacts) {
            probe.outcome = .editable
            probe.matchedBy = .element
            return probe
        }
        if hasEditableAncestor(focused, deadline: deadline) {
            probe.outcome = .editable
            probe.matchedBy = .ancestor
            return probe
        }
        var remainingNodes = descendantNodeBudget
        if containsEditableDescendant(
            focused,
            remainingDepth: descendantDepth,
            remainingNodes: &remainingNodes,
            deadline: deadline
        ) {
            probe.outcome = .editable
            probe.matchedBy = .descendant
        }
        return probe
    }

    /// Staged read: role and subrole first, and the four costlier attributes
    /// only when those did not already settle it.
    private static func isEditableElement(_ element: AXUIElement) -> Bool {
        var facts = ElementFacts(
            role: stringAttribute(kAXRoleAttribute, of: element),
            subrole: stringAttribute(kAXSubroleAttribute, of: element)
        )
        if FocusRules.isSecure(facts) { return false }
        if FocusRules.isEditableByRole(facts) { return true }
        facts.roleDescription = stringAttribute(kAXRoleDescriptionAttribute, of: element)
        facts.valueSettable = isSettable(kAXValueAttribute, on: element)
        facts.selectedTextSettable = isSettable(kAXSelectedTextAttribute, on: element)
        facts.selectedTextRangeSettable = isSettable(kAXSelectedTextRangeAttribute, on: element)
        return FocusRules.isEditable(facts)
    }

    private static func facts(of element: AXUIElement) -> ElementFacts {
        ElementFacts(
            role: stringAttribute(kAXRoleAttribute, of: element),
            subrole: stringAttribute(kAXSubroleAttribute, of: element),
            roleDescription: stringAttribute(kAXRoleDescriptionAttribute, of: element),
            valueSettable: isSettable(kAXValueAttribute, on: element),
            selectedTextSettable: isSettable(kAXSelectedTextAttribute, on: element),
            selectedTextRangeSettable: isSettable(kAXSelectedTextRangeAttribute, on: element)
        )
    }

    private static func isSecureElement(_ element: AXUIElement) -> Bool {
        FocusRules.isSecure(
            ElementFacts(subrole: stringAttribute(kAXSubroleAttribute, of: element)))
    }

    private static func owningApplication(
        of element: AXUIElement
    ) -> (name: String?, pid: pid_t?) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else {
            return (nil, nil)
        }
        let app = NSRunningApplication(processIdentifier: pid)
        return (app?.bundleIdentifier ?? app?.localizedName, pid)
    }

    private static func hasEditableAncestor(
        _ element: AXUIElement,
        deadline: Date
    ) -> Bool {
        var current = element
        for _ in 0..<ancestorHops {
            guard Date() < deadline else { return false }
            guard let parent = elementAttribute(kAXParentAttribute, of: current) else {
                return false
            }
            if isSecureElement(parent) {
                return false
            }
            if isEditableElement(parent) {
                return true
            }
            current = parent
        }
        return false
    }

    private static func containsEditableDescendant(
        _ element: AXUIElement,
        remainingDepth: Int,
        remainingNodes: inout Int,
        deadline: Date
    ) -> Bool {
        guard remainingDepth > 0, remainingNodes > 0, Date() < deadline else { return false }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success, let children = childrenValue as? [AXUIElement] else {
            return false
        }

        for child in children {
            guard remainingNodes > 0, Date() < deadline else { return false }
            remainingNodes -= 1
            if isSecureElement(child) {
                continue
            }
            let childIsTarget =
                boolAttribute(kAXFocusedAttribute, of: child) == true
                && isEditableElement(child)
            if childIsTarget {
                return true
            }
            if containsEditableDescendant(
                child,
                remainingDepth: remainingDepth - 1,
                remainingNodes: &remainingNodes,
                deadline: deadline
            ) {
                return true
            }
        }
        return false
    }

    private static func boolAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func isSettable(
        _ attribute: String,
        on element: AXUIElement
    ) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private static func elementAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }
}

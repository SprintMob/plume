import SwiftUI

/// The handful of shapes every section is built from: a scrolling page, a
/// titled card, a row inside it, and a key cap. Kept in one place so five
/// sections written on five different days still look like one window.

/// A section's scrolling body. The top padding clears the transparent
/// titlebar the window draws its sidebar material up into.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Style.Space.x6) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Style.Space.x6)
            .padding(.top, Style.Space.x6)
            .padding(.bottom, Style.Space.x8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A titled group of rows in a rounded card.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Style.Space.x2) {
            if let title {
                Text(title)
                    .font(Style.font(Style.Text.body, .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, Style.Space.half)
            }
            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Style.Radius.btn))
            .overlay(
                RoundedRectangle(cornerRadius: Style.Radius.btn)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7))
            )
            if let footnote {
                Text(footnote)
                    .font(Style.font(Style.Text.caption))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Style.Space.half)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The hairline between two rows of a group, inset the way macOS insets it.
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, Style.Space.x4)
    }
}

/// A label, an optional line of explanation, and a control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    var help: String?
    @ViewBuilder var control: Control

    init(
        _ title: String,
        detail: String? = nil,
        help: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.help = help
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Style.Space.x3) {
            VStack(alignment: .leading, spacing: Style.Space.half) {
                HStack(spacing: Style.Space.x1) {
                    Text(title).font(Style.font(Style.Text.body, .medium))
                    if let help {
                        Image(systemName: "questionmark.circle")
                            .font(Style.font(Style.Text.caption))
                            .foregroundStyle(.tertiary)
                            .help(help)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(Style.font(Style.Text.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Style.Space.x3)
            control
        }
        .padding(.horizontal, Style.Space.x4)
        .padding(.vertical, Style.Space.x3)
    }
}

/// One key, drawn as the chip a shortcut is printed on.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            // `design: .rounded` was SF Rounded, a second typeface in a single
            // control. It is gone, and the app now has exactly one.
            .font(Style.number(Style.Text.caption, .medium))
            .padding(.horizontal, Style.Space.half * 3)
            .padding(.vertical, Style.Space.half + 1)
            .background(
                Color(nsColor: .quaternaryLabelColor).opacity(0.55),
                in: RoundedRectangle(cornerRadius: Style.Radius.xs)
            )
    }
}

/// A modifier as its glyph, with the side spelled out where the keyboard has
/// two of them.
struct HotkeyCaps: View {
    let hotkey: HotkeyMonitor.Hotkey

    var body: some View {
        HStack(spacing: Style.Space.x1) {
            if let side = hotkey.side {
                Text(side)
                    .font(Style.font(Style.Text.caption))
                    .foregroundStyle(.secondary)
            }
            KeyCap(label: hotkey.glyph)
        }
    }
}

extension HotkeyMonitor.Hotkey {
    /// What the key prints on a Mac keyboard.
    var glyph: String {
        switch self {
        case .fn: return "fn"
        case .leftOption, .rightOption: return "⌥"
        case .leftCommand, .rightCommand: return "⌘"
        case .leftControl, .rightControl: return "⌃"
        case .leftShift, .rightShift: return "⇧"
        }
    }

    /// Nothing for Fn, which exists once; "left" or "right" for the eight
    /// modifiers a keyboard carries on both sides.
    var side: String? {
        switch self {
        case .fn: return nil
        case .leftOption, .leftCommand, .leftControl, .leftShift: return "left"
        case .rightOption, .rightCommand, .rightControl, .rightShift: return "right"
        }
    }
}

/// A sidebar row's glyph. A tint gives it the filled chip the content sections
/// wear; the settings sections are plain, which is what groups them.
struct SidebarIcon: View {
    let symbol: String
    var tint: Color?

    var body: some View {
        Group {
            if let tint {
                RoundedRectangle(cornerRadius: Style.Radius.xs)
                    .fill(tint)
                    .overlay(
                        Image(systemName: symbol)
                            .font(Style.font(Style.Text.caption, .semibold))
                            // On lime, never white: white on lime is 1.13:1.
                            .foregroundStyle(Style.onLime)
                    )
            } else {
                Image(systemName: symbol)
                    .font(Style.font(Style.Text.body))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 19, height: 19)
    }
}

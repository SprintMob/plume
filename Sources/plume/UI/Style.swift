import SwiftUI

/// Every colour, size, space, radius and curve plume paints itself with.
///
/// Two appearance models, and the split is not cosmetic. The overlay pill and
/// the transcript fallback float over another app's window, where a light panel
/// would read as that app's own UI rather than as plume, so they are dark in
/// both system appearances and take `Dark.*` in full. The settings window is a
/// window of ours, which is the surface a macOS user reads as a system surface,
/// so it follows light and dark through the semantic system colours and takes
/// only `lime` from here. Ignoring the appearance setting there would also
/// quietly break Increase Contrast and Reduce Transparency, which
/// `.windowBackgroundColor` and friends honour for free.
///
/// The palette is SprintMob's `hc-*` scale, taken one for one. It is the subset
/// the brand had already drawn for a dark surface, which is exactly what a
/// chrome floating above other apps needs.
///
/// **The one rule that constrains everything.** `lime` has a relative luminance
/// of 0.880: that is 1.13:1 on white and 17.5:1 on `Dark.bg`. It is a fill, and
/// never a foreground on a light surface. `StyleContrastTests` enforces it.
/// The brand states the second half too: lime is for accent and call to action,
/// and never carries a severity.
enum Style {

    /// The one value constant across both generations of the brand, and the
    /// most-used fill in the design source. Fill only.
    static let lime = Color(hex: 0xE0FE75)
    /// What goes on top of a lime fill. Never the reverse.
    static let onLime = Color(hex: 0x0A0A0A)

    /// The floating chrome, dark in both appearances.
    enum Dark {
        static let bg       = Color(hex: 0x0A0A0A)                // hc-bg
        static let elev     = Color(hex: 0x121212)                // hc-elev
        static let elev2    = Color(hex: 0x181818)                // hc-elev-2
        static let ink      = Color(hex: 0xF7F8F3)                // hc-ink      18.6:1 on bg
        static let ink70    = Color(hex: 0xF7F8F3, alpha: 0.72)   // hc-ink-70    9.7:1
        static let ink45    = Color(hex: 0xF7F8F3, alpha: 0.50)   // hc-ink-45    5.1:1, AA at 11pt
        static let ink25    = Color(hex: 0xF7F8F3, alpha: 0.25)   // hc-ink-25
        static let line     = Color(hex: 0xF7F8F3, alpha: 0.14)   // hc-line
        static let lineSoft = Color(hex: 0xF7F8F3, alpha: 0.08)   // hc-line-soft
        /// Severity on a surface that is always dark. Severity in the settings
        /// window stays semantic, because that surface follows the appearance.
        static let critical = Color(hex: 0xFF7A6B)                //             7.8:1
    }

    /// Four sizes, because this app genuinely uses four. The scale in the brand
    /// canvas runs from 118 to 13 and is dimensioned for the web; none of it
    /// transfers to macOS chrome.
    enum Text {
        static let caption: CGFloat = 11
        static let body: CGFloat = 13
        static let title: CGFloat = 17
        static let display: CGFloat = 22
    }

    enum Glyph {
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 22
    }

    /// The single place a typeface is chosen.
    ///
    /// It stays the system font. Euclid Circular B is the brand face and it is
    /// deliberately not embedded: no redistribution licence has been
    /// established, and this repo is going open source, so the .ttf would land
    /// in a public repository and in every release artefact. Even licensed it
    /// would be the wrong face here, because a geometric at 11pt in a dense
    /// settings table loses on the two things that matter at that size, and SF
    /// has a per-size chase and hinting tuned for exactly 11 and 13pt.
    ///
    /// If the licence is ever cleared, the mechanism is one
    /// `CTFontManagerRegisterFontsForURL(_:.process,_)` at launch, and this
    /// function is the only thing that changes.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Tabular figures, for anything whose width should not jump as it counts.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// The brand's strict 4px grid. It governs layout, and only layout: the
    /// internal metrics of a drawn glyph, bar widths and gaps and mark
    /// proportions, do not snap to it.
    enum Space {
        static let half: CGFloat = 2
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8    // radius-sm
        static let btn: CGFloat = 10  // radius-btn
        static let md: CGFloat = 12   // radius-md
        static let lg: CGFloat = 16   // radius-lg
    }

    enum Motion {
        static let entrance = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.28)
        static let level = Animation.easeOut(duration: 0.09)
        static let swap = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)
        /// Must equal the entrance duration. The old value was 0.18 against a
        /// 0.3 animation, which cut every dismissal off at 60%.
        static let dismissDelay: TimeInterval = 0.28
        static let failureDwell: TimeInterval = 2.4
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

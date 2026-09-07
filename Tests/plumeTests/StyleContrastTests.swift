import SwiftUI
import XCTest
@testable import plume

/// The brand states one rule about its own accent: "lime on black passes, lime
/// on white does not: never lime text on a light background." It is the kind of
/// rule that lives in a document, gets forgotten, and comes back as an
/// invisible label. So it is executable here instead.
///
/// The numbers are WCAG relative luminance and contrast ratio, computed from
/// the tokens themselves rather than copied out of the design doc, so changing
/// a hex value has to face these cases.
final class StyleContrastTests: XCTestCase {

    // MARK: - The rule

    /// 1.13:1. Not "low contrast": invisible. This is why the recommended
    /// marker is a lime capsule with dark text on it rather than a lime star,
    /// and why no severity is ever carried by lime.
    func testLimeIsUnusableAsAForegroundOnWhite() {
        XCTAssertLessThan(ratio(Style.lime, on: .white), 3.0)
    }

    func testLimeOnTheDarkSurfaceIsFine() {
        XCTAssertGreaterThan(ratio(Style.lime, on: Style.Dark.bg), 7.0)
    }

    /// What goes on a lime fill. The reverse pairing, light ink on lime, is the
    /// one SwiftUI would pick on its own for `.borderedProminent`, and it is
    /// the reason no button in this app is tinted lime.
    func testTextOnALimeFillIsReadable() {
        XCTAssertGreaterThan(ratio(Style.onLime, on: Style.lime), 7.0)
    }

    // MARK: - The dark scale

    func testEveryInkStepMeetsItsIntendedLevelOnTheDarkBackground() {
        // AAA for body, AA for the two dimmer steps, which are only used at
        // 11pt and above for secondary text.
        XCTAssertGreaterThan(ratio(Style.Dark.ink, on: Style.Dark.bg), 7.0)
        XCTAssertGreaterThan(ratio(Style.Dark.ink70, on: Style.Dark.bg), 7.0)
        XCTAssertGreaterThan(ratio(Style.Dark.ink45, on: Style.Dark.bg), 4.5)
    }

    /// Severity on the floating chrome, which is dark in both appearances. The
    /// settings window keeps the semantic system colours instead, because it
    /// follows the appearance and a value tuned for #0A0A0A would be wrong on
    /// a white window.
    func testCriticalReadsOnTheDarkBackground() {
        XCTAssertGreaterThan(ratio(Style.Dark.critical, on: Style.Dark.bg), 4.5)
    }

    /// ink25 and the two hairlines are decoration, never text. Asserted as
    /// *below* the text threshold so nobody promotes one to a label without
    /// this failing first.
    func testTheHairlinesAreNotTextColours() {
        XCTAssertLessThan(ratio(Style.Dark.ink25, on: Style.Dark.bg), 4.5)
        XCTAssertLessThan(ratio(Style.Dark.line, on: Style.Dark.bg), 4.5)
        XCTAssertLessThan(ratio(Style.Dark.lineSoft, on: Style.Dark.bg), 4.5)
    }

    /// The elevation steps have to be visible against the base or the panel
    /// has no depth, and not so far apart that they read as a different
    /// surface. Both are one-directional, so a plain ratio is the wrong tool;
    /// this compares luminance directly.
    func testTheElevationStepsAreVisibleWithoutBeingLoud() {
        let base = luminance(Style.Dark.bg)
        let elev = luminance(Style.Dark.elev)
        let elev2 = luminance(Style.Dark.elev2)
        XCTAssertGreaterThan(elev, base)
        XCTAssertGreaterThan(elev2, elev)
        XCTAssertLessThan(ratio(Style.Dark.elev2, on: Style.Dark.bg), 2.0)
    }

    // MARK: - The alpha conversions the design doc claims

    /// `hc-line-soft` is #F7F8F3 at 0x14, and 0x14/255 is 0.0784, which the
    /// doc rounds to 0.08. That mattered because the old code wrote
    /// `.white.opacity(0.08)` by hand, and the claim that the token replaces it
    /// exactly is worth holding.
    func testLineSoftMatchesTheAlphaItReplaced() {
        XCTAssertEqual(alpha(Style.Dark.lineSoft), 0.08, accuracy: 0.005)
    }

    func testInk70AndInk45MatchTheirHexAlphas() {
        XCTAssertEqual(alpha(Style.Dark.ink70), 0.72, accuracy: 0.005)
        XCTAssertEqual(alpha(Style.Dark.ink45), 0.50, accuracy: 0.005)
    }

    // MARK: - WCAG

    private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("token is not representable in sRGB")
            return (0, 0, 0, 1)
        }
        return (
            Double(srgb.redComponent),
            Double(srgb.greenComponent),
            Double(srgb.blueComponent),
            Double(srgb.alphaComponent)
        )
    }

    private func alpha(_ color: Color) -> Double {
        components(color).a
    }

    /// Composites over the background first, because half these tokens carry an
    /// alpha and a ratio against an un-composited colour is meaningless.
    private func luminance(_ color: Color, over background: Color? = nil) -> Double {
        let c = components(color)
        var (r, g, b) = (c.r, c.g, c.b)
        if c.a < 1, let background {
            let bg = components(background)
            r = r * c.a + bg.r * (1 - c.a)
            g = g * c.a + bg.g * (1 - c.a)
            b = b * c.a + bg.b * (1 - c.a)
        }
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func ratio(_ foreground: Color, on background: Color) -> Double {
        let f = luminance(foreground, over: background)
        let b = luminance(background)
        let (lighter, darker) = f > b ? (f, b) : (b, f)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

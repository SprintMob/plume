import SwiftUI

/// The two colours plume paints its own chrome in.
///
/// The overlay pill and the transcript fallback are dark whatever the system
/// appearance is: both float over another app's window, where a light panel
/// would read as that app's own UI rather than as plume. The settings window
/// is the opposite case — it is a window of ours, so it takes its greys from
/// the semantic system colours and follows light and dark, and takes only
/// `accent` from here.
enum Style {
    /// The near-black the pill and the fallback panel are filled with.
    static let background = Color(red: 16 / 255, green: 18 / 255, blue: 18 / 255)
    /// Plume's blue. The one colour that stays put across both appearances.
    static let accent = Color(red: 181 / 255, green: 209 / 255, blue: 255 / 255)
}

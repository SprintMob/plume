import AppKit
import SwiftUI

/// Borderless, click-through pill near the bottom of the active screen.
/// Driven by the daemon's hotkey + transcription lifecycle.
@MainActor
final class RecordingOverlay {
    enum State: Equatable {
        case hidden
        case recording
        case locked
        case transcribing
        /// The one new capability in the whole rebrand, and a small one: a
        /// transcription failure was visible only on stderr, which for a daemon
        /// under launchd means nowhere.
        case failed
    }

    private var window: NSPanel?
    private let model = OverlayModel()
    /// Invalidates a pending `hide()` when a new recording starts inside the
    /// dismiss animation window, which would otherwise order the freshly shown
    /// panel back out.
    private var hideGeneration = 0

    func show(_ state: State) {
        ensureWindow()
        guard let window else { return }
        hideGeneration &+= 1
        if state == .recording {
            model.resetLevels()
        }
        let wasHidden = !window.isVisible
        // Reposition and re-order on every show: the active screen and Space
        // can both change between recordings.
        position(window)
        window.orderFrontRegardless()
        if wasHidden {
            // Defer the state change so SwiftUI lays out in the .hidden style
            // first, then animates to the visible style on the next runloop tick.
            DispatchQueue.main.async { [model] in
                model.state = state
            }
        } else {
            model.state = state
        }
    }

    func hide() {
        model.state = .hidden
        hideGeneration &+= 1
        let generation = hideGeneration
        // Let the SwiftUI scale+fade animation play out before yanking the
        // window. This waited 0.18s for a 0.3s animation, so every dismissal
        // was cut off at 60%: the pill did not leave, it disappeared. The
        // delay is now the same token the animation uses.
        DispatchQueue.main.asyncAfter(deadline: .now() + Style.Motion.dismissDelay) { [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.window?.orderOut(nil)
        }
    }

    /// Shows the failure state and takes it away again on its own, because
    /// the panel ignores mouse events and there is nothing to dismiss it with.
    /// The generation token is what lets a new dictation supersede it: without
    /// it, a dictation started inside the dwell would be ordered out by the
    /// timer belonging to the failure it replaced.
    func showFailure() {
        show(.failed)
        hideGeneration &+= 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Style.Motion.failureDwell) {
            [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.hide()
        }
    }

    /// Push a new audio level (0…~1). Safe to call from any thread.
    nonisolated func pushLevel(_ level: Float) {
        Task { @MainActor in
            self.model.pushLevel(level)
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let panel = NSPanel(
            // Wide enough for the failure state. The panel is transparent and
            // click-through, so the slack costs nothing.
            contentRect: NSRect(x: 0, y: 0, width: 176, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above full-screen windows, which sit above .statusBar. Without this
        // the pill is invisible whenever the frontmost app is full-screen.
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: OverlayPill(model: model))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        window = panel
    }

    private func position(_ window: NSPanel) {
        // `NSScreen.main` follows keyboard focus and is nil when no window has
        // it — unreliable for a background agent. The screen under the pointer
        // is the one the user is looking at.
        let pointer = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let frame = window.frame
        let visible = screen.visibleFrame
        let x = visible.midX - frame.width / 2
        let y = visible.minY + 32
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Observable state for the SwiftUI pill.
@MainActor
final class OverlayModel: ObservableObject {
    /// Five, not six. The old six-bar envelope was [0.55, 0.85, 1.0, 1.0,
    /// 0.85, 0.55]: two equal peaks and no centre. Five bars give a real one,
    /// and buy the width for 3pt bars, which land on whole pixels at 1x and 2x
    /// where 2.5pt does not. The count lives in `Bars` with the rest of the
    /// geometry, since the shear reads off the same numbers.
    static let barCount = Bars.count
    private static let envelope: [Float] = [0.52, 0.80, 1.0, 0.80, 0.52]

    @Published var state: RecordingOverlay.State = .hidden
    @Published var levels: [Float] = Array(repeating: 0, count: barCount)

    /// The gain and the jitter are unchanged. They were tuned, and there is no
    /// reason to touch them.
    func pushLevel(_ level: Float) {
        let shaped = min(1.0, sqrt(max(0, level)) * 3.4)
        var next = [Float]()
        next.reserveCapacity(Self.barCount)
        for i in 0..<Self.barCount {
            // Small per-bar jitter so the bars don't all move in lockstep.
            let jitter = Float.random(in: 0.78...1.0)
            next.append(shaped * Self.envelope[i] * jitter)
        }
        levels = next
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

private struct OverlayPill: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        content
            .frame(height: Bars.maximum)
            .padding(.horizontal, Style.Space.x3)
            .padding(.vertical, Style.Space.x2)
            .background(
                Capsule(style: .continuous)
                    .fill(Style.Dark.bg)
            )
            // The single most important change in the redesign. A near-black
            // capsule with a window shadow has no edge at all over a dark
            // terminal or a dark IDE, because the shadow is the only separator
            // and a shadow is invisible on black. At 14% of hc-ink the hairline
            // is invisible over a light window, where the shadow does the work,
            // and it saves the pill entirely over a dark one.
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            // 0.86 anchored at the bottom, not 0 anchored at the centre. Scaling
            // up from nothing is a pop, which reads as playful and smears the
            // window shadow; 0.86 with a fade reads as "it was already there".
            // The bottom anchor matches where the pill actually lives, 32pt off
            // the screen edge.
            .scaleEffect(model.state == .hidden ? 0.86 : 1, anchor: .bottom)
            .opacity(model.state == .hidden ? 0 : 1)
            .animation(Style.Motion.entrance, value: model.state)
    }

    /// Locked is signalled by the rim, not by a second lime element inside.
    /// The 18pt width change animating alongside it is itself the feedback
    /// that says the double-tap was taken.
    private var border: Color {
        model.state == .locked ? Style.lime.opacity(0.45) : Style.Dark.line
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden, .recording:
            Waveform(levels: model.levels)
                .frame(width: Bars.width)
        case .locked:
            HStack(spacing: Style.Space.x2) {
                Image(systemName: "lock.fill")
                    .font(Style.font(Style.Glyph.sm, .semibold))
                    // Not lime: the bars are already lime, and a second lime
                    // element at a different size dilutes the first.
                    .foregroundStyle(Style.Dark.ink70)
                Waveform(levels: model.levels)
                    .frame(width: Bars.width)
            }
        case .transcribing:
            // The same five bars, the same shear, the same lime. Only what
            // drives their height changes, so releasing the key no longer
            // swaps one object for another: the pill stops listening and
            // starts working, visibly the same object. This replaces the
            // system ProgressView, which was the one thing on screen that was
            // not ours and which is the visual language of "this app is stuck".
            TranscribingWaveform()
                .frame(width: Bars.width)
        case .failed:
            HStack(spacing: Style.Space.x2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Style.font(Style.Glyph.sm, .semibold))
                    .foregroundStyle(Style.Dark.critical)
                Text("Dictation failed")
                    .font(Style.font(Style.Text.caption, .medium))
                    .foregroundStyle(Style.Dark.ink)
                    .fixedSize()
            }
        }
    }
}

/// The bar metrics, in one place because the shear reads off them.
private enum Bars {
    static let count = 5
    static let thickness: CGFloat = 3
    static let spacing: CGFloat = 5
    /// At silence, six 2.2pt dots read as "off", which is the opposite of what
    /// the pill is for.
    static let minimum: CGFloat = 7
    static let maximum: CGFloat = 18
    static let width = CGFloat(count) * thickness + CGFloat(count - 1) * spacing

    static func height(for level: Float) -> CGFloat {
        minimum + (maximum - minimum) * CGFloat(min(1, max(0, level)))
    }
}

/// The brand mark is two bars whose ends are cut at 45.7°, both cuts leaning
/// the same way. That motif transfers straight onto a waveform: the bars are
/// sheared rather than capped.
///
/// A literal 45° on a 3pt bar is 0.7pt of lean and cannot be seen, so the shear
/// is the steepest a 3pt bar carries at 18pt tall: 0.20 of the height, which is
/// 11.3° off vertical, leaning the same way as the logo. The departure from the
/// logo's angle is deliberate and written down here rather than discovered.
///
/// The shape paints ±1.8pt outside its own 3pt frame. That is intended: the
/// bars are 8pt apart, so the narrowest horizontal clearance between
/// neighbours is 5pt at any y, and the outer overhang eats 1.8 of the 12pt
/// margin.
private struct ShearedBar: Shape {
    static let shear: CGFloat = 0.20

    func path(in rect: CGRect) -> Path {
        let d = rect.height * Self.shear / 2
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + d, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + d, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - d, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX - d, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: Bars.spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                ShearedBar()
                    .fill(Style.lime)
                    // The height is animated directly, never through
                    // scaleEffect(y:). A shear followed by a vertical scale
                    // straightens the angle as the bar shrinks: at level 0.10
                    // those 11.3° would become roughly 50° and the bar would
                    // fall over. Animating the frame keeps the angle constant,
                    // and five shapes at ~20Hz cost nothing.
                    .frame(width: Bars.thickness, height: Bars.height(for: level))
                    .animation(Style.Motion.level, value: level)
            }
        }
    }
}

/// A bump crossing left to right on a 1.1s period. Driven by TimelineView
/// rather than a Timer so it stops being drawn the moment the pill is off
/// screen.
private struct TranscribingWaveform: View {
    private static let period: TimeInterval = 1.1

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            HStack(alignment: .center, spacing: Bars.spacing) {
                ForEach(0..<Bars.count, id: \.self) { index in
                    ShearedBar()
                        .fill(Style.lime)
                        .frame(width: Bars.thickness, height: Bars.height(for: level(index, phase)))
                }
            }
        }
    }

    /// The bump travels from before the first bar to past the last one, so the
    /// ends of the sweep are as quiet as the middle is loud.
    private func level(_ index: Int, _ phase: Double) -> Float {
        let position = phase * Double(Bars.count + 1) - 1
        let distance = abs(Double(index) - position)
        return Float(max(0, 1 - distance / 1.4))
    }
}

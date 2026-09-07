import AppKit
import SwiftUI

@MainActor
final class TranscriptFallbackPopover {
    private var panel: NSPanel?

    func show(_ transcript: String) {
        hide()
        let panel = makePanel(transcript: transcript)
        self.panel = panel
        positionAtBottomCenter(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(transcript: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 152),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(
            rootView: TranscriptFallbackView(
                transcript: transcript,
                onCopy: { [weak self] in
                    // The dictation put it there before the probe ran, so this
                    // rewrites only if something else has taken the pasteboard
                    // since — which is the whole reason the button exists.
                    TextInjector.copyToPasteboard(transcript)
                    self?.hide()
                },
                onDismiss: { [weak self] in
                    self?.hide()
                }
            )
        )
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// The screen under the pointer, not `NSScreen.main`, which follows
    /// keyboard focus and is nil when no window has it. The overlay pill has
    /// used the pointer's screen all along with a comment saying why; this
    /// panel did not, so it could appear on a different display from the pill
    /// that had just been shown on the one the user was looking at.
    private func positionAtBottomCenter(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 32
            )
        )
    }
}

private struct TranscriptFallbackView: View {
    let transcript: String
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Style.Space.x3) {
            HStack(spacing: Style.Space.x2) {
                // One lime element per surface, and on this one it is the
                // button. A lime glyph up here plus a lime pill down there
                // draws a diagonal that pulls the eye off the transcript,
                // which is the content.
                Image(systemName: "text.cursor")
                    .font(Style.font(Style.Text.body, .semibold))
                    .foregroundStyle(Style.Dark.ink45)

                Text("No text field was focused")
                    .font(Style.font(Style.Text.body, .semibold))
                    .foregroundStyle(Style.Dark.ink)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Style.font(Style.Text.caption, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Style.Dark.ink70)
                .help("Dismiss")
            }

            Text(transcript)
                .font(Style.font(Style.Text.body))
                .foregroundStyle(Style.Dark.ink)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, Style.Space.x3)
                .padding(.vertical, Style.Space.x2)
                // elev2 as the fill, lineSoft as the border. The brand's
                // elevation model separates the two, and the value this
                // replaces was a hairline token doing a surface's job.
                // #181818 on #0A0A0A is a visible step.
                .background(
                    Style.Dark.elev2,
                    in: RoundedRectangle(cornerRadius: Style.Radius.btn)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Style.Radius.btn)
                        .strokeBorder(Style.Dark.lineSoft, lineWidth: 1)
                )

            HStack {
                Text("The text is on the clipboard. Press \u{2318}V where you want it.")
                    .font(Style.font(Style.Text.caption))
                    .foregroundStyle(Style.Dark.ink70)

                Spacer()

                Button(action: onCopy) {
                    Label("Copy again", systemImage: "doc.on.doc")
                        .font(Style.font(Style.Glyph.md, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Style.onLime)
                .padding(.horizontal, Style.Space.x3)
                .padding(.vertical, Style.Space.half * 3)
                .background(
                    Style.lime,
                    in: Capsule()
                )
            }
        }
        .padding(.horizontal, Style.Space.x4)
        .padding(.vertical, Style.Space.x4)
        .background(
            RoundedRectangle(cornerRadius: Style.Radius.lg, style: .continuous)
                .fill(Style.Dark.bg)
        )
        // The same 1pt hairline the pill carries, and for the same reason.
        // These two are meant to read as one object at two sizes.
        .overlay(
            RoundedRectangle(cornerRadius: Style.Radius.lg, style: .continuous)
                .strokeBorder(Style.Dark.line, lineWidth: 1)
        )
    }
}

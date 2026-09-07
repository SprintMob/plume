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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 148),
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

    private func positionAtBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
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
                Image(systemName: "text.cursor")
                    .font(Style.font(Style.Text.body, .semibold))
                    .foregroundStyle(Style.lime)

                Text("No text field selected")
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
                .background(
                    Style.Dark.lineSoft,
                    in: RoundedRectangle(cornerRadius: Style.Radius.btn)
                )

            HStack {
                Text("Copied \u{2014} press \u{2318}V where you want it.")
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
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Style.Radius.lg + 2)
                .fill(Style.Dark.bg)
        )
    }
}

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Style.accent)

                Text("No text field selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.65))
                .help("Dismiss")
            }

            Text(transcript)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            HStack {
                Text("Copied \u{2014} press \u{2318}V where you want it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))

                Spacer()

                Button(action: onCopy) {
                    Label("Copy again", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Style.background)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Style.accent,
                    in: Capsule()
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Style.background)
        )
    }
}

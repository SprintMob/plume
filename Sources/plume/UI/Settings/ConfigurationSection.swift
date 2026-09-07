import SwiftUI

/// The choices that shape a dictation: what starts it, what shows while it
/// runs, and where the text lands.
struct ConfigurationSection: View {
    @ObservedObject var state: DaemonState

    @State private var launchAtLogin = Install.isAgentInstalled
    @State private var launchAgentError: String?

    var body: some View {
        SettingsPage {
            SettingsGroup("Appearance") {
                SettingsRow(
                    "Dictation overlay",
                    detail: "The pill near the bottom of the screen while the microphone is hot."
                ) {
                    Picker("", selection: $state.overlayEnabled) {
                        Text("Classic").tag(true)
                        Text("None").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            SettingsGroup("Keyboard Shortcuts") {
                SettingsRow("Hold-to-talk", detail: "Hold to dictate, release to insert.") {
                    HStack(spacing: 12) {
                        HotkeyCaps(hotkey: state.hotkey)
                        Picker("", selection: $state.hotkey) {
                            ForEach(HotkeyMonitor.Hotkey.allCases, id: \.self) { candidate in
                                Text(candidate.rawValue).tag(candidate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                SettingsDivider()
                // The gesture exists but has no setting behind it. Saying so is
                // better than a control that does nothing.
                SettingsRow(
                    "Lock hands-free",
                    detail: "Double-tap \(state.hotkey.rawValue) to keep recording without holding; tap once to stop."
                ) {
                    Text("Always on")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            SettingsGroup("Application", footnote: launchAgentFootnote) {
                SettingsRow(
                    "Launch at login",
                    detail: "Runs plume in the background from the moment you log in.",
                    help: "Registers ~/Library/LaunchAgents/\(Install.label).plist. The agent never carries your settings as arguments, so everything on this page keeps working."
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(
                    "Text injection",
                    detail: injectionDetail,
                    help: "Paste works everywhere, including terminals and Electron apps, which throw synthesized unicode key events away. Type unicode never touches the pasteboard."
                ) {
                    Picker("", selection: $state.injectMode) {
                        Text("Paste").tag(TextInjector.Mode.paste)
                        Text("Type unicode").tag(TextInjector.Mode.typeUnicode)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
                SettingsDivider()
                SettingsRow(
                    "Keep session history",
                    detail: "Kept in memory only, cleared when plume restarts, never written to disk."
                ) {
                    Toggle("", isOn: $state.sessionHistoryEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .onAppear { launchAtLogin = Install.isAgentInstalled }
        .onChange(of: launchAtLogin) { _, wanted in
            // Also fires on the revert below, where the two already agree.
            guard wanted != Install.isAgentInstalled else { return }
            do {
                if wanted {
                    try Install.writeAgent(logFile: false)
                } else {
                    try Install.removeAgent()
                }
                launchAgentError = nil
            } catch {
                launchAgentError = "\(error)"
                launchAtLogin = !wanted
            }
        }
    }

    private var injectionDetail: String {
        switch state.injectMode {
        case .paste:
            return "Puts the transcript on the pasteboard, sends ⌘V, and puts back what was there."
        case .typeUnicode:
            return "Types the characters directly. Terminals and Electron apps drop them silently."
        }
    }

    private var launchAgentFootnote: String {
        if let launchAgentError {
            return "Couldn't change the launch agent: \(launchAgentError)"
        }
        return "The agent discards plume's output. Run `plume install --launch-at-login --log-file` from a terminal to keep it in ~/Library/Logs/plume.log instead."
    }
}

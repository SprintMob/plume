import SwiftUI

/// Where a dictation's audio comes from, and what happens to everything else
/// playing while it does.
///
/// Two rows, and that is the whole of it: parrot has no sound effects, no
/// silence removal and no normalisation, so there is nothing else to show.
struct SoundSection: View {
    @ObservedObject var state: DaemonState
    let devices: InputDeviceStore

    /// CoreAudio is polled rather than observed — the same policy the menu
    /// bar's Input submenu applies every time it opens.
    @State private var available: [InputDeviceStore.Device] = []
    @State private var selectedUID: String?

    var body: some View {
        SettingsPage {
            SettingsGroup(
                "Input",
                footnote: "Devices are remembered by name, not by number, so a microphone keeps its place across reboots. Unplug the one you picked and parrot falls back to the system default rather than going silent."
            ) {
                SettingsRow("Microphone", detail: microphoneDetail) {
                    Picker("", selection: $selectedUID) {
                        Text("Same as System").tag(String?.none)
                        ForEach(available, id: \.uid) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                        // Without an entry to match it, a remembered device that
                        // is currently unplugged leaves the picker blank, which
                        // reads as broken rather than as unplugged.
                        if let missing = rememberedButMissing {
                            Text("Remembered device — not connected")
                                .tag(String?.some(missing))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
            }

            SettingsGroup("Playback") {
                SettingsRow(
                    "System audio while dictating",
                    detail: "Keeps a browser tab or a music player out of the microphone.",
                    help: "Mutes the active output for the length of the dictation and puts the previous mute — or volume, on AirPods and other Bluetooth devices — back when it ends."
                ) {
                    Picker("", selection: $state.muteOutputEnabled) {
                        Text("Leave playing").tag(false)
                        Text("Mute").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: selectedUID) { _, chosen in
            devices.selectedUID = chosen
        }
    }

    /// The UID of a device that was picked once and is not plugged in now.
    private var rememberedButMissing: String? {
        guard let selectedUID, !available.contains(where: { $0.uid == selectedUID })
        else { return nil }
        return selectedUID
    }

    /// Says what the next dictation will actually open, which is only worth
    /// saying when it is not what the picker shows.
    private var microphoneDetail: String? {
        if rememberedButMissing != nil {
            return "Not connected — recording from the system default until it is back."
        }
        return selectedUID == nil ? "Following whatever macOS is set to." : nil
    }

    private func refresh() {
        available = devices.available()
        selectedUID = devices.selectedUID
    }
}

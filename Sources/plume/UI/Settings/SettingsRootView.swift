import SwiftUI

/// The window's sidebar and the section it is showing.
///
/// Five sections, and only five: plume has no modes, no vocabulary and no
/// per-app rules, so there is nothing behind those to show. A sidebar row that
/// leads nowhere is worse than no row.
struct SettingsRootView: View {
    @ObservedObject var state: DaemonState
    let devices: InputDeviceStore
    @ObservedObject var history: TranscriptHistory

    @State private var section: Section = .home

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case home
        case configuration
        case sound
        case models
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Home"
            case .configuration: return "Configuration"
            case .sound: return "Sound"
            case .models: return "Models"
            case .history: return "History"
            }
        }

        var symbol: String {
            switch self {
            case .home: return "house.fill"
            case .configuration: return "gearshape"
            case .sound: return "speaker.wave.2"
            case .models: return "book"
            case .history: return "clock.arrow.circlepath"
            }
        }

        /// Tinted rows are the ones that show something; plain rows are the
        /// ones that change something.
        var tint: Color? {
            switch self {
            case .home: return .orange
            case .history: return .purple
            case .configuration, .sound, .models: return nil
            }
        }
    }

    private static let settingsSections: [Section] = [.configuration, .sound, .models]

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                row(.home)
                SwiftUI.Section {
                    ForEach(Self.settingsSections) { row($0) }
                }
                SwiftUI.Section {
                    row(.history)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 260)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 520, ideal: 660)
        }
        .navigationTitle("plume")
    }

    private func row(_ section: Section) -> some View {
        Label {
            Text(section.title).font(.system(size: 13, weight: .medium))
        } icon: {
            SidebarIcon(symbol: section.symbol, tint: section.tint)
        }
        .padding(.vertical, 2)
        .tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .home:
            HomeSection(state: state)
        case .configuration:
            ConfigurationSection(state: state)
        case .sound:
            SoundSection(state: state, devices: devices)
        case .models:
            ModelsSection(state: state)
        case .history:
            HistorySection(state: state, history: history)
        }
    }
}

import SwiftUI
import TetherKit

enum BottleTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case library = "Steam Library"
    case logs = "Logs"
    var id: String { rawValue }
}

/// A bottle's page: Overview (settings and run controls), Steam Library, and Logs.
struct BottleDetailView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var tab: BottleTab = .overview
    /// Shared by Overview and the library's Play buttons.
    @State private var debugLogging = false

    private var tabs: [BottleTab] {
        BottleTab.allCases.filter { $0 != .library || SteamInstaller.isInstalled(in: bottle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(tabs) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            switch tab {
            case .overview: BottleOverviewView(bottle: bottle, debugLogging: $debugLogging)
            case .library: SteamLibraryView(bottle: bottle, debugLogging: debugLogging)
            case .logs: LogViewerView(bottle: bottle)
            }
        }
        .navigationTitle(bottle.name)
        .onAppear { debugLogging = model.settings.debugLoggingByDefault }
        .onChange(of: tabs) { _, available in
            if !available.contains(tab) { tab = .overview }
        }
    }
}

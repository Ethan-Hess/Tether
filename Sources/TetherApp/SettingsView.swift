import AppKit
import SwiftUI
import TetherKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var storage: [StorageRow] = []
    @State private var measuring = false

    struct StorageRow: Identifiable {
        let id: String
        let name: String
        let bytes: Int64
    }

    var body: some View {
        Form {
            Section {
                Picker("Graphics backend", selection: setting(\.defaultBackend)) {
                    Text("Automatic").tag(GraphicsBackendID?.none)
                    ForEach(GraphicsBackends.all, id: \.id) { b in Text(b.displayName).tag(Optional(b.id)) }
                }
                Picker("Windows version", selection: setting(\.defaultWindowsVersion)) {
                    ForEach(WindowsVersion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Show performance HUD", isOn: setting(\.defaultShowPerformanceHUD))
            } header: {
                Text("Defaults for new bottles")
            } footer: {
                Text("Existing bottles keep their own settings.")
            }

            Section("Running games") {
                Toggle("Log Wine output by default (slower)", isOn: setting(\.debugLoggingByDefault))
            }

            Section("System") {
                ForEach(model.system.items, id: \.name) { item in
                    LabeledContent {
                        Text(item.detail).foregroundStyle(item.ok ? Color.secondary : Color.red)
                    } label: {
                        Label(item.name, systemImage: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    }
                }
                Button("Re-check") { model.refreshSystem() }
            }

            Section("Runtimes") {
                if model.runtimes.isEmpty { Text("None installed").foregroundStyle(.secondary) }
                ForEach(model.runtimes, id: \.version) { r in
                    LabeledContent("Runtime \(r.version)", value: "Wine \(r.manifest.wineVersion)")
                }
            }

            Section("Storage") {
                LabeledContent("Data folder", value: model.paths.root.path).textSelection(.enabled)
                ForEach(storage) { row in
                    LabeledContent(row.name, value: ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file))
                }
                if measuring { HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary) } }
                HStack {
                    Button("Reveal in Finder") { model.reveal(model.paths.root, missingHint: "Nothing has been created yet.") }
                    Button("Measure Again") { Task { await measure() } }.disabled(measuring)
                }
                Text("To keep data somewhere else, start Tether with the TETHER_HOME environment variable set.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .task { await measure() }
    }

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func measure() async {
        measuring = true
        defer { measuring = false }
        let paths = model.paths
        let bottles = model.bottles
        let runtimes = model.runtimes
        storage = await Task.detached {
            var rows = bottles.map { StorageRow(id: "b-\($0.name)", name: "Bottle: \($0.name)", bytes: DiskUsage.size(of: $0.root)) }
            rows += runtimes.map { StorageRow(id: "r-\($0.version)", name: "Runtime \($0.version)", bytes: DiskUsage.size(of: $0.root)) }
            rows.append(StorageRow(id: "cache", name: "Cache (artwork, safe to delete)", bytes: DiskUsage.size(of: paths.cache)))
            return rows
        }.value
    }
}

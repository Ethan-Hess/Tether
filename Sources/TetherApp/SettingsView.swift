import AppKit
import SwiftUI
import TetherKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow
    @State private var storage: [StorageRow] = []
    @State private var measuring = false
    @State private var installing: RuntimeSource?
    @State private var showingRemove = false

    struct StorageRow: Identifiable {
        let id: String
        let name: String
        let bytes: Int64
    }

    var body: some View {
        @Bindable var updater = updater
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

            Section("Updates") {
                if updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                } else {
                    LabeledContent("Updates", value: "Unavailable: \(updater.unavailableMessage ?? "")")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version", value: AppInfo.display)
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

            runtimesSection

            Section("Storage") {
                LabeledContent("Data folder", value: model.paths.root.path).textSelection(.enabled)
                ForEach(storage) { row in
                    LabeledContent(row.name, value: ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file))
                }
                if measuring { HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary) } }
                HStack {
                    Button("Reveal in Finder") { model.reveal(model.paths.root, missingHint: "Nothing has been created yet.") }
                    Button("Measure Again") { Task { await measure() } }.disabled(measuring)
                    Spacer()
                    Button("Remove Tether Data…", role: .destructive) { showingRemove = true }
                }
                Text("To keep data somewhere else, start Tether with the TETHER_HOME environment variable set.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                Button("Notices and licences…") { openWindow(id: "notices") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 700)
        .task { await measure() }
        .sheet(isPresented: $showingRemove) { RemoveDataSheet() }
        .confirmationDialog(
            "Install runtime \(installing?.version ?? "")?",
            isPresented: Binding(get: { installing != nil }, set: { if !$0 { installing = nil } })
        ) {
            Button("Download and Install") { if let s = installing { model.installRuntime(s) }; installing = nil }
            Button("Cancel", role: .cancel) { installing = nil }
        } message: {
            if let s = installing {
                Text("Downloads about \(s.size / 1_000_000) MB from \(s.url.host ?? "?"). The file is checked against a pinned SHA-256 before anything is unpacked.")
            }
        }
    }

    @ViewBuilder private var runtimesSection: some View {
        Section {
            if model.runtimes.isEmpty { Text("None installed").foregroundStyle(.secondary) }
            ForEach(model.runtimes.reversed(), id: \.version) { r in
                let users = model.bottles.filter { $0.config.runtimeVersion == r.version }.count
                LabeledContent("Runtime \(r.version)") {
                    Text("Wine \(r.manifest.wineVersion)\(r.isEmbedded ? " · built in" : " · installed")\(users > 0 ? " · pinned by \(users)" : "")")
                }
            }
            ForEach(model.installableRuntimes, id: \.version) { s in
                LabeledContent("Runtime \(s.version)") {
                    HStack {
                        Text("Wine \(s.wineVersion) · \(ByteCountFormatter.string(fromByteCount: s.size, countStyle: .file))").foregroundStyle(.secondary)
                        if model.isInstallingRuntime {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Install…") { installing = s }
                        }
                    }
                }
            }
        } header: {
            Text("Wine runtimes")
        } footer: {
            Text("A bottle uses the newest runtime unless you pin one in its settings. Install an older version here to take a bottle back to a runtime that worked.")
        }
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
        let runtimes = model.runtimes.filter { !$0.isEmbedded }
        storage = await Task.detached {
            var rows = bottles.map { StorageRow(id: "b-\($0.name)", name: "Bottle: \($0.name)", bytes: DiskUsage.size(of: $0.root)) }
            rows += runtimes.map { StorageRow(id: "r-\($0.version)", name: "Runtime \($0.version)", bytes: DiskUsage.size(of: $0.root)) }
            rows.append(StorageRow(id: "cache", name: "Cache (artwork, safe to delete)", bytes: DiskUsage.size(of: paths.cache)))
            return rows
        }.value
    }
}

/// Choose what to delete, see how big it is, confirm.
struct RemoveDataSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sizes: [TetherDataCategory: Int64] = [:]
    @State private var chosen: Set<TetherDataCategory> = [.cache]
    @State private var confirming = false

    private static let text: [TetherDataCategory: (String, String)] = [
        .bottles: ("Bottles", "Every bottle, including installed games, Steam and your saves inside them. This is the part you can't get back."),
        .runtimes: ("Wine runtimes", "Runtimes you installed and components you imported. The built-in runtime stays with the app."),
        .cache: ("Cache", "Downloaded artwork. Safe to delete."),
        .settings: ("Settings and profiles", "Your preferences and any game profiles you wrote."),
    ]

    private var busy: Bool { !model.runningBottles.isEmpty || !model.activity.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove Tether Data").font(.title2.bold())
            Text("Pick what to delete. Tether.app itself isn't touched; drag it to the Trash afterwards to uninstall.")
                .foregroundStyle(.secondary)
            ForEach(TetherDataCategory.allCases) { category in
                let info = Self.text[category]!
                Toggle(isOn: Binding(
                    get: { chosen.contains(category) },
                    set: { on in if on { chosen.insert(category) } else { chosen.remove(category) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(info.0).bold()
                            Text(ByteCountFormatter.string(fromByteCount: sizes[category] ?? 0, countStyle: .file)).foregroundStyle(.secondary)
                        }
                        Text(info.1).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if busy {
                Label("Stop every bottle and wait for installs to finish first.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Remove…", role: .destructive) { confirming = true }
                    .disabled(chosen.isEmpty || busy || model.isRemovingData)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            let paths = model.paths
            sizes = await Task.detached { TetherData.summary(paths: paths) }.value
        }
        .confirmationDialog("Permanently delete the selected data?", isPresented: $confirming) {
            Button("Delete", role: .destructive) { model.removeData(chosen); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(chosen.contains(.bottles)
                 ? "This deletes your bottles, installed games and saves. It can't be undone."
                 : "This can't be undone.")
        }
    }
}

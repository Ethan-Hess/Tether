import SwiftUI
import TetherKit

struct BottleDetailView: View {
    @Environment(BottleListModel.self) private var model
    let bottle: Bottle

    var body: some View {
        Form {
            Section("Graphics") {
                Picker("Backend", selection: binding(\.backend)) {
                    Text("Automatic").tag(GraphicsBackendID?.none)
                    ForEach(GraphicsBackends.all, id: \.id) { b in
                        Text(b.displayName).tag(Optional(b.id))
                    }
                }
                Toggle("Performance HUD", isOn: binding(\.showPerformanceHUD))
            }
            Section("Compatibility") {
                Picker("Profile", selection: binding(\.profileID)) {
                    Text("Auto-detect").tag(String?.none)
                    ForEach(model.profiles.profiles) { p in Text(p.name).tag(Optional(p.id)) }
                }
                Picker("Windows version", selection: binding(\.windowsVersion)) {
                    ForEach(WindowsVersion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Sync", selection: binding(\.sync)) {
                    Text("Default (msync)").tag(SyncMode?.none)
                    ForEach(SyncMode.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            }
            if let notes = bottle.config.profileID.flatMap(model.profiles.profile(id:))?.notes {
                Section("Profile notes") { Text(notes).foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent("Location", value: bottle.root.path)
                // TODO: Run executable (NSOpenPanel → Launcher.plan/launch), Open C: drive, Kill bottle.
                Button("Delete Bottle…", role: .destructive) { model.delete(bottle) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<BottleConfig, T>) -> Binding<T> {
        Binding(
            get: { bottle.config[keyPath: keyPath] },
            set: { newValue in
                var updated = bottle
                updated.config[keyPath: keyPath] = newValue
                model.save(updated)
            }
        )
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("System") {
                ForEach(SystemCheck.run().items, id: \.name) { item in
                    LabeledContent {
                        Text(item.detail).foregroundStyle(item.ok ? Color.secondary : Color.red)
                    } label: {
                        Label(item.name, systemImage: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}

import AppKit
import SwiftUI
import TetherKit
import UniformTypeIdentifiers

struct BottleOverviewView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @Binding var debugLogging: Bool

    @State private var confirmingDelete = false
    @State private var confirmingSteam = false
    @State private var renaming = false
    @State private var duplicating = false

    private var running: Bool { model.isRunning(bottle) }
    private var busy: String? { model.activity[bottle.name] }
    private var steamInstalled: Bool { SteamInstaller.isInstalled(in: bottle) }

    var body: some View {
        Form {
            runSection
            if let notes = model.notices[bottle.name], !notes.isEmpty {
                Section("Last launch") {
                    ForEach(notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
                }
            }
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
            AdvancedSection(bottle: bottle)
            Section("Bottle") {
                LabeledContent("Location", value: bottle.root.path).textSelection(.enabled)
                HStack {
                    Button("Open C: Drive") {
                        model.reveal(bottle.driveC, missingHint: "The prefix is created the first time you run something in this bottle.")
                    }
                    Button("Show Logs") {
                        model.reveal(bottle.logsURL, missingHint: "This bottle has no logs yet.")
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([bottle.root]) }
                }
                HStack {
                    Button("Rename…") { renaming = true }
                    Button("Duplicate…") { duplicating = true }
                    Button("Delete Bottle…", role: .destructive) { confirmingDelete = true }
                }
                .disabled(running || busy != nil)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete '\(bottle.name)'?", isPresented: $confirmingDelete) {
            Button("Delete Bottle and Everything in It", role: .destructive) { model.delete(bottle) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the Wine prefix, installed games and saves inside this bottle. It can't be undone.")
        }
        .confirmationDialog("Download and install Steam?", isPresented: $confirmingSteam) {
            Button("Download and Install") { model.installSteam(into: bottle) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloads Valve's SteamSetup.exe from \(SteamInstaller.installerURL.host ?? "?") over https and runs it silently in this bottle. You log in to Steam yourself afterwards; Tether never sees your credentials.")
        }
        .sheet(isPresented: $renaming) {
            NamePromptSheet(title: "Rename Bottle", confirmLabel: "Rename", name: bottle.name) { model.rename(bottle, to: $0) }
        }
        .sheet(isPresented: $duplicating) {
            NamePromptSheet(title: "Duplicate Bottle", confirmLabel: "Duplicate", name: bottle.name + " copy") { model.duplicate(bottle, as: $0) }
        }
    }

    // MARK: - run controls

    private var runSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(running ? Color.green : Color.secondary)
                    .imageScale(.small)
                Text(busy ?? (running ? "Running" : "Stopped"))
                if busy != nil { ProgressView().controlSize(.small) }
                Spacer()
            }
            HStack {
                if steamInstalled {
                    Button("Launch Steam") { model.launchSteam(in: bottle, debug: debugLogging) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Install Steam…") { confirmingSteam = true }
                        .buttonStyle(.borderedProminent)
                }
                Button("Run Executable…") { chooseExecutable() }
                Button("Stop") { model.stop(bottle) }
                    .disabled(!running)
            }
            .disabled(busy != nil || !model.hasRuntime)
            Toggle("Log Wine output for the next run (slower)", isOn: $debugLogging)
            if !model.hasRuntime {
                Text("Games need a Wine runtime first.")
                    .font(.callout).foregroundStyle(.secondary)
                InstallRuntimeButton()
            }
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows program to run in \(bottle.name)"
        panel.allowedContentTypes = ["exe", "msi", "bat"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // An installer may need to be started with /S etc.; arguments live in Advanced.
        model.run(bottle, executable: url.path, debug: debugLogging)
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

/// Launch arguments and environment variables, the app's version of `tether bottle set --arg/--env`.
struct AdvancedSection: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var arguments = ""
    @State private var environment = ""
    @State private var loaded = false

    var body: some View {
        Section("Advanced") {
            VStack(alignment: .leading) {
                Text("Launch arguments (one per line, passed to every program in this bottle)").font(.callout)
                TextEditor(text: $arguments).font(.system(.body, design: .monospaced)).frame(height: 56)
            }
            VStack(alignment: .leading) {
                Text("Environment (KEY=VALUE, one per line)").font(.callout)
                TextEditor(text: $environment).font(.system(.body, design: .monospaced)).frame(height: 56)
                Text("DYLD_*, WINEPREFIX, WINEDLLOVERRIDES and a few others are owned by Tether and ignored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Revert", action: load).disabled(!changed)
                Button("Apply", action: apply).disabled(!changed)
            }
        }
        .onAppear { if !loaded { load(); loaded = true } }
    }

    private var parsedArguments: [String] {
        arguments.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private var parsedEnvironment: [String: String] {
        var result: [String: String] = [:]
        for line in environment.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let key = parts.first, !key.isEmpty, parts.count > 1, !parts[1].isEmpty else { continue }
            result[key] = parts[1]
        }
        return result
    }

    private var changed: Bool {
        parsedArguments != bottle.config.launchArguments || parsedEnvironment != bottle.config.environment
    }

    private func load() {
        arguments = bottle.config.launchArguments.joined(separator: "\n")
        environment = bottle.config.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    private func apply() {
        var updated = bottle
        updated.config.launchArguments = parsedArguments
        updated.config.environment = parsedEnvironment
        model.save(updated)
    }
}

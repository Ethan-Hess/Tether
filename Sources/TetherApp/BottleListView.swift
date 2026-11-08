import SwiftUI
import TetherKit

struct BottleListView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCreate = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            VStack(spacing: 0) {
                RuntimeBanner()
                List(model.bottles, selection: $model.selection) { bottle in
                    HStack {
                        Label(bottle.name, systemImage: "shippingbox")
                        Spacer()
                        if model.isRunning(bottle) {
                            Circle().fill(.green).frame(width: 8, height: 8).help("Running")
                        }
                    }
                    .contextMenu {
                        if model.isRunning(bottle) {
                            Button("Stop") { model.stop(bottle) }
                        }
                        Button("Delete…", role: .destructive) { model.selection = bottle.id }
                            .disabled(model.isRunning(bottle))
                    }
                }
                .overlay {
                    if model.bottles.isEmpty {
                        ContentUnavailableView("No Bottles", systemImage: "shippingbox", description: Text("Create a bottle for each game or launcher."))
                    }
                }
            }
            .navigationTitle("Bottles")
            .toolbar {
                Button { showingCreate = true } label: { Label("New Bottle", systemImage: "plus") }
            }
        } detail: {
            if let bottle = model.bottle(model.selection) {
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                ContentUnavailableView("Select a Bottle", systemImage: "sidebar.left")
            }
        }
        .sheet(isPresented: $showingCreate) { CreateBottleSheet() }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
        ) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert?.message ?? "")
        }
    }
}

struct CreateBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var profileID: String?
    @State private var backend: GraphicsBackendID?
    @State private var windows: WindowsVersion = .win10

    private var problem: String? { NameCheck.problem(name, store: model.store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Bottle").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                Picker("Profile", selection: $profileID) {
                    Text("None").tag(String?.none)
                    ForEach(model.profiles.profiles) { p in Text(p.name).tag(Optional(p.id)) }
                }
                Picker("Graphics backend", selection: $backend) {
                    Text("Automatic").tag(GraphicsBackendID?.none)
                    ForEach(GraphicsBackends.all, id: \.id) { b in Text(b.displayName).tag(Optional(b.id)) }
                }
                Picker("Windows version", selection: $windows) {
                    ForEach(WindowsVersion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            .formStyle(.grouped)
            if !name.isEmpty, let problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
            Text("One game or launcher per bottle keeps the prefix clean. The Wine prefix is created the first time you run something.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    model.create(name: name, config: BottleConfig(backend: backend, profileID: profileID, windowsVersion: windows))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || problem != nil)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

/// A one-field sheet for rename and duplicate.
struct NamePromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirmLabel: String
    @State var name: String
    let onConfirm: (String) -> Void

    private var problem: String? { NameCheck.problem(name, store: model.store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            TextField("Name", text: $name).onSubmit(confirm)
            if let problem, !name.isEmpty { Text(problem).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirmLabel, action: confirm).keyboardShortcut(.defaultAction).disabled(name.isEmpty || problem != nil)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func confirm() {
        guard !name.isEmpty, problem == nil else { return }
        onConfirm(name)
        dismiss()
    }
}

enum NameCheck {
    /// Why `name` can't be used for a new bottle, or nil if it can.
    static func problem(_ name: String, store: BottleStore) -> String? {
        do { try BottleStore.validate(name: name) } catch { return error.localizedDescription }
        return store.exists(name: name) ? "A bottle named '\(name)' already exists." : nil
    }
}

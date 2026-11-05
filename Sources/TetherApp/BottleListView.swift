import SwiftUI
import TetherKit

struct BottleListView: View {
    @Environment(BottleListModel.self) private var model
    @State private var showingCreate = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(model.bottles, selection: $model.selection) { bottle in
                Label(bottle.name, systemImage: "shippingbox")
            }
            .navigationTitle("Bottles")
            .toolbar {
                Button { showingCreate = true } label: { Label("New Bottle", systemImage: "plus") }
            }
            .overlay {
                if model.bottles.isEmpty {
                    ContentUnavailableView("No Bottles", systemImage: "shippingbox", description: Text("Create a bottle for each game or launcher."))
                }
            }
        } detail: {
            if let id = model.selection, let bottle = model.bottles.first(where: { $0.id == id }) {
                BottleDetailView(bottle: bottle)
            } else {
                ContentUnavailableView("Select a Bottle", systemImage: "sidebar.left")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateBottleSheet()
        }
        .alert("Error", isPresented: .constant(model.error != nil)) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
}

struct CreateBottleSheet: View {
    @Environment(BottleListModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var profileID: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Profile", selection: $profileID) {
                Text("None").tag(String?.none)
                ForEach(model.profiles.profiles) { p in Text(p.name).tag(Optional(p.id)) }
            }
        }
        .padding()
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { model.create(name: name, profileID: profileID); dismiss() }
                    .disabled(name.isEmpty)
            }
        }
    }
}

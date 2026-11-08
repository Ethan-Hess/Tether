import SwiftUI
import TetherKit

/// Shown above the bottle list until a Wine runtime is installed.
struct RuntimeBanner: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        if !model.hasRuntime {
            VStack(alignment: .leading, spacing: 8) {
                Label("No Wine runtime installed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if model.isInstallingRuntime {
                    HStack { ProgressView().controlSize(.small); Text("Downloading and verifying…") }
                } else {
                    Button("Install Runtime…") { confirming = true }
                        .disabled(model.runtimeSource == nil)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 8)
            .confirmationDialog("Install runtime \(model.runtimeSource?.version ?? "")?", isPresented: $confirming) {
                Button("Download and Install") { model.installRuntime() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let s = model.runtimeSource {
                    Text("Downloads about \(s.size / 1_000_000) MB from \(s.url.host ?? "?"). The file is checked against a pinned SHA-256 before anything is unpacked.")
                }
            }
        }
    }

    private var detail: String {
        let canRun = model.system.items.first { $0.name.hasPrefix("macOS ≥ 26.4") }?.ok ?? true
        return canRun
            ? "Games need one. Tether downloads a pinned build and verifies it first."
            : "This Mac is older than macOS 26.4, which the current runtime needs. You can still set up bottles."
    }
}

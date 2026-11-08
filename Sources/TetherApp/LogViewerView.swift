import AppKit
import SwiftUI
import TetherKit

/// Reads the bottle's Wine log one launch at a time.
struct LogViewerView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    @State private var sessions: [LaunchLog.Session] = []
    @State private var selected: Int?
    @State private var shown = ""
    @State private var confirmingClear = false
    private let maxShownLines = 2000

    private var running: Bool { model.isRunning(bottle) }
    private var current: LaunchLog.Session? { sessions.first { $0.id == selected } }
    private var logFile: URL { bottle.logsURL.appendingPathComponent("wine.log") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Launch", selection: $selected) {
                    ForEach(sessions.reversed()) { s in Text(title(s)).tag(Optional(s.id)) }
                }
                .frame(maxWidth: 380)
                .disabled(sessions.isEmpty)
                Spacer()
                Button("Copy") { model.copyToPasteboard(current?.text ?? "") }.disabled(current == nil)
                Button("Copy Diagnostics") { model.copyToPasteboard(model.diagnostics(for: bottle, sessions: sessions)) }
                Button("Reveal File") { model.reveal(logFile, missingHint: "This bottle has no log yet.") }
                Button("Clear…", role: .destructive) { confirmingClear = true }
                    .disabled(sessions.isEmpty || running)
            }
            .padding([.horizontal, .bottom])

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Log Yet",
                    systemImage: "doc.text",
                    description: Text("Turn on \"Log Wine output\" in Overview and run something. Each launch shows up here.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(shown.isEmpty ? "(no output)" : shown)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .background(.quaternary.opacity(0.3))
                    .onChange(of: shown) { _, _ in if running { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
        }
        .task(id: running) {
            await reload()
            while model.isRunning(bottle), !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await reload()
            }
        }
        .onChange(of: selected) { _, _ in updateShown() }
        .confirmationDialog("Clear this bottle's log?", isPresented: $confirmingClear) {
            Button("Clear Log", role: .destructive) {
                do { try LaunchLog.clear(bottle) } catch { model.fail("Couldn't clear the log", error) }
                Task { await reload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every launch's output for \(bottle.name). Game saves and files are not affected.")
        }
    }

    private func title(_ s: LaunchLog.Session) -> String {
        let when = s.start.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "Earlier"
        return "\(when) · \(s.executable)"
    }

    private func reload() async {
        let bottle = self.bottle
        let loaded = await Task.detached { LaunchLog.sessions(for: bottle) }.value
        // Keep following the newest launch unless the user picked an older one.
        let followingLatest = selected == nil || selected == sessions.last?.id
        sessions = loaded
        if followingLatest || !loaded.contains(where: { $0.id == selected }) { selected = loaded.last?.id }
        updateShown()
    }

    private func updateShown() {
        guard let text = current?.text else { shown = ""; return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        shown = lines.count > maxShownLines
            ? "… \(lines.count - maxShownLines) earlier lines not shown (use Copy for everything)\n" + lines.suffix(maxShownLines).joined(separator: "\n")
            : text
    }
}

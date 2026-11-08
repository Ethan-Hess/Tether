import AppKit
import SwiftUI
import TetherKit

struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Tether").font(.title.bold())
            Text("Version \(AppInfo.display)").foregroundStyle(.secondary)
            Text("Run Windows games on Apple Silicon Macs. Open source, no telemetry, nothing injected into games.")
                .multilineTextAlignment(.center).font(.callout)
            HStack {
                Link("Source code", destination: URL(string: "https://github.com/Ethan-Hess/Tether")!)
                Button("Notices…") { openWindow(id: "notices") }
            }
            Text("Tether is free software under the LGPL-2.1. It bundles open-source components; their licences and source links are under Notices.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 380)
    }
}

/// Third-party licences and where to get their source.
struct NoticesView: View {
    private let catalog = NoticesCatalog.bundled()
    @State private var selection: String?

    private var selected: NoticeComponent? { catalog.components.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(catalog.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(catalog.components.filter { $0.group == group }) { c in
                            HStack {
                                Text(c.name).lineLimit(2)
                                if !c.verified {
                                    Spacer()
                                    Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                                        .help("The licence rests on package metadata and hasn't been checked against the source yet.")
                                }
                            }
                            .tag(c.id)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let c = selected { detail(c) } else { overview }
        }
        .frame(minWidth: 760, minHeight: 480)
        .navigationTitle("Notices")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notices").font(.title2.bold())
            Text("Tether is free software. The Wine runtime it runs games with is built by the Mach9 project from Wine, FEX, DXMT, vkd3d-proton and Mesa, and ships with libraries under the licences listed here.")
            Text("Pick a component to read its licence and find its source code. Where a licence requires it, the source for the exact build shipped is linked from the component, and the libraries are included as separate, replaceable files.")
            Text("A ? marks a component whose licence still rests on package metadata and hasn't been checked against its source.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ c: NoticeComponent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(c.name).font(.title2.bold())
                LabeledContent("Licence", value: c.license)
                if let v = c.version { LabeledContent("Version", value: v) }
                LabeledContent("How established", value: c.basis)
                Link("Source code", destination: c.sourceURL)
                if let note = c.note { Text(note).foregroundStyle(.secondary) }
                ForEach(c.licenseFiles, id: \.self) { file in
                    Divider()
                    Text(file).font(.caption).foregroundStyle(.secondary)
                    Text(NoticesCatalog.licenseText(file: file) ?? "(licence text missing from this build)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

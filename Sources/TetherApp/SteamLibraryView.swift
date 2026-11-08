import SwiftUI
import TetherKit

/// Games Steam reports as installed in this bottle, with a Play button for each.
struct SteamLibraryView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    let debugLogging: Bool

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)]

    var body: some View {
        let apps = model.steamApps[bottle.name]
        VStack(spacing: 0) {
            HStack {
                Text(apps.map { "\($0.count) installed" } ?? "Reading library…").foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.loadLibrary(bottle) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .padding([.horizontal, .bottom])

            if let apps {
                if apps.isEmpty {
                    ContentUnavailableView(
                        "No Games Yet",
                        systemImage: "gamecontroller",
                        description: Text("Launch Steam from Overview, log in and install a game. It will show up here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(apps) { app in GameCard(bottle: bottle, app: app, debugLogging: debugLogging) }
                        }
                        .padding([.horizontal, .bottom])
                    }
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        // Re-read when the bottle starts or stops (an install or update just finished, say).
        .task(id: model.runStateVersion) {
            await model.loadLibrary(bottle)
            // While this tab is open, notice games started from Steam's own window too.
            while !Task.isCancelled {
                await model.adoptRunningGames(in: bottle)
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }
}

private struct GameCard: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    let app: SteamApp
    let debugLogging: Bool

    private var profile: GameProfile? { model.profiles.match(steamAppID: app.appID) }
    private var canPlay: Bool { app.isFullyInstalled && model.hasRuntime && !model.isBusy(bottle) }
    private var phase: GamePhase { model.phase(of: app, in: bottle) }
    /// Another game in this bottle is launching or running.
    private var otherActive: SteamApp? {
        model.activeGame(in: bottle).flatMap { $0.appID == app.appID ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
            Text(app.name).font(.headline).lineLimit(2)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let profile { Text("Profile: \(profile.name)").font(.caption).foregroundStyle(.secondary) }
                if !app.isFullyInstalled { Text("Incomplete install").font(.caption.bold()).foregroundStyle(.orange) }
                switch phase {
                case .launching:
                    Text("Starting Steam and the game…").font(.caption).foregroundStyle(.secondary)
                case .running:
                    Label("Running", systemImage: "circle.fill").font(.caption.bold()).foregroundStyle(.green)
                case .idle:
                    EmptyView()
                }
            }
            playButton
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(phase == .running ? Color.green.opacity(0.7) : .clear, lineWidth: 2))
    }

    /// Play, then a greyed-out "Launching…", then Stop while the game runs.
    @ViewBuilder private var playButton: some View {
        switch phase {
        case .idle:
            Button { model.launchGame(in: bottle, app: app, debug: debugLogging) } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPlay || otherActive != nil)
            .help(otherActive.map { "\($0.name) is already running or starting." } ?? "")
        case .launching:
            Button {} label: {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Launching…") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)
        case .running:
            Button(role: .destructive) { model.stopGame(in: bottle, app: app) } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Ask \(app.name) to quit")
        }
    }

    @ViewBuilder private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Group {
            if let url = model.artwork[app.appID] {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "gamecontroller").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(460.0 / 215.0, contentMode: .fit)
        .clipShape(shape)
    }

    private var detail: String {
        var parts: [String] = []
        if let size = app.sizeOnDisk { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let played = app.lastPlayed {
            parts.append("Played \(played.formatted(.relative(presentation: .named)))")
        } else if let updated = app.lastUpdated {
            parts.append("Updated \(updated.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

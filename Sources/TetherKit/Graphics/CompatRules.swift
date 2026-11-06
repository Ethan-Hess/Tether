import Foundation

/// One rule for the wrapped runtime's compat database, the text the runtime reads from
/// `WINE_COMPATDB_FILE` to choose a graphics implementation per process.
///
/// A rule is a line of `key=value` fields joined by `;`:
///
///     exe=*;dxgi=wined3d
///     exe=steam:2357570;dxgi=dxmt
///     exe=Game.exe;d3d9=wined3d;metal_hud=true
///
/// Tether emits only `exe`, `dxgi`, `d3d9` and `metal_hud`. The format can also carry arguments,
/// environment variables and DLL overrides; those are deliberately not expressible here, which
/// keeps this channel inside ADR 0003's boundary (translation-surface choices only).
public struct CompatRule: Hashable, Sendable {
    public enum Exe: Hashable, Sendable {
        /// Every process (`*`).
        case any
        /// A program's file name, matched case-insensitively by the runtime.
        case name(String)
        /// Any process that holds this Steam app ID (`steam:<appid>`), whatever its file name.
        case steam(UInt32)
    }

    public enum Dxgi: String, Sendable { case dxmt, wined3d }
    public enum D3D9: String, Sendable { case mtld3d, wined3d }

    public var exe: Exe
    public var dxgi: Dxgi?
    public var d3d9: D3D9?
    public var metalHUD: Bool?

    public init(_ exe: Exe, dxgi: Dxgi? = nil, d3d9: D3D9? = nil, metalHUD: Bool? = nil) {
        self.exe = exe
        self.dxgi = dxgi
        self.d3d9 = d3d9
        self.metalHUD = metalHUD
    }

    /// A rule that sets nothing is never written.
    public var isEmpty: Bool { dxgi == nil && d3d9 == nil && metalHUD == nil }

    /// Whether `name` is a plain program file name the runtime can match: non-empty, no path
    /// separators, no control characters, not the wildcard, and no `:` (reserved for `steam:`).
    public static func isValidExeName(_ name: String) -> Bool {
        guard !name.isEmpty, name != "*" else { return false }
        return !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F || $0 == "/" || $0 == "\\" || $0 == ":" }
    }

    /// The runtime's escaping: `%`, `;` and ASCII control characters become uppercase `%XX`.
    static func escape(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            if scalar == "%" || scalar == ";" || scalar.value < 0x20 || scalar.value == 0x7F {
                out += String(format: "%%%02X", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// The rule as one line, fields in the runtime's canonical order.
    public func render() -> String {
        var fields: [String] = []
        switch exe {
        case .any: fields.append("exe=*")
        case .name(let n): fields.append("exe=\(Self.escape(n))")
        case .steam(let id): fields.append("exe=steam:\(id)")
        }
        if let dxgi { fields.append("dxgi=\(dxgi.rawValue)") }
        if let d3d9 { fields.append("d3d9=\(d3d9.rawValue)") }
        if let metalHUD { fields.append("metal_hud=\(metalHUD)") }
        return fields.joined(separator: ";")
    }
}

/// An ordered list of rules, written to the bottle's rules file before each launch.
public struct CompatTable: Hashable, Sendable {
    public private(set) var rules: [CompatRule]

    public init(_ rules: [CompatRule] = []) {
        self.rules = rules.filter { !$0.isEmpty }
    }

    public mutating func add(_ rule: CompatRule) {
        if !rule.isEmpty { rules.append(rule) }
    }

    /// One rule per line, no trailing line break.
    public var text: String { rules.map { $0.render() }.joined(separator: "\n") }

    /// True when any rule moves D3D10/11/12 to wined3d, which has no D3D12.
    public var disablesD3D12: Bool { rules.contains { $0.dxgi == .wined3d } }
}

/// Builds the rules for a launch from the bottle's and profiles' backend choices.
public enum CompatRuleBuilder {
    /// What a backend means in the runtime's terms, or nil if the runtime doesn't offer it
    /// (`dxvk`, `d3dmetal`) or leaves the choice to itself (`runtime`).
    public static func choice(for id: GraphicsBackendID) -> (dxgi: CompatRule.Dxgi, d3d9: CompatRule.D3D9?)? {
        switch id {
        case .dxmt: return (.dxmt, nil)
        case .wined3d: return (.wined3d, .wined3d)
        case .dxvk, .d3dmetal, .runtimeManaged: return nil
        }
    }

    /// First backend in `ids` the runtime can honour.
    public static func firstSupported(_ ids: [GraphicsBackendID]) -> GraphicsBackendID? {
        ids.first { choice(for: $0) != nil }
    }

    /// Launchers whose children inherit their environment, so per-program settings such as the
    /// Metal HUD must not be put on them.
    static let launcherExecutables: Set<String> = ["steam.exe"]

    /// - An explicit, supported bottle backend becomes one launch-wide rule and wins everywhere,
    ///   as it does in `GraphicsBackends.resolve`.
    /// - Otherwise every profile with a supported preference gets rules for its executables and
    ///   Steam app IDs (so they are in place when Steam starts a game).
    /// - With the HUD on, a direct run gets `metal_hud` on its own executable. Steam-started
    ///   games get no HUD yet: children of a store client inherit it, so it can't go on Steam.
    /// - With no choice anywhere, the table is empty and the runtime decides.
    public static func build(bottle: Bottle, profiles: [GameProfile], launchedExecutable: String?) -> CompatTable {
        var table = CompatTable()

        if let id = bottle.config.backend, let choice = choice(for: id) {
            table.add(CompatRule(.any, dxgi: choice.dxgi, d3d9: choice.d3d9))
        } else {
            for profile in profiles.sorted(by: { $0.id < $1.id }) {
                guard let id = firstSupported(profile.backendPreference), let choice = choice(for: id) else { continue }
                for exe in profile.executables where CompatRule.isValidExeName(exe) {
                    table.add(CompatRule(.name(exe), dxgi: choice.dxgi, d3d9: choice.d3d9))
                }
                for appID in profile.steamAppIDs where appID > 0 && appID <= Int(UInt32.max) {
                    table.add(CompatRule(.steam(UInt32(appID)), dxgi: choice.dxgi, d3d9: choice.d3d9))
                }
            }
        }

        if bottle.config.showPerformanceHUD, let launched = launchedExecutable {
            let name = launched.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
            if CompatRule.isValidExeName(name), !launcherExecutables.contains(name.lowercased()) {
                var rules = table.rules
                if let i = rules.firstIndex(where: { rule in
                    if case .name(let n) = rule.exe { return n.caseInsensitiveCompare(name) == .orderedSame }
                    return false
                }) {
                    rules[i].metalHUD = true
                } else {
                    rules.append(CompatRule(.name(name), metalHUD: true))
                }
                table = CompatTable(rules)
            }
        }
        return table
    }
}

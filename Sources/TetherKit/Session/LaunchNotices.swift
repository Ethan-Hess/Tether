import Foundation

/// Human-readable notes about a launch plan, shared by the CLI (stderr) and the app (inline).
public enum LaunchNotices {
    /// Policy actions taken on the bottle/profile configuration (ADR 0003).
    public static func policyWarnings(_ env: LaunchEnvironment) -> [String] {
        env.rejectedOverrides.map { "warning: DLL override '\($0.dll)' blocked by policy (docs/adr/0003-no-process-injection.md)" }
            + env.rejectedEnvironmentKeys.map { "warning: environment key '\($0)' is protected and was ignored" }
    }

    /// Cases where the selected backend can't be applied, or has known limits.
    public static func backendNotices(_ plan: LaunchPlan) -> [String] {
        var notes: [String] = []
        if let ignored = plan.ignoredBackendChoice {
            let why = plan.runtime.supports(feature: GraphicsBackends.compatRulesFeature)
                ? "it offers dxmt and wined3d"
                : "it chooses the backend itself"
            notes.append("note: the bottle's '\(ignored.rawValue)' backend can't be applied with this runtime (\(why)), so the setting has no effect")
        }
        if plan.compatRules.disablesD3D12 {
            notes.append("note: wined3d has no Direct3D 12, so games that need it won't start with this backend")
        }
        return notes
    }

    public static func messages(for plan: LaunchPlan) -> [String] {
        policyWarnings(plan.environment) + backendNotices(plan)
    }
}

# ADR 0001: Swift + SwiftUI host app

**Status:** Accepted

## Context
The host app manages bottles, runtimes, and launches. It needs low resource use while a game runs, first-class macOS integration (sandbox-free file access, codesigning, notarization, Metal/Rosetta checks), and a UI that feels native.

## Decision
Write the host in Swift. A UI-free library (`TetherKit`) holds all logic, and two thin front ends sit on top: a SwiftUI app (`TetherApp`) and a CLI (`tether`). Build with SwiftPM.

## Consequences
- The app is idle while a game runs, and the game never shares a process with UI frameworks.
- Logic is unit-testable without UI. The CLI makes launches scriptable and debuggable (`tether env`).
- macOS only. That's acceptable, because the project's purpose is macOS.
- Contributors need Swift 6.

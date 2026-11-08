import Foundation
import Testing
@testable import TetherKit

@Suite struct GameProcessesTests {
    let home = TempHome()

    @Test func parsesPsOutput() {
        let out = "    1 /sbin/launchd\n  4242 wine-preloader C:\\Program Files (x86)\\Steam\\steam.exe -silent\n\nbad line\n"
        let entries = ProcessList.parse(out)
        #expect(entries.map(\.pid) == [1, 4242])
        #expect(entries[1].command == "wine-preloader C:\\Program Files (x86)\\Steam\\steam.exe -silent")
    }

    @Test func steamClientIsNotItsWebHelperOrReporter() {
        #expect(SteamClientProcess.isClient("C:\\Program Files (x86)\\Steam\\steam.exe -silent"))
        #expect(SteamClientProcess.isClient("steam.exe"))
        #expect(!SteamClientProcess.isClient("C:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win64\\steamwebhelper.exe --type=renderer"))
        #expect(!SteamClientProcess.isClient("C:\\Program Files (x86)\\Steam\\steamerrorreporter64.exe -pid=1516"))
        #expect(!SteamClientProcess.isClient("C:\\x\\notsteam.exe"))
        #expect(SteamClientProcess.isRunning(in: [ProcessEntry(pid: 5, command: "wine C:\\Program Files (x86)\\Steam\\steam.exe")]))
        #expect(!SteamClientProcess.isRunning(in: []))
    }

    // MARK: Steam's game-process log

    private let sample = """
    [2026-11-08 10:02:08] Client version: 1792618285
    [2026-11-08 10:02:08] SSGL: UI mode (0->7)
    [2026-11-08 10:03:04] AppID 3480990 adding PID 1516 as a tracked process ""C:\\g\\Orcs.exe""
    [2026-11-08 10:03:04] SSGL: InternalUpdateClientGame indicates change to games list
    [2026-11-08 10:03:05] AppID 3480990 adding PID 1532 as a tracked process ""C:\\g\\UnityCrashHandler64.exe" --attach 1516 38801408"
    [2026-11-08 10:03:11] AppID 3480990 adding PID 1884 as a tracked process "C:\\steamerrorreporter64.exe -pid=1516"
    """

    @Test func parsesTrackedPIDsPerApp() {
        #expect(SteamGameProcessLog.parse(sample) == [3480990: [1516, 1532, 1884]])
    }

    @Test func aGameIsGoneOnceItsProcessesAreUntrackedOrRemoved() {
        let ended = sample + """

        [2026-11-08 10:03:27] AppID 3480990 no longer tracking PID 1884, exit code 0
        [2026-11-08 10:03:27] AppID 3480990 no longer tracking PID 1532, exit code 0
        [2026-11-08 10:03:27] AppID 3480990 no longer tracking PID 1516, exit code 0
        [2026-11-08 10:03:27] Remove 3480990 from running list
        """
        #expect(SteamGameProcessLog.parse(ended).isEmpty)
        let partly = sample + "\nAppID 3480990 no longer tracking PID 1884, exit code 0"
        #expect(SteamGameProcessLog.parse(partly) == [3480990: [1516, 1532]])
        #expect(SteamGameProcessLog.parse(sample + "\n[t] Remove 3480990 from running list").isEmpty)
    }

    @Test func aSteamRestartForgetsEveryRunningGame() {
        let text = sample + "\n[t] Client version: 1792618285\n[t] AppID 7 adding PID 9 as a tracked process \"x\""
        #expect(SteamGameProcessLog.parse(text) == [7: [9]])
    }

    @Test func readsWindowsLineEndings() throws {
        // Steam's own log files end lines with \r\n, which Swift treats as a single character.
        let crlf = sample.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n\r\n[t] Remove 3480990 from running list\r\n[t] Client version: 1\r\n[t] AppID 9 adding PID 5 as a tracked process \"x\"\r\n"
        #expect(SteamGameProcessLog.parse(crlf) == [9: [5]])
        let bottle = try steamLog(sample.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n")
        #expect(SteamGameProcessLog.tracked(for: bottle) == [3480990: [1516, 1532, 1884]])
        // Starting mid-file (an offset inside a line) must still work.
        #expect(SteamGameProcessLog.tracked(for: bottle, sinceOffset: 120)[3480990]?.isEmpty == false)
    }

    @Test func tracksSeveralAppsAndIgnoresNoise() {
        let text = """
        garbage
        [t] AppID 1 adding PID 10 as a tracked process "a"
        [t] AppID 2 adding PID 20 as a tracked process "b"
        [t] AppID x adding PID y as a tracked process "c"
        [t] AppID 1 no longer tracking PID 10, exit code 0
        """
        #expect(SteamGameProcessLog.parse(text) == [2: [20]])
    }

    private func steamLog(_ text: String) throws -> Bottle {
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let url = SteamGameProcessLog.url(for: bottle)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return bottle
    }

    @Test func readsTheLogOfOneBottle() throws {
        let bottle = try steamLog(sample + "\n")
        #expect(SteamGameProcessLog.tracked(for: bottle)[3480990] == [1516, 1532, 1884])
        let other = try BottleStore(paths: home.paths).create(name: "other")
        #expect(SteamGameProcessLog.tracked(for: other).isEmpty, "a bottle without Steam has no games")
    }

    @Test func onlyCountsWhatWasWrittenAfterTheLaunchBegan() throws {
        let bottle = try steamLog(sample)
        let offset = SteamGameProcessLog.size(for: bottle)
        #expect(SteamGameProcessLog.tracked(for: bottle, sinceOffset: offset).isEmpty, "a game from before the click must not count")
        let handle = try FileHandle(forWritingTo: SteamGameProcessLog.url(for: bottle))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n[t] AppID 5 adding PID 77 as a tracked process \"new\"\n".utf8))
        try handle.close()
        #expect(SteamGameProcessLog.tracked(for: bottle, sinceOffset: offset) == [5: [77]])
    }

    // MARK: incremental reader

    private func append(_ text: String, to bottle: Bottle) throws {
        let h = try FileHandle(forWritingTo: SteamGameProcessLog.url(for: bottle))
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    @Test func readerOnlyParsesWhatWasAppended() throws {
        let bottle = try steamLog("[t] Client version: 1\r\n")
        var reader = SteamGameProcessLog.Reader(bottle: bottle)
        #expect(reader.tracked.isEmpty)
        try append("[t] AppID 1 adding PID 10 as a tracked process \"a\"\r\n", to: bottle)
        reader.advance(bottle)
        #expect(reader.tracked == [1: [10]])
        try append("[t] AppID 2 adding PID 20 as a tracked process \"b\"\r\n[t] AppID 1 no longer tracking PID 10, exit code 0\r\n", to: bottle)
        reader.advance(bottle)
        #expect(reader.tracked == [2: [20]])
        reader.advance(bottle) // nothing new: nothing changes
        #expect(reader.tracked == [2: [20]])
    }

    @Test func readerWaitsForAHalfWrittenLine() throws {
        let bottle = try steamLog("")
        var reader = SteamGameProcessLog.Reader(bottle: bottle)
        try append("[t] AppID 3 adding PID 30 as a tra", to: bottle)
        reader.advance(bottle)
        #expect(reader.tracked.isEmpty, "a line Steam is still writing must not be parsed")
        try append("cked process \"c\"\r\n", to: bottle)
        reader.advance(bottle)
        #expect(reader.tracked == [3: [30]])
    }

    @Test func readerStartsAfterAGivenOffsetEvenMidLine() throws {
        let bottle = try steamLog(sample.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n")
        let size = SteamGameProcessLog.size(for: bottle)
        var fromEnd = SteamGameProcessLog.Reader(bottle: bottle, startingAt: size)
        #expect(fromEnd.tracked.isEmpty)
        try append("[t] AppID 8 adding PID 80 as a tracked process \"d\"\r\n", to: bottle)
        fromEnd.advance(bottle)
        #expect(fromEnd.tracked == [8: [80]])
        // The session view starts from the last Client version, whatever came before.
        #expect(SteamGameProcessLog.Reader(bottle: bottle).tracked[3480990] == [1516, 1532, 1884])
    }

    @Test func readerStartsOverWhenTheLogIsReplaced() throws {
        let bottle = try steamLog(sample + "\n")
        var reader = SteamGameProcessLog.Reader(bottle: bottle)
        #expect(reader.tracked[3480990] != nil)
        try Data("[t] AppID 4 adding PID 40 as a tracked process \"e\"\n".utf8).write(to: SteamGameProcessLog.url(for: bottle))
        reader.advance(bottle)
        #expect(reader.tracked == [4: [40]], "a shorter file is a new file")
    }

    @Test func readerCopesWithMultibyteTextSplitAcrossReads() throws {
        let bottle = try steamLog("")
        var reader = SteamGameProcessLog.Reader(bottle: bottle)
        let line = "[t] AppID 5 adding PID 50 as a tracked process \"C:\\Spiel\\Größe\\g.exe\"\r\n"
        let bytes = Array(line.utf8)
        let split = bytes.firstIndex(of: 0xC3)! + 1 // between the two bytes of "ö"
        let h = try FileHandle(forWritingTo: SteamGameProcessLog.url(for: bottle))
        try h.write(contentsOf: Data(bytes[..<split]))
        try h.synchronize()
        reader.advance(bottle)
        try h.write(contentsOf: Data(bytes[split...]))
        try h.close()
        reader.advance(bottle)
        #expect(reader.tracked == [5: [50]])
    }

    @Test func aMissingLogMeansNothingIsRunning() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "none")
        #expect(SteamGameProcessLog.tracked(for: bottle).isEmpty)
        #expect(SteamGameProcessLog.size(for: bottle) == 0)
    }

    // MARK: tracker

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func launchingBecomesRunningThenIdleAfterTwoMisses() {
        var t = GameLaunchTracker()
        #expect(t.phase == .idle)
        t.begin(now: t0)
        #expect(t.phase == .launching)
        #expect(t.update(gameRunning: false, steamRunning: true, now: t0 + 5) == nil)
        #expect(t.phase == .launching)
        t.update(gameRunning: true, steamRunning: true, now: t0 + 10)
        #expect(t.phase == .running)
        t.update(gameRunning: false, steamRunning: true, now: t0 + 15)
        #expect(t.phase == .running, "one empty look can be a launcher handing over")
        t.update(gameRunning: true, steamRunning: true, now: t0 + 20)
        t.update(gameRunning: false, steamRunning: true, now: t0 + 25)
        t.update(gameRunning: false, steamRunning: true, now: t0 + 30)
        #expect(t.phase == .idle)
    }

    @Test func givesUpWhenSteamClosesBeforeTheGameStarts() {
        var t = GameLaunchTracker()
        t.begin(now: t0)
        #expect(t.update(gameRunning: false, steamRunning: false, now: t0 + 10) == nil, "Steam may still be starting")
        #expect(t.update(gameRunning: false, steamRunning: false, now: t0 + 25) == .steamClosed)
        #expect(t.phase == .idle)
    }

    @Test func givesUpAfterTheLaunchTimeout() {
        var t = GameLaunchTracker()
        t.begin(now: t0)
        #expect(t.update(gameRunning: false, steamRunning: true, now: t0 + 170) == nil)
        #expect(t.update(gameRunning: false, steamRunning: true, now: t0 + 181) == .timedOut)
        #expect(t.phase == .idle)
    }

    @Test func adoptingAndCancelling() {
        var t = GameLaunchTracker()
        t.adoptRunning()
        #expect(t.phase == .running)
        t.cancel()
        #expect(t.phase == .idle)
        #expect(t.update(gameRunning: true, steamRunning: true, now: t0) == nil && t.phase == .idle)
    }
}

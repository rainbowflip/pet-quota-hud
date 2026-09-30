import Foundation
import CryptoKit

struct Quota: Codable, Equatable {
    var fiveHour: Double?
    var weekly: Double?
    var resets: Int?
    var fiveHourResetsAt: Double?
    var weeklyResetsAt: Double?
    var resetTimes: [Double] = []
    var fetchedAt = Date().timeIntervalSince1970
    static func parse(_ root: [String: Any]) -> Quota {
        let buckets = root["rateLimitsByLimitId"] as? [String: Any]
        let bucket = buckets != nil ? buckets?["codex"] as? [String: Any] : root["rateLimits"] as? [String: Any]
        var q = Quota()
        for key in ["primary", "secondary"] {
            guard let w = bucket?[key] as? [String: Any],
                  let durationNumber = w["windowDurationMins"] as? NSNumber,
                  let used = w["usedPercent"] as? Double, used.isFinite else { continue }
            let duration = durationNumber.intValue
            let remaining = max(0, min(100, 100 - used))
            if duration == 300 { q.fiveHour = remaining; q.fiveHourResetsAt = (w["resetsAt"] as? Double) }
            if duration == 10080 { q.weekly = remaining; q.weeklyResetsAt = (w["resetsAt"] as? Double) }
            if [300, 10080].contains(duration), let reset = w["resetsAt"] as? Double { q.resetTimes.append(reset) }
        }
        if let credits = root["rateLimitResetCredits"] as? [String: Any], let count = credits["availableCount"] as? Int, count >= 0 { q.resets = count }
        return q
    }
}

struct HookSignal: Codable {
    let event: String
    let time: Double
    let session: String
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
    static let support = ProcessInfo.processInfo.environment["PET_QUOTA_HUD_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent("Library/Application Support/PetQuotaHUD")
    static let signals = support.appendingPathComponent("signals")
    static func prepare() throws {
        try FileManager.default.createDirectory(at: signals, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    static func codexExecutable() -> String? {
        let candidates = [ProcessInfo.processInfo.environment["PET_QUOTA_CODEX"],
                          "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
                          "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                          "/Applications/ChatGPT.app/Contents/Resources/codex",
                          "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex",
                          "/Applications/Codex.app/Contents/Resources/codex",
                          "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// Hooks persist no prompt, transcript, credentials, or raw session identifiers.
func emitHook(_ event: String) {
    defer { print("{}") }
    guard ["SessionStart", "UserPromptSubmit", "Stop", "Interrupt"].contains(event) else { return }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    let session = payload["session_id"] as? String ?? "unknown"
    let hash = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
    let signal = HookSignal(event: event, time: Date().timeIntervalSince1970, session: hash)
    do {
        try Paths.prepare()
        try JSONEncoder().encode(signal).write(to: Paths.signals.appendingPathComponent(hash + ".json"), options: .atomic)
    } catch { /* A HUD failure must never break a Codex turn. */ }
}

struct RefreshPolicy {
    var lastAttempt = -Double.infinity
    var pendingAt: Double?
    var active: [String: Double] = [:]
    var handledResets = Set<Double>()
    mutating func signal(_ signal: HookSignal) {
        if signal.event == "UserPromptSubmit" { active[signal.session] = signal.time }
        if ["Stop", "Interrupt", "SessionStart"].contains(signal.event) { active.removeValue(forKey: signal.session) }
        request(at: signal.time + (["Stop", "Interrupt"].contains(signal.event) ? 2 : 0))
    }
    mutating func request(at time: Double) { pendingAt = min(pendingAt ?? time, time) }
    mutating func due(now: Double, visible: Bool, quota: Quota?) -> Bool {
        guard visible else { return false }
        active = active.filter { now - $0.value < 21600 }
        for reset in quota?.resetTimes ?? [] where reset <= now && !handledResets.contains(reset) {
            handledResets.insert(reset); request(at: now)
        }
        let interval: Double = active.isEmpty ? 300 : 60
        guard now - lastAttempt >= 10,
              (pendingAt.map { now >= $0 } ?? false) || now - lastAttempt >= interval else { return false }
        pendingAt = nil; lastAttempt = now
        return true
    }
}

enum ProbeError: Error { case unavailable, timeout, malformed, rejected }

// A short-lived official app-server process. No auth file or private HTTP endpoint is read here.
func probeQuota() throws -> Quota {
    guard let executable = Paths.codexExecutable() else { throw ProbeError.unavailable }
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["app-server", "--listen", "stdio://"]
    process.standardInput = input; process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
    defer {
        watchdog.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
    func send(_ value: [String: Any]) throws {
        var bytes = try JSONSerialization.data(withJSONObject: value); bytes.append(10)
        try input.fileHandleForWriting.write(contentsOf: bytes)
    }
    try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "pet_quota_hud", "version": "0.1.0"], "capabilities": ["experimentalApi": true]]])
    var buffer = Data()
    while true {
        let chunk = output.fileHandleForReading.availableData
        if chunk.isEmpty { throw ProbeError.timeout }
        buffer.append(chunk)
        if buffer.count > 2_000_000 { throw ProbeError.malformed }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = message["id"] as? Int else { continue }
            if message["error"] != nil { throw ProbeError.rejected }
            if id == 1 {
                try send(["method": "initialized"])
                try send(["id": 2, "method": "account/rateLimits/read"])
            } else if id == 2 {
                guard let result = message["result"] as? [String: Any] else { throw ProbeError.malformed }
                return Quota.parse(result)
            }
        }
    }
}

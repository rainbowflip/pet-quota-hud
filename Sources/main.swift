import AppKit
import Darwin

let args = CommandLine.arguments
if let index = args.firstIndex(of: "--hook"), args.count > index + 1 {
    emitHook(args[index + 1]); exit(0)
}
if args.contains("--probe") {
    do { let quota = try probeQuota(); print(String(data: try JSONEncoder().encode(quota), encoding: .utf8)!); exit(0) }
    catch { fputs("Quota probe failed: \(error)\n", stderr); exit(1) }
}
if args.contains("--diagnose") {
    print("petVisible=\(PetTracker().read() != nil), codexAvailable=\(Paths.codexExecutable() != nil)")
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in windows where ["codex", "chatgpt"].contains((info[kCGWindowOwnerName as String] as? String ?? "").lowercased()) && (info[kCGWindowLayer as String] as? Int ?? 0) > 0 {
        print("floatingWindow: \(info[kCGWindowBounds as String] ?? [:]) layer=\(info[kCGWindowLayer as String] ?? 0)")
    }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let index = args.firstIndex(of: "--snapshot"), args.count > index + 1 {
    let view = HUDView(frame: NSRect(x: 0, y: 0, width: 190, height: 30))
    view.quota = Quota(fiveHour: 72, weekly: 64, resets: 1, fiveHourResetsAt: Date().addingTimeInterval(3_594).timeIntervalSince1970, weeklyResetsAt: Date().addingTimeInterval(48 * 3600).timeIntervalSince1970)
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[index + 1]))
    exit(0)
}
try Paths.prepare()
let lockFD = open(Paths.support.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o600)
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
let delegate = AppDelegate()
app.delegate = delegate
app.run()

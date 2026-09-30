import AppKit

// Geometry convention: persisted / CGWindow coordinates have their origin at the top left.
// The current integrated desktop stores a direct 112 × 121 pet anchor.
// Compatibility approach informed by himomohi/codex-pet-hud (MIT); see THIRD_PARTY_NOTICES.
func petRect(_ root: [String: Any]) -> CGRect? {
    guard root["electron-avatar-overlay-open"] as? Bool == true,
          let b = root["electron-avatar-overlay-bounds"] as? [String: Any],
          let x = b["x"] as? Double, let y = b["y"] as? Double else { return nil }
    if b["width"] != nil { return nil } // Fail closed for legacy geometry; do not anchor to the whole message window.
    return CGRect(x: x, y: y, width: 112, height: 121)
}

func appKitHUDRect(pet: CGRect, desktopTop: Double, visibleFrame: CGRect, offset: Double, showCountdown: Bool) -> CGRect {
    let width = showCountdown ? 190.0 : 148.0, height = 30.0
    let x = max(visibleFrame.minX, min(visibleFrame.maxX - width, pet.midX - width / 2))
    let y = max(visibleFrame.minY, min(visibleFrame.maxY - height, desktopTop - pet.minY + offset))
    return CGRect(x: x, y: y, width: width, height: height)
}

final class PetTracker {
    private var stamp: Date?
    private var cached: CGRect?
    func read() -> CGRect? {
        let url = Paths.codexHome.appendingPathComponent(".codex-global-state.json")
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        if modified != stamp {
            stamp = modified
            cached = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.flatMap(petRect)
        }
        guard let pet = cached,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let found = windows.contains { info in
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            guard ["codex", "chatgpt"].contains(owner),
                  (info[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
            // New desktop builds use a tall transparent host covering pet + messages.
            // Persisted visibility and containment are reliable; host height is not pet height.
            return rect.contains(pet)
        }
        return found ? pet : nil
    }
}

final class HUDView: NSView {
    var quota: Quota? { didSet { needsDisplay = true } }
    var showCountdown = true { didSet { needsDisplay = true } }
    var stale = false { didSet { if oldValue != stale { needsDisplay = true } } }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let gold = NSColor(calibratedRed: 0.68, green: 0.55, blue: 0.30, alpha: 1)
        let background = NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.09, alpha: 0.96)
        let body = NSBezierPath(roundedRect: NSRect(x: 23, y: 3, width: bounds.width - 26, height: 24), xRadius: 3, yRadius: 3)
        background.setFill(); body.fill()
        func text(_ value: String, x: CGFloat, centeredIn rect: NSRect, size: CGFloat, color: NSColor = .white, rightAligned: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold), .foregroundColor: color]
            let dimensions = (value as NSString).size(withAttributes: attributes)
            (value as NSString).draw(at: NSPoint(x: rightAligned ? x - dimensions.width : x, y: rect.midY - dimensions.height / 2), withAttributes: attributes)
        }
        func countdown(_ resetAt: Double?) -> String {
            guard let resetAt else { return "--" }
            let minutes = max(0, Int(ceil((resetAt - Date().timeIntervalSince1970) / 60)))
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            if hours < 24 {
                let remainder = minutes % 60
                return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)m"
            }
            let days = hours / 24
            let remainder = hours % 24
            return remainder == 0 ? "\(days)d" : "\(days)d\(remainder)h"
        }
        func bar(_ remaining: Double?, resetAt: Double?, y: Double, color: NSColor, label: String) {
            let r = NSRect(x: 23, y: y, width: bounds.width - 26, height: 12)
            NSColor(white: 0.15, alpha: 1).setFill(); r.fill()
            if let value = remaining {
                color.withAlphaComponent(stale ? 0.42 : 0.90).setFill()
                NSRect(x: r.minX, y: r.minY, width: r.width * value / 100, height: r.height).fill()
                NSColor(white: 1, alpha: 0.16).setFill()
                NSRect(x: r.minX, y: r.maxY - 2, width: r.width * value / 100, height: 2).fill()
            }
            text(label, x: 35, centeredIn: r, size: 8)
            let value = remaining.map { String(format: "%.0f%%", $0) } ?? "—"
            let percentage = value + (stale ? "·" : "")
            if showCountdown {
                text("\(percentage) \(countdown(resetAt))", x: r.maxX - 5, centeredIn: r, size: 8, rightAligned: true)
            } else {
                text(percentage, x: r.maxX - 5, centeredIn: r, size: 8, rightAligned: true)
            }
        }
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        bar(quota?.fiveHour, resetAt: quota?.fiveHourResetsAt, y: 15, color: NSColor(calibratedRed: 0.19, green: 0.69, blue: 0.38, alpha: 1), label: "5H")
        bar(quota?.weekly, resetAt: quota?.weeklyResetsAt, y: 3, color: NSColor(calibratedRed: 0.17, green: 0.47, blue: 0.88, alpha: 1), label: "周")
        NSGraphicsContext.restoreGraphicsState()
        gold.setStroke(); body.lineWidth = 1; body.stroke()
        let badge = NSBezierPath(ovalIn: NSRect(x: 2, y: 3, width: 24, height: 24))
        background.setFill(); badge.fill(); gold.setStroke(); badge.lineWidth = 2; badge.stroke()
        let count = quota?.resets.map(String.init) ?? "?"
        let size: CGFloat = count.count > 2 ? 10 : 14
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold), .foregroundColor: gold]
        let dimensions = (count as NSString).size(withAttributes: attrs)
        (count as NSString).draw(at: NSPoint(x: 14 - dimensions.width / 2, y: 15 - dimensions.height / 2), withAttributes: attrs)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let hud = HUDView(frame: NSRect(x: 0, y: 0, width: 190, height: 30))
    let tracker = PetTracker()
    var status: NSStatusItem!
    var timer: Timer?
    var policy = RefreshPolicy()
    var busy = false
    var stamps: [String: Date] = [:]
    var lastSignalsRead = 0.0
    var error = ""
    var offset: Double = UserDefaults.standard.double(forKey: "headOffset")
    var showCountdown = UserDefaults.standard.object(forKey: "showResetCountdown") as? Bool ?? true
    var minuteTick = Int(Date().timeIntervalSince1970 / 60) { didSet { hud.needsDisplay = true } }
    var demo = CommandLine.arguments.contains("--demo")
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? Paths.prepare()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        // Below the native floating overlay (level 3): native messages always win overlaps.
        panel.ignoresMouseEvents = true; panel.level = NSWindow.Level(rawValue: 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.contentView = hud
        hud.showCountdown = showCountdown
        if !showCountdown { hud.setFrameSize(NSSize(width: 148, height: 30)) }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "◈"
        if let data = try? Data(contentsOf: Paths.support.appendingPathComponent("quota.json")) {
            hud.quota = try? JSONDecoder().decode(Quota.self, from: data); hud.stale = true
        }
        if demo { hud.quota = Quota(fiveHour: 72, weekly: 64, resets: 1) }
        updateMenu()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
        tick()
    }
    @objc func refresh() { policy.request(at: Date().timeIntervalSince1970) }
    @objc func higher() { offset += 4; saveOffset() }
    @objc func lower() { offset -= 4; saveOffset() }
    @objc func toggleCountdown() {
        showCountdown.toggle()
        UserDefaults.standard.set(showCountdown, forKey: "showResetCountdown")
        hud.showCountdown = showCountdown
        tick()
        updateMenu()
    }
    func saveOffset() { UserDefaults.standard.set(offset, forKey: "headOffset"); tick() }
    @objc func quit() { NSApp.terminate(nil) }
    func updateMenu() {
        let menu = NSMenu()
        let summary = demo ? "预览数据 · 非真实额度" : (hud.quota == nil ? "额度尚未读取" : "5H / 周：显示剩余额度")
        menu.addItem(withTitle: summary, action: nil, keyEquivalent: "")
        if let q = hud.quota {
            menu.addItem(withTitle: "更新于 " + Date(timeIntervalSince1970: q.fetchedAt).formatted(date: .omitted, time: .standard), action: nil, keyEquivalent: "")
        }
        if !error.isEmpty { menu.addItem(withTitle: error, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let countdownItem = menu.addItem(withTitle: "显示重置倒计时", action: #selector(toggleCountdown), keyEquivalent: "")
        countdownItem.target = self; countdownItem.state = showCountdown ? .on : .off
        for (title, action) in [("刷新额度", #selector(refresh)), ("位置上移 4px", #selector(higher)), ("位置下移 4px", #selector(lower)), ("退出", #selector(quit))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        status.menu = menu
    }
    func readSignals(now: Double) {
        guard now - lastSignalsRead >= 1 else { return }; lastSignalsRead = now
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.signals, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "json" {
            guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if now - date.timeIntervalSince1970 > 86400 { try? FileManager.default.removeItem(at: file); stamps.removeValue(forKey: file.path); continue }
            guard stamps[file.path] != date else { continue }; stamps[file.path] = date
            guard let data = try? Data(contentsOf: file), let signal = try? JSONDecoder().decode(HookSignal.self, from: data) else { continue }
            if now - signal.time < 21600 { policy.signal(signal) }
        }
    }
    func tick() {
        let now = Date().timeIntervalSince1970
        let currentMinute = Int(now / 60)
        if showCountdown, currentMinute != minuteTick { minuteTick = currentMinute }
        readSignals(now: now)
        let pet = demo ? CGRect(x: 650, y: 500, width: 112, height: 121) : tracker.read()
        guard let pet, let main = NSScreen.screens.first else { panel.orderOut(nil); return }
        let top = main.frame.maxY
        let center = CGPoint(x: pet.midX, y: top - pet.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) else { panel.orderOut(nil); return }
        let frame = appKitHUDRect(pet: pet, desktopTop: top, visibleFrame: screen.visibleFrame, offset: offset, showCountdown: showCountdown)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless(); policy.request(at: now) }
        hud.stale = !error.isEmpty || now - (hud.quota?.fetchedAt ?? 0) > 600
        guard !demo, !busy, policy.due(now: now, visible: true, quota: hud.quota) else { return }
        busy = true
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try probeQuota() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let quota):
                    self.hud.quota = quota; self.hud.stale = false; self.error = ""
                    if let bytes = try? JSONEncoder().encode(quota) { try? bytes.write(to: Paths.support.appendingPathComponent("quota.json"), options: .atomic) }
                case .failure(let failure):
                    self.error = (failure as? ProbeError) == .unavailable ? "未找到 Codex CLI · 保留旧值" : "额度读取失败 · 保留旧值"
                    self.hud.stale = true
                }
                self.updateMenu()
            }
        }
    }
}

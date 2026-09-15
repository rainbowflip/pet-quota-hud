import Foundation
import AppKit

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
let q = Quota.parse(["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 20.0, "windowDurationMins": 10080], "secondary": ["usedPercent": 130.0, "windowDurationMins": 300]], "reserve": ["primary": ["usedPercent": 0.0, "windowDurationMins": 300]]], "rateLimitResetCredits": ["availableCount": 0]])
expect(q.fiveHour == 0 && q.weekly == 80, "Map by duration and select Codex bucket")
expect(q.resets == 0, "Zero credits is known")
let unknown = Quota.parse([:])
expect(unknown.fiveHour == nil && unknown.weekly == nil && unknown.resets == nil, "Missing remains unknown")
expect(Quota.parse(["rateLimitsByLimitId": [:], "rateLimits": ["primary": ["windowDurationMins": 300, "usedPercent": 0.0]]]).fiveHour == nil, "No unsafe legacy fallback for unrelated buckets")
var policy = RefreshPolicy()
expect(!policy.due(now: 0, visible: false, quota: nil), "Hidden never polls")
expect(policy.due(now: 0, visible: true, quota: nil), "First visible refresh")
policy.signal(HookSignal(event: "UserPromptSubmit", time: 1, session: "a"))
expect(!policy.due(now: 9, visible: true, quota: nil), "Ten second minimum")
expect(policy.due(now: 10, visible: true, quota: nil), "Trailing signal retained")
expect(!policy.due(now: 69, visible: true, quota: nil), "Active interval")
expect(policy.due(now: 70, visible: true, quota: nil), "Active refresh at 60 seconds")
policy.signal(HookSignal(event: "Stop", time: 100, session: "a"))
expect(!policy.due(now: 101, visible: true, quota: nil), "Stop settles for two seconds")
expect(policy.due(now: 102, visible: true, quota: nil), "Stop refresh")
expect(!policy.due(now: 401, visible: true, quota: nil), "Idle interval")
expect(policy.due(now: 402, visible: true, quota: nil), "Idle five minutes")
let reset = Quota(resetTimes: [410])
expect(policy.due(now: 412, visible: true, quota: reset), "Reset timestamp refresh")
expect(!policy.due(now: 422, visible: true, quota: reset), "Expired reset does not loop")
let pet = CGRect(x: -183, y: 897, width: 112, height: 121)
let rect = appKitHUDRect(pet: pet, desktopTop: 1080, visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 982), offset: 0)
expect(rect.minX == -201 && rect.minY == 183, "Negative secondary screen coordinates")
let clipped = appKitHUDRect(pet: CGRect(x: 0, y: 0, width: 112, height: 121), desktopTop: 1080, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050), offset: 0)
expect(clipped.minX == 0 && clipped.maxY == 1050, "Clamp at screen edges")
expect(petRect(["electron-avatar-overlay-open": false]) == nil, "Closed pet has no anchor")
print("\(checks) Swift checks passed")

import AppKit
import ApplicationServices
import ScreenCaptureKit

// How the README's first recording is made.
//
//   swiftc -O Tools/demo.swift -o build/demo
//   build/demo <ShanShui binary> <home> <tag | -> <out dir | -> <item>...
//   build/demo "/Applications/Shan Shui.app/Contents/MacOS/ShanShui" /tmp/demo-home 5 /tmp/frames \
//     Accent wait:3 "Rice paper" wait:3 "New landscape" wait:2.5
//   gifski --fps 12 --quality 90 --width 1200 -o docs/demo.gif /tmp/frames/*.png   (the JPEGs as PNGs)
//
// It takes the screen for half a minute: goes to an empty tag of the mango window
// manager ("-": stays where it is) with Finder in front, starts Shan Shui with <home>
// as its home folder (its own .config/shanshui/config.json, so the user's settings
// and landscape are not touched), moves the pointer to 山 and picks each <item> from the
// menu, with the whole display recorded as JPEGs in <out dir>, 12 a second ("-" records
// nothing: a rehearsal). Then everything is put back: the user's own Shan Shui, the
// tag, the front app and the pointer.
// An <item> is a menu title, or "wait:<seconds>".
// It needs the Accessibility and Screen Recording permissions.

let a = CommandLine.arguments
guard a.count >= 6 else { print("usage: demo <binary> <home> <tag | -> <out dir | -> <item>..."); exit(2) }
let binary = a[1], home = a[2], tag = a[3], out = a[4], steps = Array(a[5...])
let id = "shanshui-macos", mmsg = NSString(string: "~/.local/bin/mmsg").expandingTildeInPath

@discardableResult func run(_ path: String, _ args: [String]) -> String {
  let p = Process(), pipe = Pipe()
  p.executableURL = URL(fileURLWithPath: path); p.arguments = args
  p.standardOutput = pipe; p.standardError = pipe
  do { try p.run() } catch { return "" }
  let d = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  return String(data: d, encoding: .utf8) ?? ""
}
func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
func waitFor(_ s: Double, _ until: () -> Bool) -> Bool {
  let end = Date().addingTimeInterval(s)
  while Date() < end { if until() { return true }; pause(0.05) }
  return until()
}
func activeTag() -> Int {
  guard let d = run(mmsg, ["get", "all-tags"]).data(using: .utf8),
        let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
        let ms = j["all_tags"] as? [[String: Any]], let ts = ms.first?["tags"] as? [[String: Any]] else { return 0 }
  return ts.first { ($0["is_active"] as? Bool) == true }?["index"] as? Int ?? 0
}
func running() -> [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: id) }

// The pointer.
var pointer = CGEvent(source: nil)?.location ?? .zero
@Sendable func event(_ kind: CGEventType, _ p: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func move(_ to: CGPoint, _ dur: Double) {
  let from = pointer, n = max(1, Int(dur * 60))
  for i in 1...n {
    let t = Double(i) / Double(n), e = t * t * (3 - 2 * t)
    event(.mouseMoved, CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e))
    pause(1.0 / 60)
  }
  pointer = to
}
func click() { event(.leftMouseDown, pointer); pause(0.08); event(.leftMouseUp, pointer) }

// Accessibility: where 山 and the menu's items are.
func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { value(e, "AXChildren") as? [AXUIElement] ?? [] }
func center(_ e: AXUIElement) -> CGPoint? {
  guard let p = value(e, "AXPosition"), let s = value(e, "AXSize") else { return nil }
  var o = CGPoint.zero, t = CGSize.zero
  AXValueGetValue(p as! AXValue, .cgPoint, &o); AXValueGetValue(s as! AXValue, .cgSize, &t)
  return CGPoint(x: o.x + t.width / 2, y: o.y + t.height / 2)
}
func button(_ pid: pid_t) -> AXUIElement? {
  guard let bar = value(AXUIElementCreateApplication(pid), "AXExtrasMenuBar") else { return nil }
  return children(bar as! AXUIElement).first
}

// What was there before, to be put back.
let frontBefore = NSWorkspace.shared.frontmostApplication
let tagBefore = tag == "-" ? 0 : activeTag(), pointerBefore = pointer
// The user's own, and where it is: it is started again from there, not by name.
let own = running().first?.bundleURL
let wasRunning = own != nil
var demo: Process?
var recording = false, frames = 0

func restore() {
  recording = false
  if let d = demo, d.isRunning { d.terminate(); d.waitUntilExit() }
  demo = nil
  // The user's own comes back once the demo's is off the list of running apps: it starts
  // only when no other is there.
  if wasRunning {
    for _ in 0..<5 where running().isEmpty {
      run("/usr/bin/open", [own?.path ?? "/Applications/Shan Shui.app"])
      _ = waitFor(2, { !running().isEmpty })
      pause(0.5)
    }
  }
  if tagBefore > 0 { run(mmsg, ["dispatch", "view,\(tagBefore)"]) }
  frontBefore?.activate()
  CGWarpMouseCursorPosition(pointerBefore)
}
func fail(_ text: String) -> Never { print("error:", text); restore(); exit(1) }
for s in [SIGINT, SIGTERM] { signal(s) { _ in restore(); exit(1) } }

func record() {
  Task {
    do {
      let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      // The display with the menu bar, when there are several.
      let display = c.displays.first { $0.displayID == CGMainDisplayID() } ?? c.displays[0]
      let f = SCContentFilter(display: display, excludingWindows: [])
      let k = SCStreamConfiguration()
      k.width = Int(display.width); k.height = Int(display.height); k.showsCursor = true
      let t0 = Date(), fps = 12.0
      var times = ""
      while recording {
        let t = Date().timeIntervalSince(t0)
        let img = try await SCScreenshotManager.captureImage(contentFilter: f, configuration: k)
        let r = NSBitmapImageRep(cgImage: img)
        try r.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!
          .write(to: URL(fileURLWithPath: String(format: "%@/%04d.jpg", out, frames)))
        times += "\(frames) \(t)\n"; frames += 1
        let wait = Double(frames) / fps - Date().timeIntervalSince(t0)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
      }
      try times.write(toFile: out + "/times.txt", atomically: true, encoding: .utf8)
    } catch { print("recording error:", error) }
  }
}

Thread.detachNewThread {
  guard tag == "-" || tagBefore > 0 else { fail("mango does not answer") }
  // The user's own painting steps aside (it saves where it is).
  running().forEach { $0.terminate() }
  guard waitFor(5, { running().isEmpty }) else { fail("Shan Shui did not quit") }

  if tag != "-" { run(mmsg, ["dispatch", "view,\(tag)"]) }
  NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
  pause(0.8)
  if tag != "-" {
    if activeTag() != Int(tag) { run(mmsg, ["dispatch", "view,\(tag)"]); pause(0.5) }
    guard activeTag() == Int(tag) else { fail("the tag did not stay") }
  }

  let p = Process()
  p.executableURL = URL(fileURLWithPath: binary)
  p.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home]) { $1 }
  p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
  do { try p.run() } catch { fail("\(error)") }
  demo = p
  let pid = p.processIdentifier
  guard waitFor(8, { button(pid).flatMap(center) != nil }) else { fail("no 山 in the menu bar") }
  print("front app:", NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")

  // The pointer starts out of the way, low on the screen.
  let screen = CGDisplayBounds(CGMainDisplayID())
  CGWarpMouseCursorPosition(CGPoint(x: screen.width * 0.62, y: screen.height * 0.62))
  pointer = CGPoint(x: screen.width * 0.62, y: screen.height * 0.62)
  pause(2.5)   // the paper is laid out and the first strokes are there

  if out != "-" { recording = true; record() }
  pause(3)
  var first = true
  for step in steps {
    if step.hasPrefix("wait:") { pause(Double(step.dropFirst(5)) ?? 1); continue }
    guard let b = button(pid), let c = center(b) else { fail("lost 山") }
    move(c, 1.0); pause(0.3); click()
    var target: CGPoint?
    guard waitFor(3, {
      target = children(b).flatMap(children).first { (value($0, "AXTitle") as? String) == step }.flatMap(center)
      return target != nil
    }), let target else { fail("no menu item \(step)") }
    pause(first ? 2.5 : 0.8)
    move(CGPoint(x: target.x - 40, y: target.y), first ? 1.6 : 1.0); pause(0.5); click()
    first = false
    print("picked", step)
    pause(0.5)
  }
  recording = false
  pause(0.5)
  print(frames, "frames")
  restore()
  exit(0)
}
RunLoop.main.run()

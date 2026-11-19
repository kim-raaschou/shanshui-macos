import AppKit

// Shan Shui for macOS: omarchy-shanshui (ZeD) as a desktop background.
//
//   ShanShui                         the app
//   ShanShui pause | resume | new | on | off | toggle | state
//   ShanShui skip 0.5                moves the front half a screen
//   ShanShui strip --dir <cache> --seed 42 --k 3 --w 2560 --h 1440   one strip, written to <cache>
//   ShanShui version                 the version and the build (the start of the program's UUID)
//   ShanShui png --seed 42 --x 0 --w 1920 --h 1080 [--ink #hex --paper #hex --delay --layer n] > view.png

let ipcChannel = Notification.Name("shanshui-macos.ipc")
let stateChannel = Notification.Name("shanshui-macos.state")

// The control commands, as the running app does them; the command line only sends them.
// The order is the usage line's.
let commands: KeyValuePairs<String, (Landscape, [String]) -> Void> = [
  "pause": { p, _ in p.pause() },
  "resume": { p, _ in p.resume() },
  "new": { p, _ in p.newLandscape() },
  "on": { p, _ in p.turnOn() },
  "off": { p, _ in p.turnOff() },
  "toggle": { p, _ in p.toggle() },
  "state": { p, _ in
    DistributedNotificationCenter.default().postNotificationName(stateChannel, object: p.state(), userInfo: nil, deliverImmediately: true)
  },
  "skip": { p, a in p.skip(a.count > 1 ? Double(a[1]) ?? 0 : 0) },
]

func fail(_ text: String, _ code: Int32) -> Int32 {
  FileHandle.standardError.write(Data((text + "\n").utf8))
  return code
}

func cli(_ a: [String]) -> Int32 {
  var o: [String: String] = [:]
  var i = 1
  while i < a.count {
    let k = String(a[i].dropFirst(2))
    if i + 1 < a.count, !a[i + 1].hasPrefix("--") { o[k] = a[i + 1]; i += 2 } else { o[k] = "1"; i += 1 }
  }
  do {
    switch a[0] {
    case "strip":
      guard let dir = o["dir"], let seed = o["seed"], Generator.validSeed(seed),
            let k = Int(o["k"] ?? ""), let w = Int(o["w"] ?? ""), let h = Int(o["h"] ?? ""), (64...16384).contains(w), (64...16384).contains(h)
      else { return fail("ShanShui: strip --dir --seed --k --w --h [--delay-scale] [--full] [--layer 0,1,2 [--layers 2|3]]", 2) }
      try Generator.strip(dir: URL(fileURLWithPath: dir), seed: seed, k: k, w: w, h: h,
                          scale: min(1, max(0.1, Double(o["delay-scale"] ?? "") ?? 0.5)),
                          layers: o["layer"].map { $0.split(separator: ",").compactMap { Int($0) }.filter { (0...2).contains($0) } },
                          of: o["layers"] == "2" ? 2 : 3, full: o["full"] != nil)
      return 0
    case "version":
      print((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") + " " + Menu.build)
      return 0
    case "png":
      FileHandle.standardOutput.write(try Generator.png(seed: o["seed"] ?? "42", x: Double(o["x"] ?? "") ?? 0, w: Int(o["w"] ?? "") ?? 1920,
                                                        h: Int(o["h"] ?? "") ?? 1080, ink: o["ink"], paper: o["paper"],
                                                        delay: o["delay"] != nil, layer: o["layer"].flatMap { Int($0) }))
      return 0
    default: break
    }
  } catch { return fail("ShanShui: \(error)", 1) }
  guard commands.contains(where: { $0.key == a[0] }) else {
    return fail("usage: ShanShui " + commands.map(\.key).joined(separator: "|") + " <screens>|png ...", 2)
  }
  let dnc = DistributedNotificationCenter.default()
  var answer: String?
  let obs = dnc.addObserver(forName: stateChannel, object: nil, queue: .main) { answer = $0.object as? String }
  dnc.postNotificationName(ipcChannel, object: a.joined(separator: " "), userInfo: nil, deliverImmediately: true)
  if a[0] == "state" {
    let until = Date().addingTimeInterval(2)
    while answer == nil, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    dnc.removeObserver(obs)
    guard let answer else { return 1 }
    print(answer)
  }
  return 0
}

final class Delegate: NSObject, NSApplicationDelegate {
  var service: Service?
  var menu: Menu?

  func applicationDidFinishLaunching(_ n: Notification) {
    let p = Landscape.shared
    p.begin()
    service = Service()
    menu = Menu()
    p.onChange = { [unowned self] in
      service?.update()
      menu?.update()
    }
    p.onFrame = { [unowned self] in service?.redraw() }
    DistributedNotificationCenter.default().addObserver(forName: ipcChannel, object: nil, queue: .main) { n in
      let a = (n.object as? String ?? "").split(separator: " ").map(String.init)
      commands.first { $0.key == a.first }?.value(p, a)
    }
  }

  func applicationWillTerminate(_ n: Notification) { Landscape.shared.save() }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if let first = arguments.first, !first.hasPrefix("-") { exit(cli(arguments)) }

// One painting at a time.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) { exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()

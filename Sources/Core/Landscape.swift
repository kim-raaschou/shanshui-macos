import AppKit

// Paisagem.qml of the original: the scroll being painted from left to right,
// without end.
//
// The landscape is cut into strips the size of the screen (k = 0, 1, 2...).
// Each strip is a finished picture plus a delay map per pixel, made off the
// main thread at low priority (Generator). Here only one number walks - the
// painting front, in world x - and the camera follows it; Painting reveals of
// each strip what the front has passed.
//
// In memory are the two strips on screen, and the third when the camera gets
// near it. The front waits when the strip it is in does not exist yet.
//
// With `depth` on the scroll becomes three layers (far, middle, near),
// each with its own strips and slower the farther it is.
final class Landscape {
  static let shared = Landscape()
  /// Running as the screen saver: always painting, and making its own strips.
  static var saver = false

  struct Strip {
    let c: Int, k: Int, key: String
    let picture: Bitmap, delay: Bitmap
  }

  /// What the app itself costs, for the menu: noted when a save runs (every
  /// half minute while painting) and when the menu opens, never by a timer of
  /// its own. The last hour is kept. What macOS spends moving the picture on
  /// screen is not the app's to see.
  final class Usage {
    struct Sample {
      let time: Double    // seconds
      let cpu: Double     // seconds of processor, the strips' helper included
      let energy: Double  // joules of processor, 0 when the system does not tell
      let memory: Int     // bytes, as Activity Monitor counts them
    }
    private(set) var samples: [Sample] = []

    func sample() {
      var r = rusage()
      getrusage(RUSAGE_CHILDREN, &r)
      let helper = Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
      let own = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e9
      var info = rusage_info_v6()
      let told = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) }
      } == 0
      var vm = task_vm_info_data_t()
      var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
      let read = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
      } == KERN_SUCCESS
      samples.append(Sample(time: ProcessInfo.processInfo.systemUptime, cpu: own + helper,
                            energy: told ? Double(info.ri_energy_nj) / 1e9 : 0, memory: read ? Int(vm.phys_footprint) : 0))
      if samples.count > 120 { samples.removeFirst(samples.count - 120) }
    }

    /// The share of one core and the milliwatts over the last `seconds`, and
    /// the memory now; nil before two samples.
    func recent(_ seconds: Double = 300) -> (core: Double, milliwatts: Double, memory: Int)? {
      guard let last = samples.last, let first = samples.last(where: { $0.time <= last.time - seconds }) ?? samples.first,
            last.time - first.time > 1 else { return nil }
      let t = last.time - first.time
      return ((last.cpu - first.cpu) / t * 100, (last.energy - first.energy) / t * 1000, last.memory)
    }

    /// Milliwatts (or, without energy, the share of a core) between each two
    /// samples of the last hour; nil where it was not painting (a gap).
    func history() -> [Double?] {
      zip(samples, samples.dropFirst()).map { a, b in
        let t = b.time - a.time
        guard t > 1, t < 45 else { return nil }
        return b.energy > 0 ? (b.energy - a.energy) / t * 1000 : (b.cpu - a.cpu) / t * 100
      }
    }
  }
  let usage = Usage()

  /// The settings, the state and the strips' folder under a home folder: the
  /// user's, or the screen saver's container (which has no XDG variables).
  struct Folders {
    let config: URL, state: URL, cache: URL
    init(_ home: URL, env: [String: String] = [:]) {
      func base(_ v: String, _ fallback: String) -> URL {
        env[v].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(fallback)
      }
      config = home.appendingPathComponent(".config/shanshui/config.json")
      state = base("XDG_STATE_HOME", ".local/state").appendingPathComponent("shanshui/state.json")
      cache = base("XDG_CACHE_HOME", ".cache").appendingPathComponent("shanshui")
    }
  }
  let folders = Folders(URL(fileURLWithPath: NSHomeDirectory()), env: ProcessInfo.processInfo.environment)

  // The keys are the original's, in English (minPorTela, tinta, papel, camadas, ...).
  static let defaults: [String: Any] = [
    "minutesPerScreen": 5,  // for the front to cross one screen
    "fps": 12,
    "frontOnScreen": 1.0,   // where the front sits on screen (0 left, 1 right)
    "spread": 140,          // how far behind the front the details come (world)
    "softness": 40,         // width of the edge where the ink comes in (world)
    "grain": 0.06,
    "ink": "foreground",
    "paper": "background",
    "invert": false,
    "depth": false,         // layers at different speeds (parallax)
    "layers": 3,            // how many, with depth: 3 as the original, or 2
    "resolution": 1,        // size of the strips relative to the screen (1, 0.75, 0.5)
    "fpsAuto": true,        // only the fps the motion asks for, at most the one above
    "fineEdge": true,       // the delay as big as the strip (the original: half the screen)
    "inkInSteps": true,     // the ink comes in by steps (the original: at every frame)
    "back": "opaque",       // the back layer's tiles: "opaque" (least work for the system), "mono" (one byte a pixel) or "blend"
    "easeLowPower": true,   // half the frame rate in Low Power Mode
    "displayColors": true,  // the tiles in the screen's colours, not sRGB
  ]

  var options: [String: Any] = Landscape.defaults {
    didSet {
      if Landscape.layers(oldValue) != layers { strips = Landscape.empty }
      arrange()
      forgetColors()
    }
  }

  var active = true { didSet { changed() } }
  var paused = false { didSet { changed() } }
  var seed = ""
  var front = 0.0 { didSet { if !walking { changed() } } }
  /// The front's walk at each frame: only the painting follows it (onFrame).
  private var walking = false
  var ready = false { didSet { changed() } }
  /// "" | "generate": what keeps it from painting, for the menu to tell.
  var problem = "" { didSet { changed() } }

  // Three fixed places per layer: layer c uses places 3c..3c+2.
  static let empty = [Strip?](repeating: nil, count: 9)
  var strips = Landscape.empty { didSet { changed() } }
  func places(_ c: Int) -> Range<Int> { (3 * c)..<(3 * c + 3) }
  var layers: Int { Landscape.layers(options) }
  static func layers(_ o: [String: Any]) -> Int {
    guard (o["depth"] as? Bool) == true else { return 1 }
    return (o["layers"] as? NSNumber)?.intValue == 2 ? 2 : 3
  }
  // How much the layer moves relative to the camera (the near one, the last,
  // is 1), and how much it fades toward the paper.
  // Of two layers, the far one is the original's far one and the other its near one.
  var factors: [Double] { [[1], [0.3, 1], [0.3, 0.6, 1]][layers - 1] }
  var mists: [Double] { [[0], [0.35, 0], [0.35, 0.15, 0]][layers - 1] }
  /// The keys of the strips being made.
  var pending: [String] = []
  var generating: Bool { !pending.isEmpty }
  var loaded = false { didSet { changed() } }

  // The camera follows the front. At the start of a landscape it stays at 0
  // while the opening run fills the screen; then it walks along.
  var camera: Double { max(0, front - frontOnScreen) }
  /// Where the front sits on the screen, in the world.
  var frontOnScreen: Double { number(options["frontOnScreen"], 0.3, 1.2, 1.0) * viewWidth }
  /// Seconds for the front to cross one screen.
  var secondsPerScreen: Double { number(options["minutesPerScreen"], 0.1, 120, 5) * 60 }
  var spread: Double { number(options["spread"], 1, 1e6, 140) }
  var softness: Double { number(options["softness"], 0.001, 1e6, 40) }
  var grain: Double { number(options["grain"], 0, 1, 0.06) }
  /// Opening: up to here the front runs (one screen in a few seconds).
  var openingUntil = -1.0
  var frontScreen: Int { max(0, Int((front / viewWidth).rounded(.down))) }
  func cameraOf(_ c: Int) -> Double { camera * factors[c] }
  func frontOf(_ c: Int) -> Double { front - (1 - factors[c]) * camera }

  /// Nobody sees the background (fullscreen, or covered on every screen): the
  /// painting freezes. Set by Service from the windows' occlusion.
  var covered = false {
    didSet {
      guard covered != oldValue else { return }
      // Where it stopped is kept now: no save runs while it is covered.
      if covered { save() }
      changed()
    }
  }

  /// The world's view is as tall as Generator.viewH; the width follows the largest monitor.
  var screen: (w: Int, h: Int) = (1920, 1080)
  /// That monitor's width in points, and its colours.
  var screenPoints = 1920
  var screenSpace: CGColorSpace = Svg.srgb
  func measureScreen() {
    let screens = NSScreen.screens.map {
      (w: Int(($0.frame.width * $0.backingScaleFactor).rounded()), h: Int(($0.frame.height * $0.backingScaleFactor).rounded()),
       points: Int($0.frame.width.rounded()), space: $0.colorSpace?.cgColorSpace)
    }
    // Of two as large, the first.
    let largest = screens.max { $0.w * $0.h < $1.w * $1.h }
    screen = largest.map { ($0.w, $0.h) } ?? (1920, 1080)
    screenPoints = largest?.points ?? 1920
    // Only an RGB one can hold the tiles' colours.
    screenSpace = largest?.space.flatMap { $0.model == .rgb ? $0 : nil } ?? Svg.srgb
    // The screen saver's thumbnail alone: strips as small as it.
    if let preview {
      screen = preview
      screenPoints = preview.w
    }
    arrange()
  }
  /// The screen saver shown only as System Settings' thumbnail, in pixels.
  var preview: (w: Int, h: Int)? {
    didSet { if preview?.w != oldValue?.w || preview?.h != oldValue?.h { measureScreen() } }
  }
  var stripScale: Double { number(options["resolution"], 0.4, 1, 1) }
  var stripSize: (w: Int, h: Int) {
    (max(64, Int((Double(screen.w) * stripScale).rounded())), max(64, Int((Double(screen.h) * stripScale).rounded())))
  }
  var viewWidth: Double { Generator.viewH * Double(stripSize.w) / Double(stripSize.h) }

  func number(_ v: Any?, _ min: Double, _ max: Double, _ fallback: Double) -> Double {
    guard let n = (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap({ Double($0) }), n.isFinite else { return fallback }
    return Swift.min(max, Swift.max(min, n))
  }

  // ---- colours

  func color(_ name: Any?, _ fallback: String) -> SIMD4<Float> { Theme.color(name as? String ?? "") ?? Theme.color(fallback)! }

  /// `invert` swaps ink and paper, in any palette.
  var inverted: Bool { (options["invert"] as? Bool) == true }
  var inkNow: SIMD4<Float> { colors().ink }
  var paperNow: SIMD4<Float> { colors().paper }

  /// The two colours are asked of the system once, and again when the
  /// options, the appearance or the system's colours change.
  private var cached: (ink: SIMD4<Float>, paper: SIMD4<Float>)?
  private var appearance: NSKeyValueObservation?
  private func colors() -> (ink: SIMD4<Float>, paper: SIMD4<Float>) {
    if cached == nil {
      let t = color(options["ink"], "foreground"), p = color(options["paper"], "background")
      cached = inverted ? (p, t) : (t, p)
    }
    return cached!
  }

  private func forgetColors() {
    cached = nil
    changed()
  }

  // ---- strips

  /// Everything that changes the drawing of a strip; also the file's name.
  /// Colours are not in it: the strip is grey and Painting paints it.
  func key(_ c: Int, _ k: Int) -> String {
    Generator.key(seed, k, stripSize.w, stripSize.h, layers > 1 ? c : nil, of: layers, full: fullDelay)
  }

  /// Not in the original, which paints at every frame: how far the front
  /// walks, in the world, before the ink it is laying is painted again. The
  /// scroll still moves at every frame. Stopped, nothing is left behind.
  var inkStep: Double { (options["inkInSteps"] as? Bool) == true && !paused ? 1 : 0 }

  /// Not in the original, whose delay is half the screen: here as big as the
  /// strip, where that is more.
  var fullDelay: Bool { (options["fineEdge"] as? Bool) == true && stripScale > 0.5 }

  /// How the back layer's tiles keep their pixels (Painting.Kind).
  var back: Painting.Kind { (options["back"] as? String).flatMap(Painting.Kind.init) ?? .opaque }
  /// Half the frame rate while the Mac is in Low Power Mode.
  var easeLowPower: Bool { (options["easeLowPower"] as? Bool) != false }
  /// The tiles in the screen's colours, so the system need not match each pixel.
  var displayColors: Bool { (options["displayColors"] as? Bool) != false }

  func strip(_ c: Int, _ k: Int) -> Strip? { strips[places(c)].compactMap { $0 }.first { $0.k == k } }

  func stripReady(_ c: Int, _ k: Int) -> Bool { strip(c, k)?.key == key(c, k) }

  /// The strip the front is in, in the near layer: the one the front waits for.
  func frontReady() -> Bool { stripReady(layers - 1, frontScreen) }

  func needed(_ c: Int) -> [Int] {
    let cam = cameraOf(c), kc = Int((cam / viewWidth).rounded(.down))
    let ks = cam - Double(kc) * viewWidth > 0.5 * viewWidth ? [kc, kc + 1, kc + 2] : [kc, kc + 1]
    return ks.filter { $0 >= 0 }
  }

  func arrange() {
    guard loaded, active, ready else { return }
    // Lets go of what left the screen.
    let ks = (0..<layers).map(needed)
    for c in 0..<layers {
      for i in places(c) where strips[i].map({ !ks[c].contains($0.k) }) == true { strips[i] = nil }
    }
    if generating { return }
    // Makes the most urgent one missing: the near layer first, and in it the
    // front's strip (of two as near, the left one). One job does the whole k:
    // the other layers that need it too come out of the same planted world.
    for c in stride(from: layers - 1, through: 0, by: -1) {
      let kf = Int((frontOf(c) / viewWidth).rounded(.down))
      guard let k = ks[c].filter({ !stripReady(c, $0) }).min(by: { (abs($0 - kf), $0) < (abs($1 - kf), $1) }) else { continue }
      generate(k, (0..<layers).filter { ks[$0].contains(k) && !stripReady($0, k) })
      return
    }
  }

  func generate(_ k: Int, _ cs: [Int]) {
    guard ready, problem.isEmpty else { return }
    let targets = cs.map { (c: $0, key: key($0, k)) }
    let size = stripSize, seed = self.seed, dir = folders.cache, full = fullDelay
    let scale = full ? 1 : min(1, 0.5 / stripScale)
    let wantedLayers: [Int]? = layers > 1 ? cs : nil, of = layers
    let urls = targets.map { Generator.names($0.key) }.map { (q: dir.appendingPathComponent($0.q), o: dir.appendingPathComponent($0.o)) }
    pending = targets.map(\.key)
    // Outside the app, at the lowest priority, as the original does with
    // node: what the generator used goes away with its process.
    var args = ["strip", "--dir", dir.path, "--seed", seed, "--k", String(k), "--w", String(size.w), "--h", String(size.h),
                "--delay-scale", String(scale)]
    if full { args.append("--full") }
    if let cs = wantedLayers { args += ["--layer", cs.map(String.init).joined(separator: ","), "--layers", String(of)] }
    // A strip is made half a screen ahead: there is time for the efficiency
    // cores. Only the opening, which runs, waits for it.
    let qos: QualityOfService = front < openingUntil ? .utility : .background
    let thread = Thread {
      let r = autoreleasepool { Result { () -> [(Bitmap, Bitmap)] in
        if Landscape.saver {
          // The screen saver's sandbox starts no process: the strip is made
          // here (one made before is only read). What the generator took is
          // given back at once, or the system's host keeps it.
          defer { malloc_zone_pressure_relief(nil, 0) }
          try Generator.strip(dir: dir, seed: seed, k: k, w: size.w, h: size.h, scale: scale, layers: wantedLayers, of: of, full: full)
        } else if !urls.allSatisfy({ Generator.existsValid($0.q) && Generator.existsValid($0.o) }) {
          let proc = Process()
          proc.executableURL = Bundle.main.executableURL
          proc.arguments = args
          proc.qualityOfService = qos
          proc.standardOutput = FileHandle.nullDevice
          try proc.run()
          proc.waitUntilExit()
          guard proc.terminationStatus == 0 else { throw Failure("strip \(k) left with \(proc.terminationStatus)") }
        }
        return try urls.map { (try Svg.read($0.q, wantedLayers == nil ? .gray : .grayAlpha), try Svg.read($0.o, .delay)) }
      } }
      DispatchQueue.main.async {
        self.pending = []
        switch r {
        case .success(let images):
          // The options may have changed meanwhile: such a strip has no place.
          for (a, t) in zip(targets, images) where a.c < self.layers && a.key == self.key(a.c, k) {
            self.put(Strip(c: a.c, k: k, key: a.key, picture: t.0, delay: t.1))
          }
          self.clear()
        case .failure(let e):
          // Tries again in a while, but tells in the menu.
          self.problem = "generate"
          NSLog("shanshui: %@", String(describing: e))
          self.keep(&self.problemTimer, 30, repeats: false) { if self.problem == "generate" { self.problem = ""; self.arrange() } }
        }
        DispatchQueue.main.async { self.arrange() }
      }
    }
    // The generator recurses deeply when it runs here.
    thread.stackSize = 32 << 20
    thread.qualityOfService = qos
    thread.start()
  }

  /// In the layer's place that has the same k, or else in a free one.
  func put(_ a: Strip) {
    let r = places(a.c)
    guard let place = r.last(where: { strips[$0]?.k == a.k }) ?? r.first(where: { strips[$0] == nil }) else { return }
    strips[place] = a
  }

  /// Deletes the strips that are in no place, nor being made, nor about to
  /// be read.
  func clear() {
    guard ready else { return }
    let keys = strips.compactMap { $0?.key } + pending + (0..<layers).flatMap { c in needed(c).map { key(c, $0) } }
    let keep = Set(keys.map(Generator.names).flatMap { [$0.q, $0.o] })
    let dir = folders.cache
    DispatchQueue.global(qos: .background).async {
      Generator.clear(dir: dir, keep: keep)
    }
  }

  // ---- the screen saver's settings
  //
  // The screen saver lives in the system's sandbox and sees only its own
  // folder, and the system keeps other apps out of it: it cannot have the
  // app's settings, state or strips. It paints its own landscape, with the
  // least work.
  static let saverDefaults: [String: Any] = ["resolution": 0.5, "fps": 6, "minutesPerScreen": 10, "depth": false]

  // ---- actions

  private static func newSeed() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }

  /// Another landscape: blank paper, and the opening runs until the screen is full.
  func newLandscape() {
    seed = Landscape.newSeed()
    front = 0
    openingUntil = frontOnScreen
    strips = Landscape.empty
    save()
    arrange()
  }

  /// Changes an option and writes config.json, with every default key in it.
  func apply(_ changes: [String: Any]) {
    var o = changes
    for (k, v) in Landscape.defaults where o[k] == nil { o[k] = options[k] ?? v }
    options = o
    write(o, folders.config)
  }

  func pause() { paused = true; save() }
  func resume() { paused = false; save() }
  func turnOn() { if !active { active = true; save(); arrange() } }
  func turnOff() { if active { active = false; save() } }
  func toggle() { if active { turnOff() } else { turnOn() } }
  /// Moves the front n screens at once.
  func skip(_ screens: Double) { front += screens * viewWidth; save(); arrange() }

  /// What was written last: the same is not written again.
  private var saved: NSDictionary?
  func save() {
    guard loaded else { return }
    // The save runs every half minute while painting: the cost is noted then.
    usage.sample()
    let o: NSDictionary = ["on": active, "paused": paused, "seed": seed, "front": (front * 10).rounded() / 10]
    if saved == o { return }
    saved = o
    write(o as? [String: Any] ?? [:], folders.state)
  }

  private func write(_ o: [String: Any], _ url: URL) {
    guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? (d + Data("\n".utf8)).write(to: url, options: .atomic)
  }

  private static func json(_ d: Data?) -> [String: Any]? { d.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } }
  private static func read(_ url: URL) -> [String: Any]? { json(try? Data(contentsOf: url)) }

  // ---- timers

  /// Frames per second: the menu's is the maximum. With fpsAuto, only what the
  /// motion asks for (one point per frame, or one of the strip's pixels where
  /// they are coarser; at least 2). The opening, which runs, uses the maximum.
  var fpsMax: Double { number(options["fps"], 1, 60, 12) }
  var fpsNow: Double {
    // In Low Power Mode, half as many.
    let share = easeLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.5 : 1
    if (options["fpsAuto"] as? Bool) == false || front < openingUntil { return max(1, fpsMax * share) }
    let steps = Double(min(screenPoints, stripSize.w))
    return max(1, max(2, min(fpsMax, steps / secondsPerScreen)) * share)
  }

  private var lastTick = 0.0
  private var anim: Timer?
  private var saveTimer: Timer?
  private var problemTimer: Timer?

  /// Keeps `t` firing every `s` seconds, made again when `s` changes; nil
  /// stops it. A timer that fires once (`repeats` false) has an interval of 0,
  /// so it is always made again.
  private func keep(_ t: inout Timer?, _ s: Double?, repeats: Bool = true, _ f: @escaping () -> Void) {
    guard t?.timeInterval != s else { return }
    t?.invalidate()
    t = s.map { s in
      let fresh = Timer(timeInterval: s, repeats: repeats) { _ in f() }
      fresh.tolerance = s * 0.1
      RunLoop.main.add(fresh, forMode: .common)
      return fresh
    }
  }

  private func tick() {
    let now = Date().timeIntervalSince1970
    let dt = min(1, now - lastTick)
    lastTick = now
    // What the camera needs changes only as it walks.
    arrange()
    // The front only walks on paper that already exists.
    guard frontReady() else { return }
    var v = viewWidth / secondsPerScreen
    let screen = frontScreen, opening = openingUntil
    if front < openingUntil { v = max(v, viewWidth / 4) } else { openingUntil = -1 }
    walking = true
    front += v * dt
    walking = false
    // The rest (the menu, the timers) changes only with a new screen or the
    // end of the opening; at the other frames only the painting follows.
    if frontScreen != screen || openingUntil != opening {
      changed()
      return
    }
    onFrame?()
  }

  private func adjust() {
    let run = active && loaded && !paused && !covered
    if run && anim == nil { lastTick = Date().timeIntervalSince1970 }
    keep(&anim, run ? (10000 / fpsNow).rounded() / 10000 : nil) { [unowned self] in tick() }
    keep(&saveTimer, active && loaded && !paused && !covered ? 30 : nil) { [unowned self] in save() }
  }

  /// Called when anything the screen or the timers depend on has changed;
  /// `onFrame` when only the front has walked.
  var onChange: (() -> Void)?
  var onFrame: (() -> Void)?
  private var dirty = false
  func changed() {
    guard !dirty else { return }
    dirty = true
    DispatchQueue.main.async {
      self.dirty = false
      self.adjust()
      self.onChange?()
    }
  }

  // ---- files

  private var watcher: DispatchSourceFileSystemObject?

  private func readConfig() {
    var o = Landscape.defaults
    if Landscape.saver { o.merge(Landscape.saverDefaults) { $1 } }
    let d = try? Data(contentsOf: folders.config)
    if let c = Landscape.json(d) { o.merge(c) { $1 } } else if d != nil { NSLog("shanshui: config.json invalid, using the defaults") }
    if !NSDictionary(dictionary: o).isEqual(to: options) { options = o }
  }

  private init() {}

  func begin() {
    measureScreen()
    appearance = NSApp.observe(\.effectiveAppearance) { [unowned self] _, _ in forgetColors() }
    NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [unowned self] _ in
      forgetColors()
    }
    // Low Power Mode on or off: the frame rate follows (fpsNow).
    NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [unowned self] _ in
      changed()
    }
    let configDir = folders.config.deletingLastPathComponent()
    do {
      try Generator.prepare([configDir, folders.state.deletingLastPathComponent(), folders.cache])
      ready = true
    } catch {
      problem = "generate"
      NSLog("shanshui: %@", String(describing: error))
    }
    readConfig()
    // config.json reloads by itself: the folder tells when a file in it changes.
    let fd = open(configDir.path, O_EVTONLY)
    if fd >= 0 {
      let v = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
      v.setEventHandler { [unowned self] in readConfig() }
      v.resume()
      watcher = v
    }
    guard !loaded else { return }
    let e = Landscape.read(folders.state) ?? [:]
    active = Landscape.saver || (e["on"] as? Bool) != false
    paused = !Landscape.saver && (e["paused"] as? Bool) == true
    let s = e["seed"] as? String ?? ""
    let valid = Generator.validSeed(s)
    seed = valid ? s : Landscape.newSeed()
    front = number(e["front"], 0, 1e9, 0)
    // First time: opens with the run, like a new landscape.
    if !valid { openingUntil = frontOnScreen }
    loaded = true
    arrange()
  }

  func state() -> String {
    let o: [String: Any] = [
      "on": active, "paused": paused, "covered": covered, "ready": ready, "error": problem,
      "openingUntil": openingUntil, "front": front, "camera": camera, "frontScreen": frontScreen,
      "viewWidth": viewWidth, "fps": fpsNow, "stripSize": ["width": stripSize.w, "height": stripSize.h],
      "generating": generating, "pending": pending, "layers": layers,
      "strips": strips.map { $0.map { "\($0.c):\($0.k)" } as Any? ?? NSNull() }, "options": options,
    ]
    return (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }
}

/// The theme's colours. Omarchy has a theme; macOS has its appearance (light
/// or dark) and its accent colour, so those stand in for it.
enum Theme {
  private static let colors: [String: NSColor] = [
    "foreground": .textColor, "background": .textBackgroundColor, "accent": .controlAccentColor,
    "muted": .secondaryLabelColor, "urgent": .systemRed,
  ]

  /// A fixed "#rrggbb", or the theme's colour as it shows over the text
  /// background, in the app's appearance.
  static func color(_ name: String) -> SIMD4<Float>? {
    if name.count == 7, name.hasPrefix("#"), let v = UInt32(name.dropFirst(), radix: 16) {
      return SIMD4(Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255, 1)
    }
    var out: SIMD4<Float>?
    NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
      guard let background = NSColor.textBackgroundColor.usingColorSpace(.sRGB), let s = colors[name]?.usingColorSpace(.sRGB) else { return }
      let a = s.alphaComponent
      out = SIMD4(Float(s.redComponent * a + background.redComponent * (1 - a)), Float(s.greenComponent * a + background.greenComponent * (1 - a)),
                  Float(s.blueComponent * a + background.blueComponent * (1 - a)), 1)
    }
    return out
  }
}

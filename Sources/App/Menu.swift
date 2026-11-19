import AppKit
import MachO

// BarWidget.qml of the original: 山 in the menu bar. A click opens the menu;
// the right button turns it on and off directly.
final class Menu: NSObject {
  private final class Item: NSMenuItem {
    private var handler: (() -> Void)?
    convenience init(_ title: String, checked: Bool = false, active: Bool = true, tip: String = "", _ handler: (() -> Void)? = nil) {
      self.init(title: title, action: handler == nil ? nil : #selector(fire), keyEquivalent: "")
      self.handler = handler
      target = self
      state = checked ? .on : .off
      isEnabled = active && handler != nil
      if !tip.isEmpty { toolTip = tip }
    }
    @objc private func fire() { handler?() }
  }

  /// A slider in the menu: the header above it says the value while it
  /// moves, and the value is set when the mouse lets go.
  private final class Slider: NSMenuItem {
    private var say: ((Double) -> String)?
    private var apply: ((Double) -> Void)?
    private weak var header: NSMenuItem?

    convenience init(value: Double, from: Double, to: Double, header: NSMenuItem, tip: String,
                     say: @escaping (Double) -> String, apply: @escaping (Double) -> Void) {
      self.init(title: "", action: nil, keyEquivalent: "")
      self.say = say
      self.apply = apply
      self.header = header
      let r = NSSlider(value: value, minValue: from, maxValue: to, target: self, action: #selector(moved(_:)))
      r.controlSize = .small
      r.toolTip = tip
      r.frame = CGRect(x: 20, y: 3, width: 206, height: 20)
      r.autoresizingMask = [.width]
      let v = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 26))
      v.autoresizingMask = [.width]
      v.addSubview(r)
      view = v
    }

    @objc private func moved(_ r: NSSlider) {
      header?.title = say?(r.doubleValue) ?? ""
      if NSApp.currentEvent?.type == .leftMouseUp { apply?(r.doubleValue) }
    }
  }

  /// The app's cost over the last hour, drawn once when the menu opens; a gap
  /// where it was not painting.
  private final class Graph: NSView {
    private let values: [Double?]
    init(_ values: [Double?], tip: String) {
      self.values = values
      super.init(frame: CGRect(x: 0, y: 0, width: 240, height: 26))
      autoresizingMask = [.width]
      toolTip = tip
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirty: NSRect) {
      let top = max(values.compactMap { $0 }.max() ?? 0, 0.001)
      let left = 20.0, width = bounds.width - 34, step = width / 119
      let path = NSBezierPath()
      path.lineWidth = 1
      var drawing = false
      for (i, v) in values.enumerated() {
        guard let v else { drawing = false; continue }
        let point = CGPoint(x: left + Double(120 - values.count + i) * step, y: 4 + v / top * (bounds.height - 8))
        if drawing { path.line(to: point) } else { path.move(to: point) }
        drawing = true
      }
      NSColor.secondaryLabelColor.setStroke()
      path.stroke()
    }
  }

  /// The start of the program's own UUID (the linker gives every build one;
  /// `dwarfdump --uuid` and crash reports show the same).
  static let build: String = {
    guard let header = _dyld_get_image_header(0) else { return "" }
    var p = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
    for _ in 0..<header.pointee.ncmds {
      let c = p.assumingMemoryBound(to: load_command.self).pointee
      if c.cmd == UInt32(LC_UUID) {
        let u = p.advanced(by: MemoryLayout<load_command>.size).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { String(format: "%02x", u[$0]) }.joined()
      }
      p = p.advanced(by: Int(c.cmdsize))
    }
    return ""
  }()

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var p: Landscape { Landscape.shared }

  override init() {
    super.init()
    item.button?.title = "山"
    item.button?.target = self
    item.button?.action = #selector(click)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    update()
  }

  func status() -> String {
    if p.problem == "generate" { return "render failed, retrying" }
    if !p.active { return "off" }
    let part = " · scroll " + String(p.frontScreen + 1)
    if p.paused { return "paused" + part }
    if p.covered { return "waiting (fullscreen)" + part }
    if !p.frontReady() { return "preparing the paper" + part }
    return "painting" + part
  }

  func update() {
    // Called at every frame: only what changed is set.
    let alpha: CGFloat = p.active && !p.paused ? 1 : 0.4, tip = "Shan shui · " + status()
    if item.button?.alphaValue != alpha { item.button?.alphaValue = alpha }
    if item.button?.toolTip != tip { item.button?.toolTip = tip }
  }

  @objc private func click() {
    if NSApp.currentEvent?.type == .rightMouseUp { p.toggle(); return }
    item.menu = build()
    item.button?.performClick(nil)
    item.menu = nil
  }

  private func build() -> NSMenu {
    let m = NSMenu()
    m.autoenablesItems = false
    // A header and one item per value; the current one is checked.
    func group<T: Equatable>(_ title: String, _ current: T, _ options: [(value: T, label: String, tip: String)],
                             _ apply: @escaping (T) -> Void) {
      m.addItem(.sectionHeader(title: title))
      for o in options { m.addItem(Item(o.label, checked: o.value == current, tip: o.tip) { apply(o.value) }) }
    }

    m.addItem(Item("Shan Shui · " + status()))
    m.addItem(Item("On", checked: p.active) { self.p.toggle() })
    m.addItem(.separator())
    let canAct = p.active && p.problem.isEmpty
    m.addItem(Item(p.paused ? "Resume" : "Pause", active: canAct) {
      if self.p.paused { self.p.resume() } else { self.p.pause() }
    })
    m.addItem(Item("Skip ahead", active: canAct, tip: "Moves half a screen") { self.p.skip(0.5) })
    m.addItem(Item("New landscape", active: canAct, tip: "Blank paper, new seed") { self.p.newLandscape() })

    // The least work in one go: the screen saver's settings, and the back
    // layer the system draws most cheaply.
    let lightest = Landscape.saverDefaults.merging(["back": "opaque"]) { $1 }
    let isLightest = lightest.allSatisfy { k, v in NSDictionary(dictionary: [k: p.options[k] ?? NSNull()]).isEqual(to: [k: v]) }
    m.addItem(.separator())
    m.addItem(Item("Lightest settings", checked: isLightest,
                   tip: "One layer, half resolution, 6 frames a second, ten minutes a screen, less energy") { self.p.apply(lightest) })

    // Not in the original, which has a list of each: here they slide.
    // Time per screen from 15 s to 10 min, each step the same part faster.
    let times: [Double] = [0.25, 0.5, 1, 2, 5, 10]
    func time(_ t: Double) -> Double {
      var min = 0.25 * pow(40, t)
      if let near = times.first(where: { abs(log($0 / min)) < 0.07 }) { min = near }
      let s = min * 60, unit: Double = s < 120 ? 5 : 15
      return (s / unit).rounded() * unit / 60
    }
    func say(_ min: Double) -> String {
      let s = Int((min * 60).rounded())
      return "Speed · " + (s < 60 ? "\(s) s" : s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s") + " per screen"
    }
    let now = p.number(p.options["minutesPerScreen"], 0.25, 10, 5)
    m.addItem(.sectionHeader(title: say(now)))
    m.addItem(Slider(value: log(now / 0.25) / log(40), from: 0, to: 1, header: m.items.last!,
                     tip: "Time for the brush to cross one screen",
                     say: { say(time($0)) }, apply: { self.p.apply(["minutesPerScreen": time($0)]) }))
    // At most the slider's; the motion asks for fewer when it is slow, and
    // what macOS spends moving the picture follows how many.
    let fps = p.number(p.options["fps"], 6, 60, 12), running = Int(p.fpsNow.rounded())
    func motion(_ f: Double) -> String { "Motion · up to \(Int(f.rounded())) fps" + (running < Int(f.rounded()) ? " · now \(running)" : "") }
    m.addItem(.sectionHeader(title: motion(fps)))
    m.addItem(Slider(value: fps, from: 6, to: 60, header: m.items.last!,
                     tip: "Frames per second at most: more is smoother and costs more",
                     say: { motion($0) }, apply: { self.p.apply(["fps": $0.rounded()]) }))
    // Not in the original, whose strips are always the screen's size.
    let res = (p.number(p.options["resolution"], 0.5, 1, 1) * 20).rounded() * 5
    m.addItem(.sectionHeader(title: "Resolution · \(Int(res)) %"))
    m.addItem(Slider(value: res, from: 50, to: 100, header: m.items.last!,
                     tip: "How finely the landscape is drawn: less is softer and takes less memory",
                     say: { "Resolution · \(Int(($0 / 5).rounded() * 5)) %" },
                     apply: { self.p.apply(["resolution": ($0 / 5).rounded() * 5 / 100]) }))
    // Palettes: ink on paper. "Invert" swaps the two in any of them.
    group("Colors", [p.options["ink"], p.options["paper"]].compactMap { $0 as? String },
          [(["foreground", "background"], "Theme", ""),
           (["accent", "background"], "Accent", ""),
           (["#2b2b2b", "#f2e8d5"], "Rice paper", "")]) { self.p.apply(["ink": $0[0], "paper": $0[1]]) }
    m.addItem(Item("Invert colors", checked: p.inverted) { self.p.apply(["invert": !self.p.inverted]) })
    // Not in the original, which has depth on or off: two layers stand between.
    group("Depth (parallax)", p.layers,
          [(1, "1 layer", "No depth, the cheapest"),
           (2, "2 layers", "The far background and the rest"),
           (3, "3 layers", "Far, middle and near; the most expensive")]) {
      self.p.apply($0 == 1 ? ["depth": false] : ["depth": true, "layers": $0])
    }
    // How the back layer is kept: what the user gets, not how.
    group("Prefer", p.back,
          [(.opaque, "Less energy", "The Mac's graphics do the least work. Uses about twice the memory"),
           (.mono, "Less memory", "About half the memory. The graphics work a little harder at every frame")]) {
      self.p.apply(["back": $0.rawValue])
    }
    m.addItem(Item("Ease off in Low Power Mode", checked: p.easeLowPower, tip: "Half the frames while the Mac is in Low Power Mode") {
      self.p.apply(["easeLowPower": !self.p.easeLowPower])
    })
    // What the app itself costs: noted every half minute while painting, and now.
    p.usage.sample()
    let memory = { (b: Int) in "\(Int((Double(b) / 1_048_576).rounded())) MB" }
    var cost = "Cost · "
    if let r = p.usage.recent() {
      cost += String(format: "%.1f %% of a core · ", r.core) + memory(r.memory) + (r.milliwatts > 0 ? " · \(Int(r.milliwatts.rounded())) mW" : "")
    } else {
      cost += memory(p.usage.samples.last?.memory ?? 0) + " · measuring"
    }
    m.addItem(.sectionHeader(title: cost))
    let graph = NSMenuItem()
    graph.view = Graph(p.usage.history(), tip: "The app's own processor use and memory over the last hour, drawing new landscape included. "
                       + "Moving the picture on screen is done by macOS and is not counted here: it follows Motion (now \(running) frames a second).")
    m.addItem(graph)
    m.addItem(.separator())
    // Not in the original: there the shell owns the plugin's life.
    m.addItem(Item("Quit") { self.p.save(); NSApp.terminate(nil) })
    // Not in the original: which version this is, and which build of it, in small print.
    if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
      let version = Item("")
      version.attributedTitle = NSAttributedString(string: "Version " + v + (Menu.build.isEmpty ? "" : " · " + Menu.build), attributes: [
        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 1), .foregroundColor: NSColor.tertiaryLabelColor,
      ])
      m.addItem(version)
    }
    return m
  }
}

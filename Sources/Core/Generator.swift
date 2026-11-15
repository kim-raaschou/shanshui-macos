import Foundation

// gerar.js of the original: the strips of {Shan, Shui}* and their folder.
// The generator is {Shan, Shui}* in Swift (ShanShui.swift) where the original
// runs it in node, and the pixels come from Svg instead of rsvg-convert.
//
// The landscape is endless in x; each 512-unit chunk has its own seed
// (seed|x0), so any strip comes out the same without what came before it.
// The world is 800 tall and the view shows 700 of it.

enum Generator {
  static let viewH = PAINT_HEIGHT

  /// Everything that changes the drawing of a strip, and so its files' name:
  /// <seed>_<k>_<w>x<h>, an "f" when the delay is as big as the strip
  /// (`full`), and the layer: _c0.._c2 of three, _d0 and _d1 of two.
  static func key(_ seed: String, _ k: Int, _ w: Int, _ h: Int, _ c: Int?, of: Int, full: Bool) -> String {
    "\(seed)_\(k)_\(w)x\(h)" + (full ? "f" : "") + (c.map { (of == 2 ? "_d" : "_c") + String($0) } ?? "")
  }

  /// The painting's file and the delay's.
  static func names(_ key: String) -> (q: String, o: String) { ("q_\(key).strip", "o_\(key).strip") }
  private static let stripName = try! NSRegularExpression(pattern: "^[qo]_[0-9]{1,20}_-?[0-9]{1,8}_[0-9]{2,5}x[0-9]{2,5}f?(_[cd][0-2])?\\.(strip|faixa|png)$")

  /// Digits only: the seed becomes a file name.
  static func validSeed(_ s: String) -> Bool { !s.isEmpty && s.count <= 20 && s.allSatisfy { $0.isASCII && $0.isNumber } }

  static func existsValid(_ url: URL) -> Bool {
    guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
    return a[.type] as? FileAttributeType == .typeRegular && ((a[.size] as? NSNumber)?.intValue ?? 0) > 0
  }

  /// One strip: q_<seed>_<k>_<w>x<h>.strip (the painting, in grey: 0 ink, 1
  /// paper) and o_<...>.strip (the delay of each pixel). `layers` nil is
  /// everything together on paper; otherwise only those depth layers (0 far,
  /// the last near) of `of`, on a clear background. A strip painted before is
  /// kept as it is.
  static func strip(dir: URL, seed: String, k: Int, w: Int, h: Int, scale: Double, layers: [Int]?, of: Int, full: Bool) throws {
    let list: [Int?] = layers.map { $0.map { Optional($0) } } ?? [nil]
    var world: Drawing?
    for c in list {
      let n = names(key(seed, k, w, h, c, of: of, full: full))
      let uq = dir.appendingPathComponent(n.q), uo = dir.appendingPathComponent(n.o)
      if existsValid(uq), existsValid(uo) { continue }
      if world == nil { world = Drawing(seed: seed, cursor: Double(k) * viewH * Double(w) / Double(h), w: w, h: h) }
      // Both drawn before either is painted, in the generator's order; one bitmap at a time.
      let q = world!.picture(c, of), o = world!.delay(c, of)
      try Svg.store(Svg.rasterize(o, w: Int((Double(w) * scale).rounded()), h: Int((Double(h) * scale).rounded())), .delay, uo)
      try Svg.store(Svg.rasterize(q, w: w, h: h), c == nil ? .gray : .grayAlpha, uq)
    }
  }

  /// Deletes the strips that are not in the list. Only names this file makes.
  static func clear(dir: URL, keep: Set<String>) {
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
      guard stripName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil, !keep.contains(name) else { continue }
      try? fm.removeItem(at: dir.appendingPathComponent(name))
    }
  }

  static func prepare(_ dirs: [URL]) throws {
    for d in dirs {
      try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
  }

  /// A coloured view (preview, tests); writes nothing.
  static func png(seed: String, x: Double, w: Int, h: Int, ink: String?, paper: String?, delay: Bool, layer: Int?) throws -> Data {
    let d = Drawing(seed: seed, cursor: x, w: w, h: h, ink: ink, paper: paper)
    return try Svg.png(Svg.rasterize(delay ? d.delay(layer, 3) : d.picture(layer, 3), w: w, h: h))
  }
}

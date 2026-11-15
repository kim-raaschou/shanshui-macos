import Foundation

// The drawing part of gerar.js (omarchy-shanshui): the SVG of a view of the
// landscape from x = cursor, and that of its delay map. Its regular
// expressions are written out here as scans of the text.

/// A view W x H of the landscape, drawn from x = cursor.
final class Drawing {
  private let g = ShanShui()
  private let cursor: Double, W: Double, H: Double, viewW: Double
  private let visible: [ShanShui.Chunk]
  private let ink: [Double], paper: [Double]
  static let viewH = 700.0

  private static func hex(_ s: String?, _ fallback: String) -> [Double] {
    var h = fallback
    if var t = s {
      if t.hasPrefix("#") { t.removeFirst() }
      if t.utf8.count == 6, t.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 | 32 >= 97 && $0 | 32 <= 102) }) { h = t }
    }
    let v = UInt32(h, radix: 16)!
    return [Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255)]
  }

  init(seed: String, cursor: Double, w: Int, h: Int, ink: String? = nil, paper: String? = nil) {
    self.cursor = cursor
    W = Double(w); H = Double(h)
    g.seed(seed)
    _ = g.noise(0)   // builds the Perlin table with the global seed
    g.onchunk = { [unowned g] x0 in g.seed(seed + "|" + jsString(x0)) }
    viewW = (Drawing.viewH * W) / H
    let CW = g.cwid
    // Generates 3000 more to the left only as context: whether flat hills are
    // put down depends on the neighbouring mountains already planted, and two
    // strips side by side must see exactly the same world to have no seam. Far
    // mountains are up to 1500 wide, the others spill over by some 500.
    let start = ((cursor - 3000) / CW).rounded(.down) * CW
    g.xmin = start; g.xmax = start
    g.chunkloader(start + CW, cursor + viewW + 600)
    let (c, vw) = (cursor, viewW)
    visible = g.chunks.filter { $0.x > c - 1600 && $0.x < c + vw + 600 }
    self.ink = Drawing.hex(ink, "000000")
    self.paper = Drawing.hex(paper, "ffffff")
  }

  // Depth: 0 the far background, 1 the middle, 2 the foreground. It goes by the
  // stroke's height in the world (water comes with y-10000 and stays with its mountain).
  private func layerOf(_ c: ShanShui.Chunk) -> Int {
    if c.tag == "distmount" { return 0 }
    let y = c.y < 0 ? c.y + 10000 : c.y
    return y < 380 ? 0 : y < 540 ? 1 : 2
  }

  // The strokes of a layer (c nil: all of them), in drawing order.
  // Not in the original: with n = 2 the middle goes with the foreground, so
  // there are two layers, the far one and the rest.
  private func ofLayer(_ c: Int?, _ n: Int) -> [ShanShui.Chunk] {
    guard let c else { return visible }
    return visible.filter { (n == 2 ? min(layerOf($0), 1) : layerOf($0)) == c }
  }

  // Everything in the original is grey on paper: the luminance decides where
  // the colour falls between the ink (black) and the paper (white).
  private var mixed: [Int: [UInt8]] = [:]

  /// "r,g,b" of a grey between ink and paper.
  private func mix(_ r: Double, _ g: Double, _ b: Double) -> [UInt8] {
    // The same few greys come again and again.
    let key = r >= 0 && r < 256 && g >= 0 && g < 256 && b >= 0 && b < 256 && r == r.rounded() && g == g.rounded() && b == b.rounded()
      ? Int(r) << 16 | Int(g) << 8 | Int(b) : -1
    if key >= 0, let c = mixed[key] { return c }
    let t = jsMin(1, jsMax(0, (0.299 * r + 0.587 * g + 0.114 * b) / 255))
    let c = Array((0..<3).map { jsString((ink[$0] + (paper[$0] - ink[$0]) * t + 0.5).rounded(.down)) }.joined(separator: ",").utf8)
    if key >= 0 { mixed[key] = c }
    return c
  }

  /// A number of digits and points, as JavaScript reads it: not a number when it has two points or none of either.
  private static func number(_ t: ArraySlice<UInt8>) -> Double {
    var m: UInt64 = 0, digits = 0, after = -1
    for c in t {
      if c == 46 {
        if after >= 0 { return .nan }
        after = 0
      } else {
        guard digits < 18 else { return Double(String(decoding: t, as: UTF8.self)) ?? .nan }
        m = m * 10 + UInt64(c - 48); digits += 1
        if after >= 0 { after += 1 }
      }
    }
    if digits == 0 { return .nan }
    // Whole numbers this small, and their division, are exact: the nearest double.
    guard m < 1 << 53, after <= 22 else { return Double(String(decoding: t, as: UTF8.self)) ?? .nan }
    return after <= 0 ? Double(m) : Double(m) / pow(10, Double(after))
  }

  /// rgb(..) and rgba(..) through `mix`, then white, black and NaN.
  private func paint(_ body: String) -> String {
    let s = Array(body.utf8)
    var out = [UInt8]()
    out.reserveCapacity(s.count + s.count / 8)
    let n = s.count
    func space(_ i: inout Int) { while i < n, s[i] == 32 || (s[i] >= 9 && s[i] <= 13) { i += 1 } }
    func number(_ i: inout Int) -> Range<Int>? {
      let a = i
      while i < n, (s[i] >= 48 && s[i] <= 57) || s[i] == 46 { i += 1 }
      return i > a ? a..<i : nil
    }
    func value(_ r: Range<Int>) -> Double { Drawing.number(s[r]) }
    func word(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || (c | 32 >= 97 && c | 32 <= 122) || c == 95 }
    func has(_ i: Int, _ t: StaticString) -> Bool {
      let k = t.utf8CodeUnitCount
      guard i + k <= n else { return false }
      return t.withUTF8Buffer { b in (0..<k).allSatisfy { s[i + $0] == b[$0] } }
    }
    var i = 0
    while i < n {
      // rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)
      if s[i] == 114, has(i, "rgb") {
        var j = i + 3
        if j < n, s[j] == 97 { j += 1 }
        if j < n, s[j] == 40 {
          j += 1
          space(&j)
          if let r = number(&j) {
            space(&j)
            if j < n, s[j] == 44 {
              j += 1; space(&j)
              if let gg = number(&j) {
                space(&j)
                if j < n, s[j] == 44 {
                  j += 1; space(&j)
                  if let b = number(&j) {
                    space(&j)
                    var al: Range<Int>?
                    var k = j
                    if k < n, s[k] == 44 {
                      k += 1; space(&k)
                      if let a = number(&k) { space(&k); if k < n, s[k] == 41 { al = a; j = k } }
                    }
                    if j < n, s[j] == 41 {
                      // `rgb(c)`, or `rgba(c,alpha)` with the alpha as it stands.
                      out.append(contentsOf: al == nil ? [114, 103, 98, 40] : [114, 103, 98, 97, 40])
                      out.append(contentsOf: mix(value(r), value(gg), value(b)))
                      if let al { out.append(44); out.append(contentsOf: s[al]) }
                      out.append(41)
                      i = j + 1
                      continue
                    }
                  }
                }
              }
            }
          }
        }
      }
      // :\s*white\b and :\s*black\b
      if s[i] == 58 {
        var j = i + 1
        space(&j)
        let white = has(j, "white"), black = has(j, "black")
        if white || black, j + 5 >= n || !word(s[j + 5]) {
          out.append(contentsOf: [58, 114, 103, 98, 40])
          out.append(contentsOf: white ? mix(255, 255, 255) : mix(0, 0, 0))
          out.append(41)
          i = j + 5
          continue
        }
      }
      if s[i] == 78, has(i, "NaN") {
        out.append(contentsOf: "-1000".utf8)
        i += 3
        continue
      }
      out.append(s[i])
      i += 1
    }
    return String(decoding: out, as: UTF8.self)
  }

  private func wrap(_ body: String, _ background: String, _ root: String = "") -> String {
    let c = jsString(cursor), vw = jsString(viewW), vh = jsString(Drawing.viewH)
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + jsString(W) + "\" height=\"" + jsString(H) + "\" " + root + " "
      + "viewBox=\"" + c + " 0 " + vw + " " + vh + "\" preserveAspectRatio=\"xMidYMid slice\">"
      + "<defs></defs>"
      + (background.isEmpty ? "" : "<rect x=\"" + jsString(cursor - 10) + "\" y=\"-10\" width=\"" + jsString(viewW + 20) + "\" height=\""
          + jsString(Drawing.viewH + 20) + "\" fill=\"" + background + "\"/>")
      + "<g>" + body + "</g>"
      + "</svg>"
  }

  // Delay map: how far each stroke comes behind the painting front, which
  // walks from left to right. The pixel is painted when the front passes
  // (its x + delay * spread). The delay depends only on the element itself -
  // depth (background before foreground) and the stroke's place inside it
  // (outline before texture) -, so it comes out the same in any strip and the
  // seams do not show. 16 bits in R (high) and G (low); 0 is the paper.
  // A nearly transparent stroke is left out: the pixel keeps the delay of the one below.
  private func delayOf(_ c: ShanShui.Chunk) -> String {
    let s = Array(ShanShui.withoutNaN(c.canv).utf8)
    let n = s.count
    let mark = Array("style='".utf8)
    func at(_ i: Int, _ t: [UInt8]) -> Bool { i + t.count <= n && (0..<t.count).allSatisfy { s[i + $0] == t[$0] } }
    var styles = 0
    for i in 0..<n where s[i] == 115 && at(i, mark) { styles += 1 }
    let count = Double(styles == 0 ? 1 : styles)
    // water comes with y-10000; far mountains ~250, the near ones ~700
    let depth = c.y < 0 ? 0 : jsMin(1, jsMax(0, (c.y - 200) / 650))

    /// The text after `key` up to the next ';' in a style.
    func part(_ st: ArraySlice<UInt8>, _ key: String) -> ArraySlice<UInt8>? {
      let k = Array(key.utf8)
      var i = st.startIndex
      while i + k.count <= st.endIndex {
        if st[i..<(i + k.count)].elementsEqual(k) {
          var j = i + k.count
          while j < st.endIndex, st[j] != 59 { j += 1 }
          return st[(i + k.count)..<j]
        }
        i += 1
      }
      return nil
    }
    /// 0 for nothing or "none"; the last number of rgba(..), or 1.
    func alpha(_ x: ArraySlice<UInt8>?) -> Double {
      guard let x, !x.isEmpty else { return 0 }
      func find(_ t: [UInt8], from: Int) -> Int? {
        var i = from
        while i + t.count <= x.endIndex {
          if x[i..<(i + t.count)].elementsEqual(t) { return i }
          i += 1
        }
        return nil
      }
      if find([110, 111, 110, 101], from: x.startIndex) != nil { return 0 }
      // rgba\([^)]*,\s*([\d.]+)\s*\)
      guard let open = find([114, 103, 98, 97, 40], from: x.startIndex), let close = x[(open + 5)...].firstIndex(of: 41),
            let comma = x[(open + 5)..<close].lastIndex(of: 44) else { return 1 }
      var a = comma + 1, b = close
      while a < b, x[a] == 32 || (x[a] >= 9 && x[a] <= 13) { a += 1 }
      while b > a, x[b - 1] == 32 || (x[b - 1] >= 9 && x[b - 1] <= 13) { b -= 1 }
      guard a < b, x[a..<b].allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 46 }) else { return 1 }
      return Drawing.number(x[a..<b])
    }

    var out = [UInt8]()
    out.reserveCapacity(n)
    var i = 0, index = 0.0
    while i < n {
      if s[i] == 115, at(i, mark) {
        var j = i + mark.count
        while j < n, s[j] != 39 { j += 1 }
        if j < n {
          let st = s[(i + mark.count)..<j]
          let d = 0.6 * depth + 0.4 * (index / count)
          index += 1
          let v = Int((d * 65534 + 0.5).rounded(.down)) + 1
          let color = "rgb(\(v >> 8),\(v & 255),0)"
          let f = part(st, "fill:"), k = part(st, "stroke:"), w = part(st, "stroke-width:")
          let fill = alpha(f) >= 0.1 ? color : "none"
          let stroke = k == nil ? (fill == "none" ? "none" : color) : alpha(k) >= 0.1 ? color : "none"
          out.append(contentsOf: ("style='fill:" + fill + ";stroke:" + stroke).utf8)
          if let w { out.append(contentsOf: ";stroke-width:".utf8); out.append(contentsOf: w) }
          out.append(39)
          i = j + 1
          continue
        }
      }
      out.append(s[i])
      i += 1
    }
    return String(decoding: out, as: UTF8.self)
  }

  // The world is planted only once; any number of layers come out of it.

  /// A loose layer: no paper, what has no stroke stays clear.
  func picture(_ c: Int?, _ n: Int) -> String {
    wrap(paint(ofLayer(c, n).map(\.canv).joined()), c == nil ? "rgb(" + paper.map(jsString).joined(separator: ",") + ")" : "")
  }

  /// No antialiasing: a blended edge would become a moment that does not exist.
  func delay(_ c: Int?, _ n: Int) -> String {
    wrap(ofLayer(c, n).map(delayOf).joined(), "rgb(0,0,0)", "shape-rendering=\"crispEdges\" text-rendering=\"optimizeSpeed\"")
  }
}

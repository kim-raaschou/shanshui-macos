import CoreGraphics
import CoreText
import Foundation
import ImageIO

// Stands where rsvg-convert stands in the original: turns the SVG the
// generator writes into pixels. The generator only writes polylines, one kind
// of text and a background rect, so that is all this reads.

struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ d: String) { description = d }
}

enum Svg {
  static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

  /// RGBA, 8 bits, alpha premultiplied, top row first.
  static func rasterize(_ svg: String, w: Int, h: Int) throws -> CGContext {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure("no bitmap \(w)x\(h)") }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColorSpace(srgb)
    ctx.setStrokeColorSpace(srgb)
    // SVG's defaults.
    ctx.setLineJoin(.miter)
    ctx.setMiterLimit(4)
    ctx.setLineCap(.butt)
    // A zero after the text: the reader may look one past the end.
    (Array(svg.utf8) + [0]).withUnsafeBufferPointer { p in
      var l = Reader(p: p, n: p.count - 1, ctx: ctx, w: w, h: h)
      l.read()
    }
    return ctx
  }

  // ---- PNG

  static func png(_ c: CGContext) throws -> Data {
    guard let img = c.makeImage() else { throw Failure("no image") }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { throw Failure("no png") }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw Failure("png not written") }
    return out as Data
  }

  // ---- the cache's own files
  //
  // A strip is kept as the painting reads it: one or two channels, as they
  // are, after 12 bytes that tell which. Nothing is decoded: the file is
  // mapped, and the system reads only the parts the painting gets to.

  static func store(_ c: CGContext, _ format: Format, _ url: URL) throws {
    let n = c.width * c.height, channels = format.channels, second = format == .grayAlpha ? 3 : 1
    let src = c.data!.assumingMemoryBound(to: UInt8.self)
    var d = Data(count: 12 + n * channels)
    d.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
      for (i, v) in [channels, c.width, c.height].enumerated() { dst.storeBytes(of: UInt32(v).littleEndian, toByteOffset: i * 4, as: UInt32.self) }
      if channels == 1 { for i in 0..<n { dst[12 + i] = src[i * 4] } }
      else { for i in 0..<n { dst[12 + i * 2] = src[i * 4]; dst[13 + i * 2] = src[i * 4 + second] } }
    }
    try d.write(to: url, options: .atomic)
  }

  static func read(_ url: URL, _ format: Format) throws -> Bitmap {
    let d = try Data(contentsOf: url, options: .alwaysMapped)
    guard d.count > 12 else { throw Failure("strip not read: \(url.lastPathComponent)") }
    func u32(_ i: Int) -> Int { Int(d.subdata(in: i..<(i + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian) }
    let channels = u32(0), w = u32(4), h = u32(8)
    guard channels == format.channels, w > 0, h > 0 else { throw Failure("strip not valid: \(url.lastPathComponent)") }
    if d.count == 12 + w * h * channels { return Bitmap(data: d, start: 12, w: w, h: h, channels: channels) }
    // A file of before, compressed.
    let bytes = try (d.subdata(in: 12..<d.count) as NSData).decompressed(using: .lzfse) as Data
    guard bytes.count == w * h * channels else { throw Failure("strip not valid: \(url.lastPathComponent)") }
    return Bitmap(data: bytes, start: 0, w: w, h: h, channels: channels)
  }
}

/// A strip's channels, as its file has them from `start` on.
struct Bitmap {
  let data: Data
  let start: Int
  let w: Int
  let h: Int
  let channels: Int
}

/// What a strip's picture keeps of its four channels.
enum Format {
  case gray       // the painting on paper: grey alone
  case grayAlpha   // a depth layer: grey and alpha
  case delay       // the delay: 16 bits in R and G
  var channels: Int { self == .gray ? 1 : 2 }
}

private typealias RGBA = (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

private struct Reader {
  let p: UnsafeBufferPointer<UInt8>
  let n: Int
  let ctx: CGContext
  let w: Int
  let h: Int
  var points: [CGPoint] = []
  var attributes: [(name: Range<Int>, value: Range<Int>)] = []

  func equals(_ r: Range<Int>, _ s: StaticString) -> Bool { r.count == s.utf8CodeUnitCount && starts(r, s) }

  func starts(_ r: Range<Int>, _ s: StaticString) -> Bool {
    guard r.count >= s.utf8CodeUnitCount else { return false }
    return memcmp(p.baseAddress! + r.lowerBound, s.utf8Start, s.utf8CodeUnitCount) == 0
  }

  func trim(_ r: Range<Int>) -> Range<Int> {
    var a = r.lowerBound, b = r.upperBound
    while a < b, p[a] <= 32 { a += 1 }
    while b > a, p[b - 1] <= 32 { b -= 1 }
    return a..<b
  }

  /// The next number at or after `i`, before `end`; nil when there is none.
  func number(_ i: inout Int, _ end: Int) -> Double? {
    while i < end, p[i] <= 32 || p[i] == 44 { i += 1 }
    guard i < end else { return nil }
    let neg = p[i] == 45
    if neg || p[i] == 43 { i += 1 }
    var v = 0.0, f = 0.1, found = false
    while i < end, p[i] >= 48, p[i] <= 57 { v = v * 10 + Double(p[i] - 48); i += 1; found = true }
    if i < end, p[i] == 46 {
      i += 1
      while i < end, p[i] >= 48, p[i] <= 57 { v += Double(p[i] - 48) * f; f *= 0.1; i += 1; found = true }
    }
    guard found else { i = end; return nil }
    if i < end, p[i] == 101 || p[i] == 69 {
      var j = i + 1, e = 0, hasExp = false
      let eneg = j < end && p[j] == 45
      if eneg || (j < end && p[j] == 43) { j += 1 }
      while j < end, p[j] >= 48, p[j] <= 57 { e = e * 10 + Int(p[j] - 48); j += 1; hasExp = true }
      if hasExp { v *= pow(10, Double(eneg ? -e : e)); i = j }
    }
    return neg ? -v : v
  }

  func number(_ r: Range<Int>?) -> Double? {
    guard let r else { return nil }
    var i = r.lowerBound
    return number(&i, r.upperBound)
  }

  func color(_ raw: Range<Int>) -> RGBA? {
    let r = trim(raw)
    if starts(r, "rgb") {
      var i = r.lowerBound
      while i < r.upperBound, p[i] != 40 { i += 1 }
      i += 1
      // The numbers stop at ')' by themselves: number reads nothing past a character that is not one.
      let end = r.upperBound
      guard let cr = number(&i, end), let cg = number(&i, end), let cb = number(&i, end) else { return nil }
      let a = number(&i, end) ?? 1
      return (CGFloat(min(255, max(0, cr)) / 255), CGFloat(min(255, max(0, cg)) / 255),
              CGFloat(min(255, max(0, cb)) / 255), CGFloat(min(1, max(0, a))))
    }
    if equals(r, "white") { return (1, 1, 1, 1) }
    if equals(r, "black") { return (0, 0, 0, 1) }
    return nil
  }

  func attribute(_ name: StaticString) -> Range<Int>? {
    for a in attributes where equals(a.name, name) { return a.value }
    return nil
  }

  func attribute(_ name: StaticString, is value: StaticString) -> Bool { attribute(name).map { equals($0, value) } ?? false }

  /// `fill:..;stroke:..;stroke-width:..`, with SVG's defaults for what is absent.
  func style(_ r: Range<Int>?) -> (fill: RGBA?, stroke: RGBA?, width: Double) {
    var fill: RGBA? = (0, 0, 0, 1), stroke: RGBA? = nil, width = 1.0
    guard let r else { return (fill, stroke, width) }
    var i = r.lowerBound
    while i < r.upperBound {
      var j = i
      while j < r.upperBound, p[j] != 59 { j += 1 }
      var m = i
      while m < j, p[m] != 58 { m += 1 }
      if m < j {
        let key = trim(i..<m), value = (m + 1)..<j
        if equals(key, "fill") { fill = color(value) }
        else if equals(key, "stroke") { stroke = color(value) }
        else if equals(key, "stroke-width") { width = number(value) ?? 1 }
      }
      i = j + 1
    }
    return (fill, stroke, width)
  }

  mutating func read() {
    var i = 0
    while i < n {
      guard p[i] == 60 else { i += 1; continue }
      var j = i + 1
      if j < n, p[j] == 47 || p[j] == 33 || p[j] == 63 {
        while j < n, p[j] != 62 { j += 1 }
        i = j + 1
        continue
      }
      let nameStart = j
      while j < n, p[j] > 32, p[j] != 62, p[j] != 47 { j += 1 }
      let name = nameStart..<j
      attributes.removeAll(keepingCapacity: true)
      while j < n {
        while j < n, p[j] <= 32 { j += 1 }
        if j >= n || p[j] == 62 { break }
        if p[j] == 47 { j += 1; continue }
        let a = j
        while j < n, p[j] != 61, p[j] != 62, p[j] > 32 { j += 1 }
        let attributeName = a..<j
        guard j < n, p[j] == 61 else { continue }
        j += 1
        guard j < n, p[j] == 39 || p[j] == 34 else { continue }
        let quote = p[j]
        j += 1
        let v = j
        while j < n, p[j] != quote { j += 1 }
        attributes.append((attributeName, v..<j))
        j += 1
      }
      i = j + 1
      if equals(name, "polyline") { polyline() }
      else if equals(name, "text") {
        var end = i
        while end < n, p[end] != 60 { end += 1 }
        text(i..<end)
        i = end
      } else if equals(name, "rect") { rect() }
      else if equals(name, "svg") { svg() }
    }
  }

  func svg() {
    if attribute("shape-rendering", is: "crispEdges") {
      ctx.setShouldAntialias(false)
      ctx.setAllowsAntialiasing(false)
    }
    guard let vb = attribute("viewBox") else { return }
    var i = vb.lowerBound
    guard let x = number(&i, vb.upperBound), let y = number(&i, vb.upperBound),
          let vw = number(&i, vb.upperBound), let vh = number(&i, vb.upperBound), vw > 0, vh > 0 else { return }
    // preserveAspectRatio="xMidYMid slice"
    let s = max(Double(w) / vw, Double(h) / vh)
    ctx.translateBy(x: CGFloat((Double(w) - vw * s) / 2 - x * s), y: CGFloat((Double(h) - vh * s) / 2 - y * s))
    ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
  }

  func rect() {
    guard attribute("filter") == nil, let f = attribute("fill"), let c = color(f),
          let x = number(attribute("x")), let y = number(attribute("y")),
          let rw = number(attribute("width")), let rh = number(attribute("height")) else { return }
    ctx.setFillColor([c.r, c.g, c.b, c.a])
    ctx.fill(CGRect(x: x, y: y, width: rw, height: rh))
  }

  mutating func polyline() {
    guard let pts = attribute("points") else { return }
    points.removeAll(keepingCapacity: true)
    var i = pts.lowerBound
    while let x = number(&i, pts.upperBound), let y = number(&i, pts.upperBound) {
      points.append(CGPoint(x: x, y: y))
    }
    guard points.count > 1 else { return }
    let e = style(attribute("style"))
    let fills = e.fill != nil && e.fill!.a > 0
    let strokes = e.stroke != nil && e.stroke!.a > 0 && e.width > 0
    guard fills || strokes else { return }
    if let f = e.fill, fills { ctx.setFillColor([f.r, f.g, f.b, f.a]) }
    if let s = e.stroke, strokes {
      ctx.setStrokeColor([s.r, s.g, s.b, s.a])
      ctx.setLineWidth(CGFloat(e.width))
    }
    ctx.beginPath()
    ctx.addLines(between: points)
    ctx.drawPath(using: fills && strokes ? .fillStroke : fills ? .fill : .stroke)
  }

  func text(_ content: Range<Int>) {
    let e = style(attribute("style"))
    guard let f = e.fill, f.a > 0, let size = number(attribute("font-size")), size > 0 else { return }
    var tx = 0.0, ty = 0.0, degrees = 0.0
    if let t = attribute("transform") {
      var i = t.lowerBound
      tx = number(&i, t.upperBound) ?? 0
      ty = number(&i, t.upperBound) ?? 0
      while i < t.upperBound, p[i] != 40 { i += 1 }
      i += 1
      degrees = number(&i, t.upperBound) ?? 0
    }
    let font = CTFontCreateWithName("Verdana" as CFString, CGFloat(size), nil)
    let color = CGColor(colorSpace: Svg.srgb, components: [f.r, f.g, f.b, f.a])!
    let s = NSAttributedString(string: String(decoding: p[content], as: UTF8.self), attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
    let line = CTLineCreateWithAttributedString(s)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(tx), y: CGFloat(ty))
    ctx.rotate(by: CGFloat(degrees * .pi / 180))
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = CGPoint(x: attribute("text-anchor", is: "middle") ? -width / 2 : 0, y: 0)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }
}

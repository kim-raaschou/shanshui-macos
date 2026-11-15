import Foundation

// {Shan, Shui}* by Lingdong Huang (MIT, https://github.com/LingDong-/shan-shui-inf),
// from JavaScript to Swift. The landscape of a seed is the original's, stroke
// for stroke: the same random numbers are drawn in the same order, and every
// sum is done as JavaScript does it (JSNumbers). The names are the original's,
// so the two can be read side by side.
//
// This file is the original's tools: the random numbers, the noise, the
// polygons and the brush. The things that are drawn are in the files beside it.

/// A point, [x, y] in the original.
typealias Pt = SIMD2<Double>

extension Array where Element == Double {
  /// As JavaScript reads an array: what is not there is not a number.
  subscript(js i: Int) -> Double { i >= 0 && i < count ? self[i] : .nan }
}

/// JavaScript's ToInt32, for `x | 0` and the shifts.
func jsInt32(_ v: Double) -> Int32 {
  guard v.isFinite else { return 0 }
  let m = v.rounded(.towardZero).truncatingRemainder(dividingBy: 4294967296)
  return Int32(truncatingIfNeeded: Int64(m))
}

/// One world: its own random numbers and noise, so two can be made at once.
final class ShanShui {
  // ---- MEM

  var chunks: [Chunk] = []
  var xmin = 0.0, xmax = 0.0
  let cwid = 512.0
  /// How many mountains stand over each five units of the world. The original
  /// keeps it in an array and reads it left of 0 as well, so it is a dictionary.
  var planmtx: [Int: Double] = [:]
  var onchunk: ((Double) -> Void)?

  // ---- Prng

  private var s = 1234.0
  private static let p = 999979.0, q = 999983.0, m = p * q

  private static func hash(_ x: String) -> Double {
    // JSON.stringify of the seed: in quotes, with what JSON escapes.
    var json = "\""
    for c in x.unicodeScalars {
      switch c {
      case "\"": json += "\\\""
      case "\\": json += "\\\\"
      case "\u{8}": json += "\\b"
      case "\u{c}": json += "\\f"
      case "\n": json += "\\n"
      case "\r": json += "\\r"
      case "\t": json += "\\t"
      default:
        if c.value < 0x20 { json += "\\u" + String(format: "%04x", c.value) } else { json.unicodeScalars.append(c) }
      }
    }
    json += "\""
    let y = Array(Data(json.utf8).base64EncodedString().utf8)
    var z = 0.0
    for i in 0..<y.count { z += Double(y[i]) * jsPow(128, Double(i)) }
    return z
  }

  /// Math.seed
  func seed(_ x: String) {
    var y = 0.0, z = 0.0
    let m = ShanShui.m, p = ShanShui.p, q = ShanShui.q
    while y.truncatingRemainder(dividingBy: p) == 0 || y.truncatingRemainder(dividingBy: q) == 0 || y == 0 || y == 1 {
      y = (ShanShui.hash(x) + z).truncatingRemainder(dividingBy: m)
      z += 1
    }
    s = y
    for _ in 0..<10 { _ = random() }
  }

  /// Math.random
  func random() -> Double {
    s = (s * s).truncatingRemainder(dividingBy: ShanShui.m)
    return s / ShanShui.m
  }

  // ---- Noise (p5.js)

  private var perlin: [Double]?

  func noise(_ x0: Double, _ y0: Double = 0, _ z0: Double = 0) -> Double {
    var x = x0
    // `y || 0`: what is not a number is 0 too.
    var y = y0.isNaN ? 0 : y0, z = z0.isNaN ? 0 : z0
    if perlin == nil { perlin = (0..<4096).map { _ in random() } }
    let perlin = perlin!
    if x < 0 { x = -x }
    if y < 0 { y = -y }
    if z < 0 { z = -z }
    // Whole numbers, as JavaScript keeps them: doubles until a shift makes them 32 bits.
    var xi = x.rounded(.down), yi = y.rounded(.down), zi = z.rounded(.down)
    var xf = x - xi, yf = y - yi, zf = z - zi
    var r = 0.0, ampl = 0.5
    func scaledCosine(_ i: Double) -> Double { 0.5 * (1.0 - cos(i * Double.pi)) }
    func at(_ i: Double) -> Double { perlin[Int(jsInt32(i) & 4095)] }
    for _ in 0..<4 {
      var of = xi + Double(jsInt32(yi) << 4) + Double(jsInt32(zi) << 8)
      let rxf = scaledCosine(xf), ryf = scaledCosine(yf)
      var n1 = at(of)
      n1 += rxf * (at(of + 1) - n1)
      var n2 = at(of + 16)
      n2 += rxf * (at(of + 16 + 1) - n2)
      n1 += ryf * (n2 - n1)
      of += 256
      n2 = at(of)
      n2 += rxf * (at(of + 1) - n2)
      var n3 = at(of + 16)
      n3 += rxf * (at(of + 16 + 1) - n3)
      n2 += ryf * (n3 - n2)
      n1 += scaledCosine(zf) * (n2 - n1)
      r += n1 * ampl
      ampl *= 0.5
      xi = Double(jsInt32(xi) << 1); xf *= 2
      yi = Double(jsInt32(yi) << 1); yf *= 2
      zi = Double(jsInt32(zi) << 1); zf *= 2
      if xf >= 1.0 { xi += 1; xf -= 1 }
      if yf >= 1.0 { yi += 1; yf -= 1 }
      if zf >= 1.0 { zi += 1; zf -= 1 }
    }
    return r
  }

  // ---- PolyTools

  func midPt(_ plist: [Pt]) -> Pt {
    let n = Double(plist.count)
    var acc = Pt(0, 0)
    for v in plist { acc = Pt(v[0] / n + acc[0], v[1] / n + acc[1]) }
    return acc
  }

  func midPt(_ a: Pt, _ b: Pt) -> Pt { midPt([a, b]) }

  func triangulate(_ plist: [Pt], area: Double = 100, convex: Bool = false, optimize: Bool = true) -> [[Pt]] {
    func lineExpr(_ pt0: Pt, _ pt1: Pt) -> (m: Double, k: Double) {
      let den = pt1[0] - pt0[0]
      let m = den == 0 ? Double.infinity : (pt1[1] - pt0[1]) / den
      return (m, pt0[1] - m * pt0[0])
    }
    func intersect(_ ln0: (Pt, Pt), _ ln1: (Pt, Pt)) -> Bool {
      let le0 = lineExpr(ln0.0, ln0.1), le1 = lineExpr(ln1.0, ln1.1)
      let den = le0.m - le1.m
      if den == 0 { return false }
      let x = (le1.k - le0.k) / den
      let y = le0.m * x + le0.k
      func onSeg(_ ln: (Pt, Pt)) -> Bool {
        jsMin(ln.0[0], ln.1[0]) <= x && x <= jsMax(ln.0[0], ln.1[0]) && jsMin(ln.0[1], ln.1[1]) <= y && y <= jsMax(ln.0[1], ln.1[1])
      }
      return onSeg(ln0) && onSeg(ln1)
    }
    func next(_ plist: [Pt], _ i: Int) -> Pt { plist[i != plist.count - 1 ? i + 1 : 0] }
    func ptInPoly(_ pt: Pt, _ plist: [Pt]) -> Bool {
      var scount = 0
      for i in 0..<plist.count where intersect((plist[i], next(plist, i)), (pt, Pt(pt[0] + 999, pt[1] + 999))) { scount += 1 }
      return scount % 2 == 1
    }
    func lnInPoly(_ ln: (Pt, Pt), _ plist: [Pt]) -> Bool {
      let ep = 0.01
      let lnc = (Pt(ln.0[0] * (1 - ep) + ln.1[0] * ep, ln.0[1] * (1 - ep) + ln.1[1] * ep),
                 Pt(ln.0[0] * ep + ln.1[0] * (1 - ep), ln.0[1] * ep + ln.1[1] * (1 - ep)))
      for i in 0..<plist.count where intersect(lnc, (plist[i], next(plist, i))) { return false }
      return ptInPoly(midPt(ln.0, ln.1), plist)
    }
    func sidesOf(_ plist: [Pt]) -> [Double] {
      (0..<plist.count).map { i in
        let pt = plist[i], np = next(plist, i)
        return (jsPow(np[0] - pt[0], 2) + jsPow(np[1] - pt[1], 2)).squareRoot()
      }
    }
    func areaOf(_ plist: [Pt]) -> Double {
      let slist = sidesOf(plist)
      let a = slist[js: 0], b = slist[js: 1], c = slist[js: 2]
      let s = (a + b + c) / 2
      return (s * (s - a) * (s - b) * (s - c)).squareRoot()
    }
    func sliverRatio(_ plist: [Pt]) -> Double {
      let A = areaOf(plist)
      var P = 0.0
      for n in sidesOf(plist) { P = P + n }
      return A / P
    }
    func bestEar(_ plist: [Pt]) -> ([Pt], [Pt]) {
      var cuts: [([Pt], [Pt])] = []
      for i in 0..<plist.count {
        let pt = plist[i], lp = plist[i != 0 ? i - 1 : plist.count - 1], np = next(plist, i)
        var qlist = plist
        qlist.remove(at: i)
        if convex || lnInPoly((lp, np), plist) {
          let c = ([lp, pt, np], qlist)
          if !optimize { return c }
          cuts.append(c)
        }
      }
      var best: ([Pt], [Pt]) = (plist, [])
      var bestRatio = 0.0
      for cut in cuts {
        let r = sliverRatio(cut.0)
        if r >= bestRatio { best = cut; bestRatio = r }
      }
      return best
    }
    func shatter(_ plist: [Pt], _ a: Double) -> [[Pt]] {
      if plist.isEmpty { return [] }
      if areaOf(plist) < a { return [plist] }
      let slist = sidesOf(plist)
      var ind = 0
      for i in 0..<slist.count where slist[i] > slist[ind] { ind = i }
      let nind = (ind + 1) % plist.count, lind = (ind + 2) % plist.count
      let mid = midPt(plist[ind], plist[nind])
      return shatter([plist[ind], mid, plist[lind]], a) + shatter([plist[lind], plist[nind], mid], a)
    }
    if plist.count <= 3 { return shatter(plist, area) }
    let cut = bestEar(plist)
    return shatter(cut.0, area) + triangulate(cut.1, area: area, convex: convex, optimize: optimize)
  }

  // ---- numbers

  func distance(_ p0: Pt, _ p1: Pt) -> Double { (jsPow(p0[0] - p1[0], 2) + jsPow(p0[1] - p1[1], 2)).squareRoot() }

  func mapval(_ value: Double, _ istart: Double, _ istop: Double, _ ostart: Double, _ ostop: Double) -> Double {
    ostart + (ostop - ostart) * (((value - istart) * 1.0) / (istop - istart))
  }

  func loopNoise(_ nslist: inout [Double]) {
    let n = nslist.count
    let dif = nslist[js: n - 1] - nslist[js: 0]
    var bds = (100.0, -100.0)
    for i in 0..<n {
      nslist[i] += (dif * Double(n - 1 - i)) / Double(n - 1)
      if nslist[i] < bds.0 { bds.0 = nslist[i] }
      if nslist[i] > bds.1 { bds.1 = nslist[i] }
    }
    for i in 0..<n { nslist[i] = mapval(nslist[i], bds.0, bds.1, 0, 1) }
  }

  func randChoice<T>(_ arr: [T]) -> T { arr[Int((Double(arr.count) * random()).rounded(.down))] }

  func normRand(_ m: Double, _ M: Double) -> Double { mapval(random(), 0, 1, m, M) }

  func wtrand(_ f: (Double) -> Double) -> Double {
    while true {
      let x = random(), y = random()
      if y < f(x) { return x }
    }
  }

  func randGaussian() -> Double { wtrand { jsPow(M_E, -24 * jsPow($0 - 0.5, 2)) } * 2 - 1 }

  func bezmh(_ P0: [Pt], _ w: Double = 1) -> [Pt] {
    var P = P0
    if P.count == 2 { P = [P[0], midPt(P[0], P[1]), P[1]] }
    var plist: [Pt] = []
    for j in 0..<max(0, P.count - 2) {
      let p0 = j == 0 ? P[j] : midPt(P[j], P[j + 1])
      let p1 = P[j + 1]
      let p2 = j == P.count - 3 ? P[j + 2] : midPt(P[j + 1], P[j + 2])
      let pl = 20
      for i in 0..<(pl + (j == P.count - 3 ? 1 : 0)) {
        let t = Double(i) / Double(pl)
        let u = jsPow(1 - t, 2) + 2 * t * (1 - t) * w + t * t
        plist.append(Pt((jsPow(1 - t, 2) * p0[0] + 2 * t * (1 - t) * p1[0] * w + t * t * p2[0]) / u,
                        (jsPow(1 - t, 2) * p0[1] + 2 * t * (1 - t) * p1[1] * w + t * t * p2[1]) / u))
      }
    }
    return plist
  }

  // ---- the brush

  func poly(_ plist: [Pt], xof: Double = 0, yof: Double = 0, fil: String = "rgba(0,0,0,0)", str: String? = nil, wid: Double = 0) -> String {
    var canv = Array("<polyline points='".utf8)
    canv.reserveCapacity(64 + plist.count * 14)
    for p in plist {
      canv.append(32)
      jsFixed(p[0] + xof, 1, into: &canv)
      canv.append(44)
      jsFixed(p[1] + yof, 1, into: &canv)
    }
    canv.append(contentsOf: ("' style='fill:" + fil + ";stroke:" + (str ?? fil) + ";stroke-width:" + jsString(wid) + "'/>").utf8)
    return String(decoding: canv, as: UTF8.self)
  }

  func stroke(_ ptlist: [Pt], xof: Double = 0, yof: Double = 0, wid: Double = 2, col: String = "rgba(200,200,200,0.9)",
              noi: Double = 0.5, out: Double = 1, fun: ((Double) -> Double)? = nil) -> String {
    let fun = fun ?? { sin($0 * Double.pi) }
    if ptlist.isEmpty { return "" }
    var vtxlist0: [Pt] = [], vtxlist1: [Pt] = []
    let n0 = random() * 10
    let n = ptlist.count
    if n > 2 {
      for i in 1..<(n - 1) {
        var w = wid * fun(Double(i) / Double(n))
        w = w * (1 - noi) + w * noi * noise(Double(i) * 0.5, n0)
        let a1 = atan2(ptlist[i][1] - ptlist[i - 1][1], ptlist[i][0] - ptlist[i - 1][0])
        let a2 = atan2(ptlist[i][1] - ptlist[i + 1][1], ptlist[i][0] - ptlist[i + 1][0])
        var a = (a1 + a2) / 2
        if a < a2 { a += Double.pi }
        vtxlist0.append(Pt(ptlist[i][0] + w * cos(a), ptlist[i][1] + w * sin(a)))
        vtxlist1.append(Pt(ptlist[i][0] - w * cos(a), ptlist[i][1] - w * sin(a)))
      }
    }
    let vtxlist = [ptlist[0]] + vtxlist0 + (vtxlist1 + [ptlist[n - 1]]).reversed() + [ptlist[0]]
    return poly(vtxlist.map { Pt($0[0] + xof, $0[1] + yof) }, fil: col, str: col, wid: out)
  }

  /// blob with `ret` 1: its outline.
  func blobPoints(_ x: Double, _ y: Double, len: Double = 20, wid: Double = 5, ang: Double = 0, noi: Double = 0.5,
                  fun: ((Double) -> Double)? = nil) -> [Pt] {
    let fun = fun ?? { $0 <= 1 ? jsPow(sin($0 * Double.pi), 0.5) : -jsPow(sin(($0 + 1) * Double.pi), 0.5) }
    let reso = 20.0
    var lalist: [(l: Double, a: Double)] = []
    for i in 0..<21 {
      let p = (Double(i) / reso) * 2
      let xo = len / 2 - abs(p - 1) * len
      let yo = (fun(p) * wid) / 2
      lalist.append(((xo * xo + yo * yo).squareRoot(), atan2(yo, xo)))
    }
    var nslist: [Double] = []
    let n0 = random() * 10
    for i in 0..<21 { nslist.append(noise(Double(i) * 0.05, n0)) }
    loopNoise(&nslist)
    var plist: [Pt] = []
    for i in 0..<lalist.count {
      let ns = nslist[i] * noi + (1 - noi)
      plist.append(Pt(x + cos(lalist[i].a + ang) * lalist[i].l * ns, y + sin(lalist[i].a + ang) * lalist[i].l * ns))
    }
    return plist
  }

  func blob(_ x: Double, _ y: Double, len: Double = 20, wid: Double = 5, ang: Double = 0, col: String = "rgba(200,200,200,0.9)",
            noi: Double = 0.5, fun: ((Double) -> Double)? = nil) -> String {
    poly(blobPoints(x, y, len: len, wid: wid, ang: ang, noi: noi, fun: fun), fil: col, str: col, wid: 0)
  }

  func div(_ plist: [Pt], _ reso: Double) -> [Pt] {
    let tl = Double(plist.count - 1) * reso
    var rlist: [Pt] = []
    var i = 0.0
    while i < tl {
      let lastp = plist[Int((i / reso).rounded(.down))], nextp = plist[Int((i / reso).rounded(.up))]
      let p = i.truncatingRemainder(dividingBy: reso) / reso
      rlist.append(Pt(lastp[0] * (1 - p) + nextp[0] * p, lastp[1] * (1 - p) + nextp[1] * p))
      i += 1
    }
    if !plist.isEmpty { rlist.append(plist[plist.count - 1]) }
    return rlist
  }

  /// texture: both what it draws (`ret` 0) and its lines (`ret` 1). The
  /// original draws either way, so the random numbers go the same.
  func texture(_ ptlist: [[Pt]], xof: Double = 0, yof: Double = 0, tex: Double = 400, wid: Double = 1.5, len: Double = 0.2,
               sha: Double = 0, noi: ((Double) -> Double)? = nil, col: ((Double) -> String)? = nil,
               dis: (() -> Double)? = nil) -> (canv: String, list: [[Pt]]) {
    let noi = noi ?? { 30 / $0 }
    let col = col ?? { [unowned self] _ in "rgba(100,100,100," + jsFixed(self.random() * 0.3, 3) + ")" }
    let dis = dis ?? { [unowned self] in
      if self.random() > 0.5 { return (1.0 / 3) * self.random() }
      return (1.0 * 2) / 3 + (1.0 / 3) * self.random()
    }
    let reso = (Double(ptlist.count), Double(ptlist[0].count))
    var texlist: [[Pt]] = []
    var i = 0.0
    while i < tex {
      let mid = Double(jsInt32(dis() * reso.1))
      let hlen = (random() * (reso.1 * len)).rounded(.down)
      let start = Int(min(max(mid - hlen, 0), reso.1)), end = Int(min(max(mid + hlen, 0), reso.1))
      let layer = (i / tex) * (reso.0 - 1)
      var line: [Pt] = []
      let lo = ptlist[Int(layer.rounded(.down))], hi = ptlist[Int(layer.rounded(.up))]
      let p = layer - layer.rounded(.down)
      for j in start..<max(start, end) {
        let x = lo[j][0] * p + hi[j][0] * (1 - p)
        let y = lo[j][1] * p + hi[j][1] * (1 - p)
        let nx = noi(layer + 1) * (noise(x, Double(j) * 0.5) - 0.5)
        let ny = noi(layer + 1) * (noise(y, Double(j) * 0.5) - 0.5)
        line.append(Pt(x + nx, y + ny))
      }
      texlist.append(line)
      i += 1
    }
    var canv = ""
    let step = Int(sha)
    if sha != 0 {
      var j = 0
      while j < texlist.count {
        canv += stroke(texlist[j].map { Pt($0[0] + xof, $0[1] + yof) }, wid: sha, col: "rgba(100,100,100,0.1)")
        j += 2
      }
    }
    var j = step
    while j < texlist.count {
      let pts = texlist[j].map { Pt($0[0] + xof, $0[1] + yof) }
      canv += stroke(pts, wid: wid, col: col(Double(j) / Double(texlist.count)))
      j += 1 + step
    }
    return (canv, texlist)
  }
}

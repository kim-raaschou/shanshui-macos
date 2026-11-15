import Foundation

// The original's Tree: the eight kinds of tree (tree01 ... tree08) and what
// they are made of, the branch, the twig and the bark (barkify). Each is the
// JavaScript line for line, with the same random numbers in the same order;
// where JavaScript shares a point between two lists and changes it in one
// (div keeps the last point of a list, and barkify moves it), the change is
// written back here, since a Pt is a value.

/// The leaf colour of tree01, tree02, tree03 and tree07: the parts of an
/// "rgba(...)" colour (its first "rgba(" and first ")" taken away, split at
/// the commas), or `otherwise`.
private func leafcolOf(_ col: String, _ otherwise: [String]) -> [String] {
  guard col.contains("rgba(") else { return otherwise }
  var s = col
  if let r = s.range(of: "rgba(") { s.replaceSubrange(r, with: "") }
  if let r = s.range(of: ")") { s.replaceSubrange(r, with: "") }
  return s.components(separatedBy: ",")
}

/// A part of the leaf colour as JavaScript joins it into text.
private func leafPart(_ leafcol: [String], _ i: Int) -> String { i < leafcol.count ? leafcol[i] : "undefined" }

/// parseFloat of a part of the leaf colour: the longest number at its start.
private func parseFloat(_ leafcol: [String], _ i: Int) -> Double {
  guard i < leafcol.count else { return .nan }
  let s = Array(leafcol[i].unicodeScalars.drop { CharacterSet.whitespacesAndNewlines.contains($0) })
  var k = 0
  func digits() -> Int {
    let k0 = k
    while k < s.count, s[k] >= "0", s[k] <= "9" { k += 1 }
    return k - k0
  }
  if k < s.count, s[k] == "+" || s[k] == "-" { k += 1 }
  let rest = String(String.UnicodeScalarView(s[k...]))
  if rest.hasPrefix("Infinity") { return s.first == "-" ? -.infinity : .infinity }
  var n = digits()
  var end = k
  if k < s.count, s[k] == "." {
    k += 1
    n += digits()
    if n > 0 { end = k }
  } else if n > 0 { end = k }
  if n == 0 { return .nan }
  if k < s.count, s[k] == "e" || s[k] == "E" {
    var e = k + 1
    if e < s.count, s[e] == "+" || s[e] == "-" { e += 1 }
    k = e
    if digits() > 0 { end = k }
  }
  var text = String(String.UnicodeScalarView(s[0..<end]))
  if text.hasSuffix(".") { text.removeLast() }
  return Double(text) ?? .nan
}

extension ShanShui {
  func tree01(_ x: Double, _ y: Double, hei: Double = 50, wid: Double = 3, col: String = "rgba(100,100,100,0.5)",
              noi: Double = 0.5) -> String {
    let reso = 10.0
    var nslist: [(Double, Double)] = []
    for i in 0..<10 { nslist.append((noise(Double(i) * 0.5), noise(Double(i) * 0.5, 0.5))) }

    let leafcol = leafcolOf(col, ["100", "100", "100", "0.5"])
    var canv = ""
    var line1: [Pt] = []
    var line2: [Pt] = []
    for i in 0..<10 {
      let nx = x
      let ny = y - (Double(i) * hei) / reso
      if Double(i) >= reso / 4 {
        var j = 0.0
        while j < (reso - Double(i)) / 5 {
          canv += blob(nx + (random() - 0.5) * wid * 1.2 * (reso - Double(i)), ny + (random() - 0.5) * wid,
                       len: random() * 20 * (reso - Double(i)) * 0.2 + 10, wid: random() * 6 + 3, ang: ((random() - 0.5) * Double.pi) / 6,
                       col: "rgba(" + leafPart(leafcol, 0) + "," + leafPart(leafcol, 1) + "," + leafPart(leafcol, 2) + ","
                         + jsFixed(random() * 0.2 + parseFloat(leafcol, 3), 1) + ")")
          j += 1
        }
      }
      line1.append(Pt(nx + (nslist[i].0 - 0.5) * wid - wid / 2, ny))
      line2.append(Pt(nx + (nslist[i].1 - 0.5) * wid + wid / 2, ny))
    }
    canv += poly(line1, fil: "none", str: col, wid: 1.5) + poly(line2, fil: "none", str: col, wid: 1.5)
    return canv
  }

  func tree02(_ x: Double, _ y: Double, hei: Double = 16, wid: Double = 8, clu: Double = 5, col: String = "rgba(100,100,100,0.5)",
              noi: Double = 0.5) -> String {
    // The original works out the leaf colour here and never uses it.
    var canv = ""
    var i = 0.0
    while i < clu {
      // The blob's width is drawn before its length, as the original lists them.
      let bx = x + randGaussian() * clu * 4
      let by = y + randGaussian() * clu * 4
      let bwid = random() * wid * 0.75 + wid * 0.5
      let blen = random() * hei * 0.75 + hei * 0.5
      canv += blob(bx, by, len: blen, wid: bwid, ang: Double.pi / 2, col: col, fun: {
        $0 <= 1 ? jsPow(sin($0 * Double.pi) * $0, 0.5) : -jsPow(sin(($0 - 2) * Double.pi * ($0 - 2)), 0.5)
      })
      i += 1
    }
    return canv
  }

  func tree03(_ x: Double, _ y: Double, hei: Double = 50, wid: Double = 5, ben: (Double) -> Double = { _ in 0 },
              col: String = "rgba(100,100,100,0.5)", noi: Double = 0.5) -> String {
    let reso = 10.0
    var nslist: [(Double, Double)] = []
    for i in 0..<10 { nslist.append((noise(Double(i) * 0.5), noise(Double(i) * 0.5, 0.5))) }

    let leafcol = leafcolOf(col, ["100", "100", "100", "0.5"])
    var canv = ""
    var blobs = ""
    var line1: [Pt] = []
    var line2: [Pt] = []
    for i in 0..<10 {
      let nx = x + ben(Double(i) / reso) * 100
      let ny = y - (Double(i) * hei) / reso
      if Double(i) >= reso / 5 {
        var j = 0.0
        while j < (reso - Double(i)) * 2 {
          let shape = { (x: Double) in log(50 * x + 1) / 3.95 }
          let ox = random() * wid * 2 * shape((reso - Double(i)) / reso)
          blobs += blob(nx + ox * randChoice([-1.0, 1]), ny + (random() - 0.5) * wid * 2,
                        len: ox * 2, wid: random() * 6 + 3, ang: ((random() - 0.5) * Double.pi) / 6,
                        col: "rgba(" + leafPart(leafcol, 0) + "," + leafPart(leafcol, 1) + "," + leafPart(leafcol, 2) + ","
                          + jsFixed(random() * 0.2 + parseFloat(leafcol, 3), 3) + ")")
          j += 1
        }
      }
      line1.append(Pt(nx + (((nslist[i].0 - 0.5) * wid - wid / 2) * (reso - Double(i))) / reso, ny))
      line2.append(Pt(nx + (((nslist[i].1 - 0.5) * wid + wid / 2) * (reso - Double(i))) / reso, ny))
    }
    let lc = line1 + line2.reversed()
    canv += poly(lc, fil: "white", str: col, wid: 1.5)
    canv += blobs
    return canv
  }

  private func branch(hei: Double = 300, wid: Double = 6, ang: Double = 0, det: Double = 10, ben: Double = Double.pi * 0.2) -> ([Pt], [Pt]) {
    var ang = ang
    var tlist: [Pt]
    var nx = 0.0
    var ny = 0.0
    tlist = [Pt(nx, ny)]
    var a0 = 0.0
    let g = 3.0
    for _ in 0..<3 {
      a0 += (ben / 2 + (random() * ben) / 2) * randChoice([-1.0, 1])
      nx += (cos(a0) * hei) / g
      ny -= (sin(a0) * hei) / g
      tlist.append(Pt(nx, ny))
    }
    let ta = atan2(tlist[tlist.count - 1][1], tlist[tlist.count - 1][0])

    for i in 0..<tlist.count {
      let a = atan2(tlist[i][1], tlist[i][0])
      let d = (tlist[i][0] * tlist[i][0] + tlist[i][1] * tlist[i][1]).squareRoot()
      tlist[i][0] = d * cos(a - ta + ang)
      tlist[i][1] = d * sin(a - ta + ang)
    }

    var trlist1: [Pt] = []
    var trlist2: [Pt] = []
    let span = det
    let tl = Double(tlist.count - 1) * span
    var lx = 0.0
    var ly = 0.0

    var i = 0.0
    while i < tl {
      let lastp = tlist[Int((i / span).rounded(.down))]
      let nextp = tlist[Int((i / span).rounded(.up))]
      let p = i.truncatingRemainder(dividingBy: span) / span
      nx = lastp[0] * (1 - p) + nextp[0] * p
      ny = lastp[1] * (1 - p) + nextp[1] * p

      ang = atan2(ny - ly, nx - lx)
      let woff = ((noise(i * 0.3) - 0.5) * wid * hei) / 80

      var b = 0.0
      if p == 0 {
        b = random() * wid
      }

      let nw = wid * (((tl - i) / tl) * 0.5 + 0.5)
      trlist1.append(Pt(nx + cos(ang + Double.pi / 2) * (nw + woff + b), ny + sin(ang + Double.pi / 2) * (nw + woff + b)))
      trlist2.append(Pt(nx + cos(ang - Double.pi / 2) * (nw - woff + b), ny + sin(ang - Double.pi / 2) * (nw - woff + b)))
      lx = nx
      ly = ny
      i += 1
    }

    return (trlist1, trlist2)
  }

  private func twig(_ tx: Double, _ ty: Double, _ dep: Double, dir: Double = 1, sca: Double = 1, wid: Double = 1, ang: Double = 0,
                    lea: (Bool, Double) = (true, 12)) -> String {
    var canv = ""
    var twlist: [Pt] = []
    let tl = 10.0
    let hs = random() * 0.5 + 0.5
    // fun1 (Math.pow(x, 0.5)) is never chosen. fun2 reads the loop's i, not its argument.
    var i = 0.0
    let fun2 = { (_: Double) -> Double in -1 / jsPow(i / tl + 1, 5) + 1 }

    let tfun = randChoice([fun2])
    let a0 = ((random() * Double.pi) / 6) * dir + ang
    while i < tl {
      let mx = dir * tfun(i / tl) * 50 * sca * hs
      let my = -i * 5 * sca

      let a = atan2(my, mx)
      let d = jsPow(mx * mx + my * my, 0.5)

      let nx = cos(a + a0) * d
      let ny = sin(a + a0) * d

      twlist.append(Pt(nx + tx, ny + ty))
      if (i == Double(jsInt32(tl / 3)) || i == Double(jsInt32((tl * 2) / 3))) && dep > 0 {
        canv += twig(nx + tx, ny + ty, dep - 1, dir: dir * randChoice([-1.0, 1]), sca: sca * 0.8, wid: wid, ang: ang, lea: lea)
      }
      if i == tl - 1 && lea.0 == true {
        for j in 0..<5 {
          let dj = (Double(j) - 2.5) * 5
          // The leaf's width is drawn before its length, as the original lists them.
          let bwid = (6 + 3 * random()) * wid
          let blen = (15 + 12 * random()) * wid
          canv += blob(nx + tx + cos(ang) * dj * wid, ny + ty + (sin(ang) * dj - lea.1 / (dep + 1)) * wid,
                       len: blen, wid: bwid, ang: ang / 2 + Double.pi / 2 + Double.pi * 0.2 * (random() - 0.5),
                       col: "rgba(100,100,100," + jsFixed(0.5 + dep * 0.2, 3) + ")", fun: {
                         $0 <= 1 ? jsPow(sin($0 * Double.pi) * $0, 0.5) : -jsPow(sin(($0 - 2) * Double.pi * ($0 - 2)), 0.5)
                       })
        }
      }
      i += 1
    }
    canv += stroke(twlist, wid: 1, col: "rgba(100,100,100,0.5)", fun: { cos(($0 * Double.pi) / 2) })
    return canv
  }

  /// barkify. As in the original, the last point of each ridge is the trunk's
  /// own point, so moving it moves the trunk's: it is written back to `trlist`.
  private func barkify(_ x: Double, _ y: Double, _ trlist: inout ([Pt], [Pt])) -> String {
    func bark(_ x: Double, _ y: Double, _ wid: Double, _ ang: Double) -> String {
      let len = 10 + 10 * random()
      let noi = 0.5
      let fun = { (x: Double) -> Double in x <= 1 ? jsPow(sin(x * Double.pi), 0.5) : -jsPow(sin((x + 1) * Double.pi), 0.5) }
      let reso = 20.0
      var canv = ""

      var lalist: [(Double, Double)] = []
      var i = 0.0
      while i < reso + 1 {
        let p = (i / reso) * 2
        let xo = len / 2 - abs(p - 1) * len
        let yo = (fun(p) * wid) / 2
        let a = atan2(yo, xo)
        let l = (xo * xo + yo * yo).squareRoot()
        lalist.append((l, a))
        i += 1
      }
      var nslist: [Double] = []
      let n0 = random() * 10
      i = 0
      while i < reso + 1 {
        nslist.append(noise(i * 0.05, n0))
        i += 1
      }

      loopNoise(&nslist)
      var brklist: [Pt] = []
      for i in 0..<lalist.count {
        let ns = nslist[i] * noi + (1 - noi)
        let nx = x + cos(lalist[i].1 + ang) * lalist[i].0 * ns
        let ny = y + sin(lalist[i].1 + ang) * lalist[i].0 * ns
        brklist.append(Pt(nx, ny))
      }
      let fr = random()
      canv += stroke(brklist, wid: 0.8, col: "rgba(100,100,100,0.4)", noi: 0, out: 0, fun: { sin(($0 + fr) * Double.pi * 3) })

      return canv
    }
    var canv = ""

    var i = 2
    while i < trlist.0.count - 1 {
      let a0 = atan2(trlist.0[i][1] - trlist.0[i - 1][1], trlist.0[i][0] - trlist.0[i - 1][0])
      let a1 = atan2(trlist.1[i][1] - trlist.1[i - 1][1], trlist.1[i][0] - trlist.1[i - 1][0])
      let p = random()
      let nx = trlist.0[i][0] * (1 - p) + trlist.1[i][0] * p
      let ny = trlist.0[i][1] * (1 - p) + trlist.1[i][1] * p
      if random() < 0.2 {
        canv += blob(nx + x, ny + y, len: 15, wid: 6 - abs(p - 0.5) * 10, ang: (a0 + a1) / 2, col: "rgba(100,100,100,0.6)", noi: 1)
      } else {
        canv += bark(nx + x, ny + y, 5 - abs(p - 0.5) * 10, (a0 + a1) / 2)
      }

      if random() < 0.05 {
        let jl = random() * 2 + 2
        let xya = randChoice([(trlist.0[i][0], trlist.0[i][1], a0), (trlist.1[i][0], trlist.1[i][1], a1)])
        var j = 0.0
        while j < jl {
          canv += blob(xya.0 + x + cos(xya.2) * (j - jl / 2) * 4, xya.1 + y + sin(xya.2) * (j - jl / 2) * 4,
                       len: 4 + 6 * random(), wid: 4, ang: a0 + Double.pi / 2, col: "rgba(100,100,100,0.6)")
          j += 1
        }
      }
      i += 1
    }
    let trflist = trlist.0 + trlist.1.reversed()
    var rglist: [[Pt]] = [[]]
    // Where each point of rglist is in trflist: not in the original, which shares the points.
    var rgfrom: [[Int]] = [[]]
    for i in 0..<trflist.count {
      if random() < 0.5 {
        rglist.append([])
        rgfrom.append([])
      } else {
        rglist[rglist.count - 1].append(trflist[i])
        rgfrom[rgfrom.count - 1].append(i)
      }
    }

    for i in 0..<rglist.count {
      rglist[i] = div(rglist[i], 4)
      for j in 0..<rglist[i].count {
        rglist[i][j][0] += (noise(Double(i), Double(j) * 0.1, 1) - 0.5) * (15 + 5 * randGaussian())
        rglist[i][j][1] += (noise(Double(i), Double(j) * 0.1, 2) - 0.5) * (15 + 5 * randGaussian())
      }
      // div's last point is the one it was given: the trunk's point moves with it.
      if let k = rgfrom[i].last {
        let v = rglist[i][rglist[i].count - 1]
        if k < trlist.0.count { trlist.0[k] = v } else { trlist.1[trlist.1.count - 1 - (k - trlist.0.count)] = v }
      }
      canv += stroke(rglist[i].map { Pt($0[0] + x, $0[1] + y) }, wid: 1.5, col: "rgba(100,100,100,0.7)", out: 0)
    }
    return canv
  }

  func tree04(_ x: Double, _ y: Double, hei: Double = 300, wid: Double = 6, col: String = "rgba(100,100,100,0.5)", noi: Double = 0.5) -> String {
    var canv = ""
    var txcanv = ""
    var twcanv = ""

    // trlist as the original has it before it is joined into one list.
    var trpair = branch(hei: hei, wid: wid, ang: -Double.pi / 2)
    txcanv += barkify(x, y, &trpair)
    let trlist = trpair.0 + trpair.1.reversed()

    var trmlist: [Pt] = []

    let n = Double(trlist.count)
    for i in 0..<trlist.count {
      if (Double(i) >= n * 0.3 && Double(i) <= n * 0.7 && random() < 0.1) || Double(i) == n / 2 - 1 {
        let ba = Double.pi * 0.2 - Double.pi * 1.4 * (Double(i) > n / 2 ? 1 : 0)
        var brlist = branch(hei: hei * (random() + 1) * 0.3, wid: wid * 0.5, ang: ba)

        if !brlist.0.isEmpty { brlist.0.removeFirst() }
        if !brlist.1.isEmpty { brlist.1.removeFirst() }
        let foff = { (v: Pt) in Pt(v[0] + trlist[i][0], v[1] + trlist[i][1]) }
        var brf = (brlist.0.map(foff), brlist.1.map(foff))
        txcanv += barkify(x, y, &brf)

        for j in 0..<brlist.0.count {
          if random() < 0.2 || j == brlist.0.count - 1 {
            twcanv += twig(brlist.0[j][0] + trlist[i][0] + x, brlist.0[j][1] + trlist[i][1] + y, 1,
                           dir: ba > -Double.pi / 2 ? 1 : -1, sca: (0.5 * hei) / 300, wid: hei / 300,
                           ang: ba > -Double.pi / 2 ? ba : ba + Double.pi)
          }
        }
        trmlist += (brlist.0 + brlist.1.reversed()).map { Pt($0[0] + trlist[i][0], $0[1] + trlist[i][1]) }
      } else {
        trmlist.append(trlist[i])
      }
    }
    canv += poly(trmlist, xof: x, yof: y, fil: "white", str: col, wid: 0)

    if !trmlist.isEmpty { trmlist.removeFirst() }
    if !trmlist.isEmpty { trmlist.removeLast() }
    canv += stroke(trmlist.map { Pt($0[0] + x, $0[1] + y) }, wid: 2.5, col: "rgba(100,100,100," + jsFixed(0.4 + random() * 0.1, 3) + ")",
                   noi: 0.9, out: 0, fun: { _ in sin(1) })

    canv += txcanv
    canv += twcanv
    return canv
  }

  func tree05(_ x: Double, _ y: Double, hei: Double = 300, wid: Double = 5, col: String = "rgba(100,100,100,0.5)", noi: Double = 0.5) -> String {
    var canv = ""
    var txcanv = ""
    var twcanv = ""

    // trlist as the original has it before it is joined into one list.
    var trpair = branch(hei: hei, wid: wid, ang: -Double.pi / 2, ben: 0)
    txcanv += barkify(x, y, &trpair)
    let trlist = trpair.0 + trpair.1.reversed()

    var trmlist: [Pt] = []

    let n = Double(trlist.count)
    for i in 0..<trlist.count {
      let p = abs(Double(i) - n * 0.5) / (n * 0.5)
      if (Double(i) >= n * 0.2 && Double(i) <= n * 0.8 && i % 3 == 0 && random() > p) || Double(i) == n / 2 - 1 {
        let bar = random() * 0.2
        let ba = -bar * Double.pi - (1 - bar * 2) * Double.pi * (Double(i) > n / 2 ? 1 : 0)
        var brlist = branch(hei: hei * (0.3 * p - random() * 0.05), wid: wid * 0.5, ang: ba, ben: 0.5)

        if !brlist.0.isEmpty { brlist.0.removeFirst() }
        if !brlist.1.isEmpty { brlist.1.removeFirst() }
        //txcanv += barkify(x,y,[brlist[0].map(foff),brlist[1].map(foff)])

        for j in 0..<brlist.0.count {
          if j % 20 == 0 || j == brlist.0.count - 1 {
            twcanv += twig(brlist.0[j][0] + trlist[i][0] + x, brlist.0[j][1] + trlist[i][1] + y, 0,
                           dir: ba > -Double.pi / 2 ? 1 : -1, sca: (0.2 * hei) / 300, wid: hei / 300,
                           ang: ba > -Double.pi / 2 ? ba : ba + Double.pi, lea: (true, 5))
          }
        }
        trmlist += (brlist.0 + brlist.1.reversed()).map { Pt($0[0] + trlist[i][0], $0[1] + trlist[i][1]) }
      } else {
        trmlist.append(trlist[i])
      }
    }

    canv += poly(trmlist, xof: x, yof: y, fil: "white", str: col, wid: 0)

    if !trmlist.isEmpty { trmlist.removeFirst() }
    if !trmlist.isEmpty { trmlist.removeLast() }
    canv += stroke(trmlist.map { Pt($0[0] + x, $0[1] + y) }, wid: 2.5, col: "rgba(100,100,100," + jsFixed(0.4 + random() * 0.1, 3) + ")",
                   noi: 0.9, out: 0, fun: { _ in sin(1) })

    canv += txcanv
    canv += twcanv
    return canv
  }

  func tree06(_ x: Double, _ y: Double, hei: Double = 100, wid: Double = 6, col: String = "rgba(100,100,100,0.5)", noi: Double = 0.5) -> String {
    var canv = ""
    var txcanv = ""
    var twcanv = ""

    func fracTree(_ xoff: Double, _ yoff: Double, _ dep: Double, hei: Double, wid: Double, ang: Double, ben: Double) -> [Pt] {
      // trlist as the original has it before it is joined into one list.
      var trpair = branch(hei: hei, wid: wid, ang: ang, det: hei / 20, ben: ben)
      txcanv += barkify(xoff, yoff, &trpair)
      let trlist = trpair.0 + trpair.1.reversed()

      var trmlist: [Pt] = []

      let n = Double(trlist.count)
      for i in 0..<trlist.count {
        // The original works out p = |i - n/2| / (n/2) here and never uses it.
        if ((random() < 0.025 && Double(i) >= n * 0.2 && Double(i) <= n * 0.8) || Double(i) == Double(jsInt32(n / 2)) - 1
          || Double(i) == Double(jsInt32(n / 2)) + 1) && dep > 0 {
          let bar = 0.02 + random() * 0.08
          let ba = bar * Double.pi - bar * 2 * Double.pi * (Double(i) > n / 2 ? 1 : 0)

          let brlist = fracTree(trlist[i][0] + xoff, trlist[i][1] + yoff, dep - 1,
                                hei: hei * (0.7 + random() * 0.2), wid: wid * 0.6, ang: ang + ba, ben: 0.55)

          for j in 0..<brlist.count {
            if random() < 0.03 {
              twcanv += twig(brlist[j][0] + trlist[i][0] + xoff, brlist[j][1] + trlist[i][1] + yoff, 2,
                             dir: ba > 0 ? 1 : -1, sca: 0.3, ang: ba * (random() * 0.5 + 0.75), lea: (false, 0))
            }
          }

          trmlist += brlist.map { Pt($0[0] + trlist[i][0], $0[1] + trlist[i][1]) }
        } else {
          trmlist.append(trlist[i])
        }
      }
      return trmlist
    }

    var trmlist = fracTree(x, y, 3, hei: hei, wid: wid, ang: -Double.pi / 2, ben: 0)

    canv += poly(trmlist, xof: x, yof: y, fil: "white", str: col, wid: 0)

    if !trmlist.isEmpty { trmlist.removeFirst() }
    if !trmlist.isEmpty { trmlist.removeLast() }
    canv += stroke(trmlist.map { Pt($0[0] + x, $0[1] + y) }, wid: 2.5, col: "rgba(100,100,100," + jsFixed(0.4 + random() * 0.1, 3) + ")",
                   noi: 0.9, out: 0, fun: { _ in sin(1) })

    canv += txcanv
    canv += twcanv
    return canv
  }

  func tree07(_ x: Double, _ y: Double, hei: Double = 60, wid: Double = 4, ben: (Double) -> Double = { $0.squareRoot() * 0.2 },
              col: String = "rgba(100,100,100,1)", noi: Double = 0.5) -> String {
    let reso = 10.0
    var nslist: [(Double, Double)] = []
    for i in 0..<10 { nslist.append((noise(Double(i) * 0.5), noise(Double(i) * 0.5, 0.5))) }
    // The original works out the leaf colour here for a blob that gives back its outline, which has no colour.
    var canv = ""
    var line1: [Pt] = []
    var line2: [Pt] = []
    var T: [[Pt]] = []
    for i in 0..<10 {
      let nx = x + ben(Double(i) / reso) * 100
      let ny = y - (Double(i) * hei) / reso
      if Double(i) >= reso / 4 {
        for _ in 0..<1 {
          let bpl = blobPoints(nx + (random() - 0.5) * wid * 1.2 * (reso - Double(i)) * 0.5, ny + (random() - 0.5) * wid * 0.5,
                               len: random() * 50 + 20, wid: random() * 12 + 12, ang: (-random() * Double.pi) / 6, fun: {
                                 $0 <= 1 ? 2.75 * $0 * jsPow(1 - $0, 1 / 1.8) : 2.75 * ($0 - 2) * jsPow($0 - 1, 1 / 1.8)
                               })

          //canv+=poly(bpl,{fil:col,wid:0})
          T = T + triangulate(bpl, area: 50, convex: true, optimize: false)
        }
      }
      line1.append(Pt(nx + (nslist[i].0 - 0.5) * wid - wid / 2, ny))
      line2.append(Pt(nx + (nslist[i].1 - 0.5) * wid + wid / 2, ny))
    }

    //canv += poly(line1.concat(line2.reverse()),{fil:col,wid:0})
    T = triangulate(line1 + line2.reversed(), area: 50, convex: true, optimize: true) + T

    for k in 0..<T.count {
      let m = midPt(T[k])
      let c = jsInt32(noise(m[0] * 0.02, m[1] * 0.02) * 200 + 50)
      let co = "rgba(" + String(c) + "," + String(c) + "," + String(c) + ",0.8)"
      canv += poly(T[k], fil: co, str: co, wid: 0)
    }
    return canv
  }

  func tree08(_ x: Double, _ y: Double, hei: Double = 80, wid: Double = 1, col: String = "rgba(100,100,100,0.5)", noi: Double = 0.5) -> String {
    var canv = ""
    let txcanv = ""
    var twcanv = ""

    let ang = normRand(-1, 1) * Double.pi * 0.2

    let trpair = branch(hei: hei, wid: wid, ang: -Double.pi / 2 + ang, det: hei / 20, ben: Double.pi * 0.2)
    //txcanv += barkify(x,y,trlist)

    let trlist = trpair.0 + trpair.1.reversed()

    // The original's fracTree also takes a `hei`, which it never reads.
    func fracTree(_ xoff: Double, _ yoff: Double, _ dep: Double, ang: Double, len: Double = 15, ben: Double = 0) -> String {
      let fun: (Double) -> Double = dep == 0 ? { cos(0.5 * Double.pi * $0) } : { _ in 1 }
      let spt = Pt(xoff, yoff)
      let ept = Pt(xoff + cos(ang) * len, yoff + sin(ang) * len)

      var trmlist = [Pt(xoff, yoff), Pt(xoff + len, yoff)]

      let bfun = randChoice([{ (x: Double) -> Double in sin(x * Double.pi) }, { (x: Double) -> Double in -sin(x * Double.pi) }])

      trmlist = div(trmlist, 10)

      for i in 0..<trmlist.count {
        trmlist[i][1] += bfun(Double(i) / Double(trmlist.count)) * 2
      }
      for i in 0..<trmlist.count {
        let d = distance(trmlist[i], spt)
        let a = atan2(trmlist[i][1] - spt[1], trmlist[i][0] - spt[0])
        trmlist[i][0] = spt[0] + d * cos(a + ang)
        trmlist[i][1] = spt[1] + d * sin(a + ang)
      }

      var tcanv = ""
      tcanv += stroke(trmlist, wid: 0.8, col: "rgba(100,100,100,0.5)", fun: fun)
      if dep != 0 {
        let nben = ben + randChoice([-1.0, 1]) * Double.pi * 0.001 * dep * dep
        if random() < 0.5 {
          tcanv += fracTree(ept[0], ept[1], dep - 1, ang: ang + ben + Double.pi * randChoice([normRand(-1, 0.5), normRand(0.5, 1)]) * 0.2,
                            len: len * normRand(0.8, 0.9), ben: nben)
          tcanv += fracTree(ept[0], ept[1], dep - 1, ang: ang + ben + Double.pi * randChoice([normRand(-1, -0.5), normRand(0.5, 1)]) * 0.2,
                            len: len * normRand(0.8, 0.9), ben: nben)
        } else {
          tcanv += fracTree(ept[0], ept[1], dep - 1, ang: ang + ben, len: len * normRand(0.8, 0.9), ben: nben)
        }
      }
      return tcanv
    }

    for i in 0..<trlist.count {
      if random() < 0.2 {
        twcanv += fracTree(x + trlist[i][0], y + trlist[i][1], (4 * random()).rounded(.down), ang: -Double.pi / 2 - ang * random())
      } else if Double(i) == (Double(trlist.count) / 2).rounded(.down) {
        twcanv += fracTree(x + trlist[i][0], y + trlist[i][1], 3, ang: -Double.pi / 2 + ang)
      }
    }

    canv += poly(trlist, xof: x, yof: y, fil: "white", str: col, wid: 0)

    canv += stroke(trlist.map { Pt($0[0] + x, $0[1] + y) }, wid: 2.5, col: "rgba(100,100,100," + jsFixed(0.6 + random() * 0.1, 3) + ")",
                   noi: 0.9, out: 0, fun: { _ in sin(1) })

    canv += txcanv
    canv += twcanv
    //console.log(canv)
    return canv
  }
}

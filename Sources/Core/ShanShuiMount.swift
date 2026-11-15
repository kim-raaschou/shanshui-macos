import Foundation

// The original's Mount: the mountains, the flat hills and what stands on
// them, the far mountains and the rocks.

extension ShanShui {
  private func foot(_ ptlist: [[Pt]], xof: Double = 0, yof: Double = 0) -> String {
    var ftlist: [[Pt]] = []
    let span = 10
    var ni = 0
    for i in 0..<max(0, ptlist.count - 2) where i == ni {
      ni = min(ni + randChoice([1, 2]), ptlist.count - 1)
      var a: [Pt] = [], b: [Pt] = []
      let n = ptlist[i].count
      var j = 0
      while Double(j) < min(Double(n) / 8, 10) {
        a.append(Pt(ptlist[i][j][0] + noise(Double(j) * 0.1, Double(i)) * 10, ptlist[i][j][1]))
        b.append(Pt(ptlist[i][n - 1 - j][0] - noise(Double(j) * 0.1, Double(i)) * 10, ptlist[i][n - 1 - j][1]))
        j += 1
      }
      a.reverse()
      b.reverse()
      for j in 0..<span {
        let p = Double(j) / Double(span)
        let x1 = ptlist[i][0][0] * (1 - p) + ptlist[ni][0][0] * p
        var y1 = ptlist[i][0][1] * (1 - p) + ptlist[ni][0][1] * p
        let x2 = ptlist[i][n - 1][0] * (1 - p) + ptlist[ni][n - 1][0] * p
        var y2 = ptlist[i][n - 1][1] * (1 - p) + ptlist[ni][n - 1][1] * p
        let vib = -1.7 * (p - 1) * jsPow(p, 1.0 / 5)
        y1 += vib * 5 + noise(xof * 0.05, Double(i)) * 5
        y2 += vib * 5 + noise(xof * 0.05, Double(i)) * 5
        a.append(Pt(x1, y1))
        b.append(Pt(x2, y2))
      }
      ftlist.append(a)
      ftlist.append(b)
    }
    var canv = ""
    for l in ftlist { canv += poly(l, xof: xof, yof: yof, fil: "white", str: "none") }
    for l in ftlist {
      let pts = l.map { Pt($0[0] + xof, $0[1] + yof) }
      canv += stroke(pts, wid: 1, col: "rgba(100,100,100," + jsFixed(0.1 + random() * 0.1, 3) + ")")
    }
    return canv
  }

  func mountain(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double? = nil, wid: Double? = nil, tex: Double = 200,
                veg: Bool = true, col: ((Double) -> String)? = nil) -> String {
    let hei = hei ?? 100 + random() * 400
    let wid = wid ?? 400 + random() * 200
    var canv = ""
    var ptlist: [[Pt]] = []
    let h = hei, w = wid
    let reso = (10, 50)
    var hoff = 0.0
    for j in 0..<reso.0 {
      hoff += (random() * yoff) / 100
      ptlist.append([])
      for i in 0..<reso.1 {
        let x = (Double(i) / Double(reso.1) - 0.5) * Double.pi
        var y = cos(x)
        y *= noise(x + 10, Double(j) * 0.15, seed)
        let p = 1 - Double(j) / Double(reso.0)
        ptlist[ptlist.count - 1].append(Pt((x / Double.pi) * w * p, -y * h * p + hoff))
      }
    }
    let n = reso.1

    func vegetate(_ treeFunc: (Double, Double) -> String, _ growthRule: (Int, Int) -> Bool, _ proofRule: ([Pt], Int) -> Bool = { _, _ in true }) {
      var veglist: [Pt] = []
      for i in 0..<ptlist.count {
        for j in 0..<ptlist[i].count where growthRule(i, j) { veglist.append(ptlist[i][j]) }
      }
      for i in 0..<veglist.count where proofRule(veglist, i) { canv += treeFunc(veglist[i][0], veglist[i][1]) }
    }
    func shade(_ x: Double, _ y: Double, _ base: Double) -> String {
      "rgba(100,100,100," + jsFixed(noise(0.01 * x, 0.01 * y) * 0.5 * 0.3 + base, 3) + ")"
    }
    //RIM
    vegetate({ x, y in self.tree02(x + xoff, y + yoff - 5, clu: 2, col: shade(x, y, 0.5)) },
             { i, j in
               let ns = self.noise(Double(j) * 0.1, seed)
               return i == 0 && ns * ns * ns < 0.1 && abs(ptlist[i][j][1]) / h > 0.2
             })
    //WHITE BG
    canv += poly(ptlist[0] + [Pt(0, Double(reso.0 * 4))], xof: xoff, yof: yoff, fil: "white", str: "none")
    //OUTLINE
    canv += stroke(ptlist[0].map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: 3, col: "rgba(100,100,100,0.3)", noi: 1)

    canv += foot(ptlist, xof: xoff, yof: yoff)
    canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, sha: randChoice([0, 0, 0, 0, 5]), col: col).canv

    //TOP
    vegetate({ x, y in self.tree02(x + xoff, y + yoff, col: shade(x, y, 0.5)) },
             { i, j in
               let ns = self.noise(Double(i) * 0.1, Double(j) * 0.1, seed + 2)
               return ns * ns * ns < 0.1 && abs(ptlist[i][j][1]) / h > 0.5
             })

    if veg {
      //MIDDLE
      vegetate({ x, y in
                 var ht = ((h + y) / h) * 70
                 ht = ht * 0.3 + self.random() * ht * 0.7
                 let wid = self.random() * 3 + 1
                 return self.tree01(x + xoff, y + yoff, hei: ht, wid: wid, col: shade(x, y, 0.3))
               },
               { i, j in
                 let ns = self.noise(Double(i) * 0.2, Double(j) * 0.05, seed)
                 return j % 2 != 0 && ns * ns * ns * ns < 0.012 && abs(ptlist[i][j][1]) / h < 0.3
               },
               { veglist, i in
                 var counter = 0
                 for j in 0..<veglist.count {
                   if i != j && jsPow(veglist[i][0] - veglist[j][0], 2) + jsPow(veglist[i][1] - veglist[j][1], 2) < 30 * 30 { counter += 1 }
                   if counter > 2 { return true }
                 }
                 return false
               })
      //BOTTOM
      vegetate({ x, y in
                 var ht = ((h + y) / h) * 120
                 ht = ht * 0.5 + self.random() * ht * 0.5
                 let bc = self.random() * 0.1
                 let bp = 1.0
                 return self.tree03(x + xoff, y + yoff, hei: ht, ben: { jsPow($0 * bc, bp) }, col: shade(x, y, 0.3))
               },
               { i, j in
                 let ns = self.noise(Double(i) * 0.2, Double(j) * 0.05, seed)
                 return (j == 0 || j == n - 1) && ns * ns * ns * ns < 0.012
               })
    }

    //BOTT ARCH
    vegetate({ x, y in
               let tt = self.randChoice([0, 0, 1, 1, 1, 2])
               if tt == 1 {
                 let wid = self.normRand(40, 70), sto = self.randChoice([1.0, 2, 2, 3]), rot = self.random(), sty = self.randChoice([1, 2, 3])
                 return self.arch02(x + xoff, y + yoff, seed, wid: wid, rot: rot, sto: sto, sty: sty)
               } else if tt == 2 {
                 return self.arch04(x + xoff, y + yoff, seed, sto: self.randChoice([1.0, 1, 1, 2, 2]))
               }
               return ""
             },
             { i, j in
               let ns = self.noise(Double(i) * 0.2, Double(j) * 0.05, seed + 10)
               return i != 0 && (j == 1 || j == n - 2) && ns * ns * ns * ns < 0.008
             })
    //TOP ARCH
    vegetate({ x, y in
               let sto = self.randChoice([5.0, 7]), wid = 40 + self.random() * 20
               return self.arch03(x + xoff, y + yoff, seed, wid: wid, sto: sto)
             },
             { i, j in i == 1 && abs(Double(j) - Double(n) / 2) < 1 && self.random() < 0.02 })
    //TRANSM
    vegetate({ x, y in self.transmissionTower01(x + xoff, y + yoff, seed) },
             { i, j in
               let ns = self.noise(Double(i) * 0.2, Double(j) * 0.05, seed + 20 * Double.pi)
               return i % 2 == 0 && (j == 1 || j == n - 2) && ns * ns * ns * ns < 0.002
             })
    //BOTT ROCK
    vegetate({ x, y in
               let wid = 20 + self.random() * 20, hei = 20 + self.random() * 20
               return self.rock(x + xoff, y + yoff, seed, hei: hei, wid: wid, sha: 2)
             },
             { _, j in (j == 0 || j == n - 1) && self.random() < 0.1 })
    return canv
  }

  func flatMount(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double? = nil, wid: Double? = nil, tex: Double = 80,
                 cho: Double = 0.5) -> String {
    let hei = hei ?? 40 + random() * 400
    let wid = wid ?? 400 + random() * 200
    var canv = ""
    var ptlist: [[Pt]] = []
    let reso = (5, 50)
    var hoff = 0.0
    var flat: [[Pt]] = []
    for j in 0..<reso.0 {
      hoff += (random() * yoff) / 100
      ptlist.append([])
      flat.append([])
      for i in 0..<reso.1 {
        let x = (Double(i) / Double(reso.1) - 0.5) * Double.pi
        var y = cos(x * 2) + 1
        y *= noise(x + 10, Double(j) * 0.1, seed)
        let p = 1 - (Double(j) / Double(reso.0)) * 0.6
        let nx = (x / Double.pi) * wid * p
        var ny = -y * hei * p + hoff
        let h = 100.0
        if ny < -h * cho + hoff {
          ny = -h * cho + hoff
          if flat[flat.count - 1].count % 2 == 0 { flat[flat.count - 1].append(Pt(nx, ny)) }
        } else if flat[flat.count - 1].count % 2 == 1 {
          flat[flat.count - 1].append(ptlist[ptlist.count - 1][ptlist[ptlist.count - 1].count - 1])
        }
        ptlist[ptlist.count - 1].append(Pt(nx, ny))
      }
    }
    //WHITE BG
    canv += poly(ptlist[0] + [Pt(0, Double(reso.0 * 4))], xof: xoff, yof: yoff, fil: "white", str: "none")
    //OUTLINE
    canv += stroke(ptlist[0].map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: 3, col: "rgba(100,100,100,0.3)", noi: 1)
    canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, wid: 2, dis: { [unowned self] in
      if self.random() > 0.5 { return 0.1 + 0.4 * self.random() }
      return 0.9 - 0.4 * self.random()
    }).canv
    var grlist1: [Pt] = [], grlist2: [Pt] = []
    for i in stride(from: 0, to: flat.count, by: 2) where flat[i].count >= 2 {
      grlist1.append(flat[i][0])
      grlist2.append(flat[i][flat[i].count - 1])
    }
    if grlist1.isEmpty { return canv }
    var wb = (grlist1[0][0], grlist2[0][0])
    for i in 0..<3 {
      let p = 0.8 - Double(i) * 0.2
      grlist1.insert(Pt(wb.0 * p, grlist1[0][1] - 5), at: 0)
      grlist2.insert(Pt(wb.1 * p, grlist2[0][1] - 5), at: 0)
    }
    wb = (grlist1[grlist1.count - 1][0], grlist2[grlist2.count - 1][0])
    for i in 0..<3 {
      let p = 0.6 - Double(i * i) * 0.1
      grlist1.append(Pt(wb.0 * p, grlist1[grlist1.count - 1][1] + 1))
      grlist2.append(Pt(wb.1 * p, grlist2[grlist2.count - 1][1] + 1))
    }
    let d = 5.0
    grlist1 = div(grlist1, d)
    grlist2 = div(grlist2, d)
    grlist1.reverse()
    var grlist = grlist1 + grlist2 + [grlist1[0]]
    // The last point is the first one itself in the original, so it is moved twice.
    let last = grlist.count - 1
    for i in 0..<grlist.count {
      if i == last { grlist[i] = grlist[0] }
      let v = (1 - abs(Double(i).truncatingRemainder(dividingBy: d) - d / 2) / (d / 2)) * 0.12
      grlist[i][0] *= 1 - v + noise(grlist[i][1] * 0.5) * v
      if i == last { grlist[0] = grlist[i] }
    }
    canv += poly(grlist, xof: xoff, yof: yoff, fil: "white", str: "none", wid: 2)
    canv += stroke(grlist.map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: 3, col: "rgba(100,100,100,0.2)")

    // bound: what is not there yet is taken; NaN never is.
    var b = (xmin: Double.nan, xmax: Double.nan, ymin: Double.nan, ymax: Double.nan)
    for (i, p) in grlist.enumerated() {
      if i == 0 || p[0] < b.xmin { b.xmin = p[0] }
      if i == 0 || p[0] > b.xmax { b.xmax = p[0] }
      if i == 0 || p[1] < b.ymin { b.ymin = p[1] }
      if i == 0 || p[1] > b.ymax { b.ymax = p[1] }
    }
    canv += flatDec(xoff, yoff, b)
    return canv
  }

  func flatDec(_ xoff: Double, _ yoff: Double, _ grbd: (xmin: Double, xmax: Double, ymin: Double, ymax: Double)) -> String {
    var canv = ""
    let tt = randChoice([0, 0, 1, 2, 3, 4])
    let ymid = (grbd.ymin + grbd.ymax) / 2
    /// A rock on the hill: the random numbers in the original's order.
    func aRock(_ x: Double, _ y: Double, _ seed: Double, _ wid: Double, _ hei: Double, _ sha: Double) -> String {
      rock(x, y, seed, hei: hei, wid: wid, sha: sha)
    }
    var j = 0.0
    while j < random() * 5 {
      let x = xoff + normRand(grbd.xmin, grbd.xmax), y = yoff + ymid + normRand(-10, 10) + 10, s = random() * 100
      let wid = 10 + random() * 20, hei = 10 + random() * 20
      canv += aRock(x, y, s, wid, hei, 2)
      j += 1
    }
    j = 0
    while j < randChoice([0.0, 0, 1, 2]) {
      let xr = xoff + normRand(grbd.xmin, grbd.xmax)
      let yr = yoff + ymid + normRand(-5, 5) + 20
      var k = 0.0
      while k < 2 + random() * 3 {
        let x = xr + jsMin(jsMax(normRand(-30, 30), grbd.xmin), grbd.xmax)
        canv += tree08(x, yr, hei: 60 + random() * 40)
        k += 1
      }
      j += 1
    }
    func rocks(_ most: Double) {
      var j = 0.0
      while j < random() * most {
        let x = xoff + normRand(grbd.xmin, grbd.xmax), y = yoff + ymid + normRand(-5, 5) + 20, s = random() * 100
        let wid = 50 + random() * 20, hei = 40 + random() * 20
        canv += aRock(x, y, s, wid, hei, 5)
        j += 1
      }
    }
    if tt == 0 { rocks(3) }
    if tt == 1 {
      let pmin = random() * 0.5, pmax = random() * 0.5 + 0.5
      let xmin = grbd.xmin * (1 - pmin) + grbd.xmax * pmin, xmax = grbd.xmin * (1 - pmax) + grbd.xmax * pmax
      var i = xmin
      while i < xmax {
        let x = xoff + i + 20 * normRand(-1, 1)
        canv += tree05(x, yoff + ymid + 20, hei: 100 + random() * 200)
        i += 30
      }
      rocks(4)
    } else if tt == 2 {
      var i = 0.0
      while i < randChoice([1.0, 1, 1, 1, 2, 2, 3]) {
        let xr = normRand(grbd.xmin, grbd.xmax)
        let yr = ymid
        canv += tree04(xoff + xr, yoff + yr + 20)
        var j = 0.0
        while j < random() * 2 {
          let x = xoff + jsMax(grbd.xmin, jsMin(grbd.xmax, xr + normRand(-50, 50)))
          let y = yoff + yr + normRand(-5, 5) + 20
          let s = j * i * random() * 100
          let wid = 50 + random() * 20, hei = 40 + random() * 20
          canv += aRock(x, y, s, wid, hei, 5)
          j += 1
        }
        i += 1
      }
    } else if tt == 3 {
      var i = 0.0
      while i < randChoice([1.0, 1, 1, 1, 2, 2, 3]) {
        let x = xoff + normRand(grbd.xmin, grbd.xmax)
        canv += tree06(x, yoff + ymid, hei: 60 + random() * 60)
        i += 1
      }
    } else if tt == 4 {
      let pmin = random() * 0.5, pmax = random() * 0.5 + 0.5
      let xmin = grbd.xmin * (1 - pmin) + grbd.xmax * pmin, xmax = grbd.xmin * (1 - pmax) + grbd.xmax * pmax
      var i = xmin
      while i < xmax {
        let x = xoff + i + 20 * normRand(-1, 1), y = yoff + ymid + normRand(-1, 1) + 0
        canv += tree07(x, y, hei: normRand(40, 80))
        i += 20
      }
    }
    var i = 0.0
    while i < 50 * random() {
      let x = xoff + normRand(grbd.xmin, grbd.xmax), y = yoff + normRand(grbd.ymin, grbd.ymax)
      canv += tree02(x, y)
      i += 1
    }
    let ts = randChoice([0, 0, 0, 0, 1])
    if ts == 1 && tt != 4 {
      let x = xoff + normRand(grbd.xmin, grbd.xmax), s = random()
      let wid = normRand(160, 200), hei = normRand(80, 100), per = random()
      canv += arch01(x, yoff + ymid + 20, s, hei: hei, wid: wid, per: per)
    }
    return canv
  }

  func distMount(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 300, len: Double = 2000, seg: Double = 5) -> String {
    var canv = ""
    let span = 10.0
    var ptlist: [[Pt]] = []
    var i = 0.0
    while i < len / span / seg {
      var l: [Pt] = []
      var j = 0.0
      while j < seg + 1 {
        let k = i * seg + j
        l.append(Pt(xoff + k * span, yoff - hei * noise(k * 0.05, seed) * jsPow(sin((Double.pi * k) / (len / span)), 0.5)))
        j += 1
      }
      j = 0
      while j < seg / 2 + 1 {
        let k = i * seg + j * 2
        l.insert(Pt(xoff + k * span, yoff + 24 * noise(k * 0.05, 2, seed) * jsPow(sin((Double.pi * k) / (len / span)), 1)), at: 0)
        j += 1
      }
      ptlist.append(l)
      i += 1
    }
    func getCol(_ x: Double, _ y: Double) -> String {
      let c = jsString(Double(jsInt32(noise(x * 0.02, y * 0.02, yoff) * 55 + 200)))
      return "rgb(" + c + "," + c + "," + c + ")"
    }
    for l in ptlist {
      canv += poly(l, fil: getCol(l[l.count - 1][0], l[l.count - 1][1]), str: "none", wid: 1)
      for t in triangulate(l, area: 100, convex: true, optimize: false) {
        let m = midPt(t)
        let co = getCol(m[0], m[1])
        canv += poly(t, fil: co, str: co, wid: 1)
      }
    }
    return canv
  }

  func rock(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 80, wid: Double = 100, tex: Double = 40, sha: Double = 10) -> String {
    var canv = ""
    let reso = (10, 50)
    var ptlist: [[Pt]] = []
    for i in 0..<reso.0 {
      ptlist.append([])
      var nslist: [Double] = []
      for j in 0..<reso.1 { nslist.append(noise(Double(i), Double(j) * 0.2, seed)) }
      loopNoise(&nslist)
      for j in 0..<reso.1 {
        let a = (Double(j) / Double(reso.1)) * Double.pi * 2 - Double.pi / 2
        var l = (wid * hei) / (jsPow(hei * cos(a), 2) + jsPow(wid * sin(a), 2)).squareRoot()
        l *= 0.7 + 0.3 * nslist[j]
        let p = 1 - Double(i) / Double(reso.0)
        let nx = cos(a) * l * p
        var ny = -sin(a) * l * p
        if Double.pi < a || a < 0 { ny *= 0.2 }
        ny += hei * (Double(i) / Double(reso.0)) * 0.2
        ptlist[ptlist.count - 1].append(Pt(nx, ny))
      }
    }
    //WHITE BG
    canv += poly(ptlist[0] + [Pt(0, 0)], xof: xoff, yof: yoff, fil: "white", str: "none")
    //OUTLINE
    canv += stroke(ptlist[0].map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: 3, col: "rgba(100,100,100,0.3)", noi: 1)
    canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, wid: 3, sha: sha,
                    col: { [unowned self] _ in "rgba(180,180,180," + jsFixed(0.3 + self.random() * 0.3, 3) + ")" },
                    dis: { [unowned self] in
                      if self.random() > 0.5 { return 0.15 + 0.15 * self.random() }
                      return 0.85 - 0.15 * self.random()
                    }).canv
    return canv
  }
}

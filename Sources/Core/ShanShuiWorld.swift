import Foundation

// The original's water, its plan of where the mountains stand, and the chunks
// the endless landscape is kept in (mountplanner, MEM, chunkloader).

extension ShanShui {
  /// One thing in the landscape: what it is, where, and its drawing.
  struct Chunk {
    let tag: String
    let x: Double, y: Double
    var canv: String
  }

  /// replace(/NaN/g, -1000), over the bytes: the drawings are long.
  static func withoutNaN(_ canv: String) -> String {
    var t = canv
    return t.withUTF8 { s -> String? in
      let n = s.count
      var i = 0, from = 0
      var out: [UInt8]?
      while i + 2 < n {
        if s[i] == 78, s[i + 1] == 97, s[i + 2] == 78 {
          if out == nil { out = []; out!.reserveCapacity(n + 16) }
          out!.append(contentsOf: UnsafeBufferPointer(rebasing: s[from..<i]))
          out!.append(contentsOf: [45, 49, 48, 48, 48])
          i += 3; from = i
        } else {
          i += 1
        }
      }
      guard var out else { return nil }
      out.append(contentsOf: UnsafeBufferPointer(rebasing: s[from..<n]))
      return String(decoding: out, as: UTF8.self)
    } ?? canv
  }

  func water(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 2, len: Double = 800, clu: Double = 10) -> String {
    var canv = ""
    var ptlist: [[Pt]] = []
    var yk = 0.0
    var i = 0.0
    while i < clu {
      ptlist.append([])
      let xk = (random() - 0.5) * (len / 8)
      yk += random() * 5
      let lk = len / 4 + random() * (len / 4)
      let reso = 5.0
      var j = -lk
      while j < lk {
        ptlist[ptlist.count - 1].append(Pt(j + xk, sin(j * 0.2) * hei * noise(j * 0.1) - 20 + yk))
        j += reso
      }
      i += 1
    }
    for j in stride(from: 1, to: ptlist.count, by: 1) {
      let pts = ptlist[j].map { Pt($0[0] + xoff, $0[1] + yoff) }
      canv += stroke(pts, wid: 1, col: "rgba(100,100,100," + jsFixed(0.3 + random() * 0.3, 3) + ")")
    }
    return canv
  }

  /// What is planned at a place: a tag and where.
  typealias Plan = (tag: String, x: Double, y: Double)

  func mountplanner(_ xmin: Double, _ xmax: Double) -> [Plan] {
    var reg: [Plan] = []
    let samp = 0.03
    func ns(_ x: Double) -> Double { jsMax(noise(x * samp) - 0.55, 0) * 2 }
    func yr(_ x: Double) -> Double { noise(x * 0.01, Double.pi) }
    func locmax(_ x: Double, _ y: Double, _ r: Double) -> Bool {
      let z0 = ns(x)
      if z0 <= 0.3 { return false }
      var i = x - r
      while i < x + r {
        var j = y - r
        while j < y + r {
          if ns(i) > z0 { return false }
          j += 1
        }
        i += 1
      }
      return true
    }
    @discardableResult func chadd(_ r: Plan, _ mind: Double = 10) -> Bool {
      for k in reg where abs(k.x - r.x) < mind { return false }
      reg.append(r)
      return true
    }
    func key(_ v: Double) -> Int { Int(v.rounded(.down)) }

    let xstep = 5.0, mwid = 200.0
    // planmtx[i] = planmtx[i] || 0: what is not there, or not a number, is 0.
    var i = xmin
    while i < xmax {
      let i1 = key(i / xstep)
      if let v = planmtx[i1], !v.isNaN, v != 0 {} else { planmtx[i1] = 0 }
      i += xstep
    }

    i = xmin
    while i < xmax {
      var j = 0.0
      while j < yr(i) * 480 {
        if locmax(i, j, 2) {
          let xof = i + 2 * (random() - 0.5) * 500
          let yof = j + 300
          if chadd(("mount", xof, yof)) {
            // Adding to what is not there gives what is not a number.
            var k = ((xof - mwid) / xstep).rounded(.down)
            while k < (xof + mwid) / xstep {
              planmtx[Int(k)] = (planmtx[Int(k)] ?? .nan) + 1
              k += 1
            }
          }
        }
        j += 30
      }
      if abs(i).truncatingRemainder(dividingBy: 1000) < jsMax(1, xstep - 1) {
        chadd(("distmount", i, 280 - random() * 50))
      }
      i += xstep
    }
    i = xmin
    while i < xmax {
      if planmtx[key(i / xstep)] == 0 {
        if random() < 0.01 {
          var j = 0.0
          while j < 4 * random() {
            chadd(("flatmount", i + 2 * (random() - 0.5) * 700, 700 - j * 50))
            j += 1
          }
        }
      }
      i += xstep
    }
    i = xmin
    while i < xmax {
      if random() < 0.2 { chadd(("boat", i, 300 + random() * 390), 400) }
      i += xstep
    }
    return reg
  }

  func chunkloader(_ xmin: Double, _ xmax: Double) {
    func add(_ n: Chunk) {
      var nch = n
      nch.canv = ShanShui.withoutNaN(nch.canv)
      if chunks.isEmpty { chunks.append(nch); return }
      if nch.y <= chunks[0].y { chunks.insert(nch, at: 0); return }
      if nch.y >= chunks[chunks.count - 1].y { chunks.append(nch); return }
      for j in 0..<(chunks.count - 1) where chunks[j].y <= nch.y && nch.y <= chunks[j + 1].y {
        chunks.insert(nch, at: j + 1)
        return
      }
    }

    while xmax > self.xmax - cwid || xmin < self.xmin + cwid {
      // zed.shanshui: each chunk has its own seed, so a view at x=50000 need
      // not make everything from x=0.
      onchunk?(xmax > self.xmax - cwid ? self.xmax : self.xmin - cwid)
      let plan: [Plan]
      if xmax > self.xmax - cwid {
        plan = mountplanner(self.xmax, self.xmax + cwid)
        self.xmax = self.xmax + cwid
      } else {
        plan = mountplanner(self.xmin - cwid, self.xmin)
        self.xmin = self.xmin - cwid
      }
      for i in 0..<plan.count {
        let p = plan[i]
        if p.tag == "mount" {
          add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: mountain(p.x, p.y, Double(i) * 2 * random())))
          add(Chunk(tag: p.tag, x: p.x, y: p.y - 10000, canv: water(p.x, p.y, Double(i) * 2)))
        } else if p.tag == "flatmount" {
          add(Chunk(tag: p.tag, x: p.x, y: p.y,
                    canv: flatMount(p.x, p.y, 2 * random() * Double.pi, hei: 100, wid: 600 + random() * 400, cho: 0.5 + random() * 0.2)))
        } else if p.tag == "distmount" {
          add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: distMount(p.x, p.y, random() * 100, hei: 150, len: randChoice([500, 1000, 1500]))))
        } else if p.tag == "boat" {
          add(Chunk(tag: p.tag, x: p.x, y: p.y, canv: boat01(p.x, p.y, random(), sca: p.y / 800, fli: randChoice([true, false]))))
        }
      }
    }
  }
}

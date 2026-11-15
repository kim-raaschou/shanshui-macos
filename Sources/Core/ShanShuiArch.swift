import Foundation

// The original's Arch: the huts, pagodas and towers, the boat and the pylon.

extension ShanShui {
  /// The four corners of a wall, for what is drawn on it.
  typealias Wall = (pul: Pt, pur: Pt, pdl: Pt, pdr: Pt)

  private func flip(_ ptlist: [Pt], _ axis: Double = 0) -> [Pt] { ptlist.map { Pt(axis - ($0[0] - axis), $0[1]) } }

  private func hut(_ xoff: Double, _ yoff: Double, hei: Double = 40, wid: Double = 180, tex: Double = 300) -> String {
    let reso = (10, 10)
    var ptlist: [[Pt]] = []
    for i in 0..<reso.0 {
      ptlist.append([])
      let heir = hei + hei * 0.2 * random()
      for j in 0..<reso.1 {
        let nx = wid * (Double(i) / Double(reso.0 - 1) - 0.5) * jsPow(Double(j) / Double(reso.1 - 1), 0.7)
        let ny = heir * (Double(j) / Double(reso.1 - 1))
        ptlist[ptlist.count - 1].append(Pt(nx, ny))
      }
    }
    var canv = ""
    canv += poly(Array(ptlist[0].dropLast()) + ptlist[ptlist.count - 1].dropLast().reversed(), xof: xoff, yof: yoff, fil: "white", str: "none")
    canv += poly(ptlist[0], xof: xoff, yof: yoff, fil: "none", str: "rgba(100,100,100,0.3)", wid: 2)
    canv += poly(ptlist[ptlist.count - 1], xof: xoff, yof: yoff, fil: "none", str: "rgba(100,100,100,0.3)", wid: 2)
    canv += texture(ptlist, xof: xoff, yof: yoff, tex: tex, wid: 1, len: 0.25,
                    noi: { _ in 5 },
                    col: { [unowned self] _ in "rgba(120,120,120," + jsFixed(0.3 + self.random() * 0.3, 3) + ")" },
                    dis: { [unowned self] in self.wtrand { $0 * $0 } }).canv
    return canv
  }

  private func box(_ xoff: Double, _ yoff: Double, hei: Double = 20, wid: Double = 120, rot: Double = 0.7, per: Double = 4,
                   tra: Bool = true, bot: Bool = true, wei: Double = 3, dec: ((Wall) -> [[Pt]])? = nil) -> String {
    let mid = -wid * 0.5 + wid * rot
    let bmid = -wid * 0.5 + wid * (1 - rot)
    var ptlist: [[Pt]] = []
    ptlist.append(div([Pt(-wid * 0.5, -hei), Pt(-wid * 0.5, 0)], 5))
    ptlist.append(div([Pt(wid * 0.5, -hei), Pt(wid * 0.5, 0)], 5))
    if bot {
      ptlist.append(div([Pt(-wid * 0.5, 0), Pt(mid, per)], 5))
      ptlist.append(div([Pt(wid * 0.5, 0), Pt(mid, per)], 5))
    }
    ptlist.append(div([Pt(mid, -hei), Pt(mid, per)], 5))
    if tra {
      if bot {
        ptlist.append(div([Pt(-wid * 0.5, 0), Pt(bmid, -per)], 5))
        ptlist.append(div([Pt(wid * 0.5, 0), Pt(bmid, -per)], 5))
      }
      ptlist.append(div([Pt(bmid, -hei), Pt(bmid, -per)], 5))
    }
    let surf: Double = (rot < 0.5 ? 1 : 0) * 2 - 1
    if let dec {
      ptlist += dec((pul: Pt(surf * wid * 0.5, -hei), pur: Pt(mid, -hei + per), pdl: Pt(surf * wid * 0.5, 0), pdr: Pt(mid, per)))
    }
    let polist = [Pt(-wid * 0.5, -hei), Pt(wid * 0.5, -hei), Pt(wid * 0.5, 0), Pt(mid, per), Pt(-wid * 0.5, 0)]
    var canv = ""
    if !tra { canv += poly(polist, xof: xoff, yof: yoff, fil: "white", str: "none") }
    for l in ptlist {
      canv += stroke(l.map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: wei, col: "rgba(100,100,100,0.4)", noi: 1, fun: { _ in 1 })
    }
    return canv
  }

  private func deco(_ style: Int, _ w: Wall, hsp: (Int, Int) = (1, 3), vsp: (Int, Int) = (1, 2)) -> [[Pt]] {
    var plist: [[Pt]] = []
    let dl = div([w.pul, w.pdl], Double(vsp.1))
    let dr = div([w.pur, w.pdr], Double(vsp.1))
    let du = div([w.pul, w.pur], Double(hsp.1))
    let dd = div([w.pdl, w.pdr], Double(hsp.1))
    if style == 1 {
      //-| |-
      let mlu = du[hsp.0], mru = du[du.count - 1 - hsp.0], mld = dd[hsp.0], mrd = dd[du.count - 1 - hsp.0]
      var i = vsp.0
      while i < dl.count - vsp.0 {
        let mml = div([mlu, mld], Double(vsp.1))[i]
        let mmr = div([mru, mrd], Double(vsp.1))[i]
        let ml = dl[i], mr = dr[i]
        plist.append(div([mml, ml], 5))
        plist.append(div([mmr, mr], 5))
        i += vsp.0
      }
      plist.append(div([mlu, mld], 5))
      plist.append(div([mru, mrd], 5))
    } else if style == 2 {
      //||||
      var i = hsp.0
      while i < du.count - hsp.0 {
        plist.append(div([du[i], dd[i]], 5))
        i += hsp.0
      }
    } else if style == 3 {
      //|##|
      let mlu = du[hsp.0], mru = du[du.count - 1 - hsp.0], mld = dd[hsp.0], mrd = dd[du.count - 1 - hsp.0]
      var i = vsp.0
      while i < dl.count - vsp.0 {
        let mml = div([mlu, mld], Double(vsp.1))[i]
        let mmr = div([mru, mrd], Double(vsp.1))[i]
        let mmu = div([mlu, mru], Double(vsp.1))[i]
        let mmd = div([mld, mrd], Double(vsp.1))[i]
        plist.append(div([mml, mmr], 5))
        plist.append(div([mmu, mmd], 5))
        i += vsp.0
      }
      plist.append(div([mlu, mld], 5))
      plist.append(div([mru, mrd], 5))
    }
    return plist
  }

  private func rail(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 20, wid: Double = 180, rot: Double = 0.7,
                    per: Double = 4, seg: Double = 4, wei: Double = 1, tra: Bool = true, fro: Bool = true) -> String {
    let mid = -wid * 0.5 + wid * rot
    let bmid = -wid * 0.5 + wid * (1 - rot)
    var ptlist: [[Pt]] = []
    if fro {
      ptlist.append(div([Pt(-wid * 0.5, 0), Pt(mid, per)], seg))
      ptlist.append(div([Pt(mid, per), Pt(wid * 0.5, 0)], seg))
    }
    if tra {
      ptlist.append(div([Pt(-wid * 0.5, 0), Pt(bmid, -per)], seg))
      ptlist.append(div([Pt(bmid, -per), Pt(wid * 0.5, 0)], seg))
    }
    if fro {
      ptlist.append(div([Pt(-wid * 0.5, -hei), Pt(mid, -hei + per)], seg))
      ptlist.append(div([Pt(mid, -hei + per), Pt(wid * 0.5, -hei)], seg))
    }
    if tra {
      ptlist.append(div([Pt(-wid * 0.5, -hei), Pt(bmid, -hei - per)], seg))
      ptlist.append(div([Pt(bmid, -hei - per), Pt(wid * 0.5, -hei)], seg))
    }
    if tra {
      // The original shortens the same list twice.
      let open = Int((random() * Double(ptlist.count)).rounded(.down))
      ptlist[open] = Array(ptlist[open].dropLast())
      ptlist[open] = Array(ptlist[open].dropLast())
    }
    var canv = ""
    let n = ptlist.count
    for i in 0..<(n / 2) {
      let o = (n / 2 + i) % n
      for j in 0..<ptlist[i].count {
        ptlist[i][j][1] += (noise(Double(i), Double(j) * 0.5, seed) - 0.5) * hei
        let k = j % ptlist[o].count
        ptlist[o][k][1] += (noise(Double(i) + 0.5, Double(j) * 0.5, seed) - 0.5) * hei
        var ln = div([ptlist[i][j], ptlist[o][k]], 2)
        ln[0][0] += (random() - 0.5) * hei * 0.5
        canv += poly(ln, xof: xoff, yof: yoff, fil: "none", str: "rgba(100,100,100,0.5)", wid: 2)
      }
    }
    for l in ptlist {
      canv += stroke(l.map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: wei, col: "rgba(100,100,100,0.5)", noi: 0.5, fun: { _ in 1 })
    }
    return canv
  }

  private func roof(_ xoff: Double, _ yoff: Double, hei: Double = 20, wid: Double = 120, rot: Double = 0.7, per: Double = 4,
                    cor: Double = 5, wei: Double = 3, pla: (Int, String) = (0, "")) -> String {
    func opf(_ ptlist: [Pt]) -> [Pt] { rot < 0.5 ? flip(ptlist) : ptlist }
    let rrot = rot < 0.5 ? 1 - rot : rot
    let mid = -wid * 0.5 + wid * rrot
    let quat = (mid + wid * 0.5) * 0.5 - mid
    var ptlist: [[Pt]] = []
    ptlist.append(div(opf([Pt(-wid * 0.5 + quat, -hei - per / 2), Pt(-wid * 0.5 + quat * 0.5, -hei / 2 - per / 4), Pt(-wid * 0.5 - cor, 0)]), 5))
    ptlist.append(div(opf([Pt(mid + quat, -hei), Pt((mid + quat + wid * 0.5) / 2, -hei / 2), Pt(wid * 0.5 + cor, 0)]), 5))
    ptlist.append(div(opf([Pt(mid + quat, -hei), Pt(mid + quat / 2, -hei / 2 + per / 2), Pt(mid + cor, per)]), 5))
    ptlist.append(div(opf([Pt(-wid * 0.5 - cor, 0), Pt(mid + cor, per)]), 5))
    ptlist.append(div(opf([Pt(wid * 0.5 + cor, 0), Pt(mid + cor, per)]), 5))
    ptlist.append(div(opf([Pt(-wid * 0.5 + quat, -hei - per / 2), Pt(mid + quat, -hei)]), 5))
    var canv = ""
    let polist = opf([Pt(-wid * 0.5, 0), Pt(-wid * 0.5 + quat, -hei - per / 2), Pt(mid + quat, -hei), Pt(wid * 0.5, 0), Pt(mid, per)])
    canv += poly(polist, xof: xoff, yof: yoff, fil: "white", str: "none")
    for l in ptlist {
      canv += stroke(l.map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: wei, col: "rgba(100,100,100,0.4)", noi: 1, fun: { _ in 1 })
    }
    if pla.0 == 1 {
      var pp = opf([Pt(mid + quat / 2, -hei / 2 + per / 2), Pt(-wid * 0.5 + quat * 0.5, -hei / 2 - per / 4)])
      if pp[0][0] > pp[1][0] { pp = [pp[1], pp[0]] }
      let mp = midPt(pp)
      let a = atan2(pp[1][1] - pp[0][1], pp[1][0] - pp[0][0])
      let adeg = (a * 180) / Double.pi
      canv += "<text font-size='" + jsString(hei * 0.6) + "' font-family='Verdana'" + " style='fill:rgba(100,100,100,0.9)'"
        + " text-anchor='middle' transform='translate(" + jsString(mp[0] + xoff) + "," + jsString(mp[1] + yoff) + ") rotate("
        + jsString(adeg) + ")'>" + pla.1 + "</text>"
    }
    return canv
  }

  private func pagroof(_ xoff: Double, _ yoff: Double, hei: Double = 20, wid: Double = 120, rot: Double = 0.7, per: Double = 4,
                       cor: Double = 10, sid: Double = 4, wei: Double = 3) -> String {
    var ptlist: [[Pt]] = []
    var polist = [Pt(0, -hei)]
    var canv = ""
    var i = 0.0
    while i < sid {
      let fx = wid * ((i * 1.0) / (sid - 1) - 0.5)
      let fy = per * (1 - abs((i * 1.0) / (sid - 1) - 0.5) * 2)
      let fxx = (wid + cor) * ((i * 1.0) / (sid - 1) - 0.5)
      if i > 0 { ptlist.append([ptlist[ptlist.count - 1][2], Pt(fxx, fy)]) }
      ptlist.append([Pt(0, -hei), Pt(fx * 0.5, (-hei + fy) * 0.5), Pt(fxx, fy)])
      polist.append(Pt(fxx, fy))
      i += 1
    }
    canv += poly(polist, xof: xoff, yof: yoff, fil: "white", str: "none")
    for l in ptlist {
      canv += stroke(div(l, 5).map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: wei, col: "rgba(100,100,100,0.4)", noi: 1, fun: { _ in 1 })
    }
    return canv
  }

  func arch01(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 70, wid: Double = 180, rot: Double = 0.7, per: Double = 5) -> String {
    let p = 0.4 + random() * 0.2
    let h0 = hei * p
    let h1 = hei * (1 - p)
    var canv = ""
    canv += hut(xoff, yoff - hei, hei: h0, wid: wid)
    canv += box(xoff, yoff, hei: h1, wid: (wid * 2) / 3, per: per, bot: false)
    canv += rail(xoff, yoff, seed, hei: 10, wid: wid, per: per * 2, seg: Double(jsInt32(3 + random() * 3)), tra: true, fro: false)
    let mcnt = randChoice([0, 1, 1, 2])
    if mcnt == 1 {
      let x = xoff + normRand(-wid / 3, wid / 3)
      canv += man(x, yoff, sca: 0.42, fli: randChoice([true, false]))
    } else if mcnt == 2 {
      canv += man(xoff + normRand(-wid / 4, -wid / 5), yoff, sca: 0.42, fli: false)
      canv += man(xoff + normRand(wid / 5, wid / 4), yoff, sca: 0.42, fli: true)
    }
    canv += rail(xoff, yoff, seed, hei: 10, wid: wid, per: per * 2, seg: Double(jsInt32(3 + random() * 3)), tra: false, fro: true)
    return canv
  }

  func arch02(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 10, wid: Double = 50, rot: Double = 0.3, per: Double = 5,
              sto: Double = 3, sty: Int = 1, rai: Bool = false) -> String {
    var canv = ""
    var hoff = 0.0
    let hsp = [(0, 0), (1, 5), (1, 5), (1, 4)][sty], vsp = [(0, 0), (1, 2), (1, 2), (1, 3)][sty]
    var i = 0.0
    while i < sto {
      canv += box(xoff, yoff - hoff, hei: hei, wid: wid * jsPow(0.85, i), rot: rot, per: per, tra: false, wei: 1.5,
                  dec: { [unowned self] a in self.deco(sty, a, hsp: hsp, vsp: vsp) })
      if rai {
        canv += rail(xoff, yoff - hoff, i * 0.2, hei: hei / 2, wid: wid * jsPow(0.85, i) * 1.1, rot: rot, per: per, wei: 0.5, tra: false)
      }
      var pla = (0, "")
      if sto == 1 && random() < 1.0 / 3 { pla = (1, "Pizza Hut") }
      canv += roof(xoff, yoff - hoff - hei, hei: hei, wid: wid * jsPow(0.9, i), rot: rot, per: per, wei: 1.5, pla: pla)
      hoff += hei * 1.5
      i += 1
    }
    return canv
  }

  func arch03(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 10, wid: Double = 50, rot: Double = 0.7, per: Double = 5,
              sto: Double = 7) -> String {
    var canv = ""
    var hoff = 0.0
    var i = 0.0
    while i < sto {
      canv += box(xoff, yoff - hoff, hei: hei, wid: wid * jsPow(0.85, i), rot: rot, per: per / 2, tra: false, wei: 1.5,
                  dec: { [unowned self] a in self.deco(1, a, hsp: (1, 4), vsp: (1, 2)) })
      canv += rail(xoff, yoff - hoff, i * 0.2, hei: hei / 2, wid: wid * jsPow(0.85, i) * 1.1, rot: rot, per: per / 2, seg: 5, wei: 0.5, tra: false)
      canv += pagroof(xoff, yoff - hoff - hei, hei: hei * 1.5, wid: wid * jsPow(0.9, i), rot: rot, per: per, wei: 1.5)
      hoff += hei * 1.5
      i += 1
    }
    return canv
  }

  func arch04(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 15, wid: Double = 30, rot: Double = 0.7, per: Double = 5,
              sto: Double = 2) -> String {
    var canv = ""
    var hoff = 0.0
    var i = 0.0
    while i < sto {
      canv += box(xoff, yoff - hoff, hei: hei, wid: wid * jsPow(0.85, i), rot: rot, per: per / 2, tra: true, wei: 1.5, dec: { _ in [] })
      canv += rail(xoff, yoff - hoff, i * 0.2, hei: hei / 3, wid: wid * jsPow(0.85, i) * 1.2, rot: rot, per: per / 2, seg: 3, wei: 0.5, tra: true)
      canv += pagroof(xoff, yoff - hoff - hei, hei: hei * 1, wid: wid * jsPow(0.9, i), rot: rot, per: per, wei: 1.5)
      hoff += hei * 1.2
      i += 1
    }
    return canv
  }

  func boat01(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, len: Double = 120, sca: Double = 1, fli: Bool = false) -> String {
    var canv = ""
    let dir: Double = fli ? -1 : 1
    canv += man(xoff + 20 * sca * dir, yoff, sca: 0.5 * sca, hat: { [unowned self] in self.hat02($0, $1, fli: $2) },
                ite: { [unowned self] in self.stick01($0, $1, fli: $2) }, fli: !fli, len: [0, 30, 20, 30, 10, 30, 30, 30, 30])
    var plist1: [Pt] = [], plist2: [Pt] = []
    func fun1(_ x: Double) -> Double { jsPow(sin(x * Double.pi), 0.5) * 7 * sca }
    func fun2(_ x: Double) -> Double { jsPow(sin(x * Double.pi), 0.5) * 10 * sca }
    var i = 0.0
    while i < len * sca {
      plist1.append(Pt(i * dir, fun1(i / len)))
      plist2.append(Pt(i * dir, fun2(i / len)))
      i += 5 * sca
    }
    let plist = plist1 + plist2.reversed()
    canv += poly(plist, xof: xoff, yof: yoff, fil: "white")
    canv += stroke(plist.map { Pt(xoff + $0[0], yoff + $0[1]) }, wid: 1, col: "rgba(100,100,100,0.4)", fun: { sin($0 * Double.pi * 2) })
    return canv
  }

  func transmissionTower01(_ xoff: Double, _ yoff: Double, _ seed: Double = 0, hei: Double = 100, wid: Double = 20) -> String {
    var canv = ""
    func quickstroke(_ pl: [Pt]) -> String {
      stroke(div(pl, 5).map { Pt($0[0] + xoff, $0[1] + yoff) }, wid: 1, col: "rgba(100,100,100,0.4)", fun: { _ in 0.5 })
    }
    let p00 = Pt(-wid * 0.05, -hei), p01 = Pt(wid * 0.05, -hei)
    let p10 = Pt(-wid * 0.1, -hei * 0.9), p11 = Pt(wid * 0.1, -hei * 0.9)
    let p20 = Pt(-wid * 0.2, -hei * 0.5), p21 = Pt(wid * 0.2, -hei * 0.5)
    let p30 = Pt(-wid * 0.5, 0), p31 = Pt(wid * 0.5, 0)
    let bch = [Pt(0.7, -0.85), Pt(1, -0.675), Pt(0.7, -0.5)]
    for b in bch {
      canv += quickstroke([Pt(-b[0] * wid, b[1] * hei), Pt(b[0] * wid, b[1] * hei)])
      canv += quickstroke([Pt(-b[0] * wid, b[1] * hei), Pt(0, (b[1] - 0.05) * hei)])
      canv += quickstroke([Pt(b[0] * wid, b[1] * hei), Pt(0, (b[1] - 0.05) * hei)])
      canv += quickstroke([Pt(-b[0] * wid, b[1] * hei), Pt(-b[0] * wid, (b[1] + 0.1) * hei)])
      canv += quickstroke([Pt(b[0] * wid, b[1] * hei), Pt(b[0] * wid, (b[1] + 0.1) * hei)])
    }
    let l10 = div([p00, p10, p20, p30], 5), l11 = div([p01, p11, p21, p31], 5)
    for i in 0..<(l10.count - 1) {
      canv += quickstroke([l10[i], l11[i + 1]])
      canv += quickstroke([l11[i], l10[i + 1]])
    }
    canv += quickstroke([p00, p01])
    canv += quickstroke([p10, p11])
    canv += quickstroke([p20, p21])
    canv += quickstroke([p00, p10, p20, p30])
    canv += quickstroke([p01, p11, p21, p31])
    return canv
  }
}

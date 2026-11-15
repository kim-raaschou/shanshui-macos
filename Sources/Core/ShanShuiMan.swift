import Foundation

// The original's Man: the figures, their hats and what they carry.

extension ShanShui {
  /// A hat or a thing in the hand: between two points, flipped or not.
  typealias Item = (_ p0: Pt, _ p1: Pt, _ fli: Bool) -> String

  private func expand(_ ptlist: [Pt], _ wfun: (Double) -> Double) -> ([Pt], [Pt]) {
    var vtxlist0: [Pt] = [], vtxlist1: [Pt] = []
    _ = random() * 10
    let n = ptlist.count
    if n > 2 {
      for i in 1..<(n - 1) {
        let w = wfun(Double(i) / Double(n))
        let a1 = atan2(ptlist[i][1] - ptlist[i - 1][1], ptlist[i][0] - ptlist[i - 1][0])
        let a2 = atan2(ptlist[i][1] - ptlist[i + 1][1], ptlist[i][0] - ptlist[i + 1][0])
        var a = (a1 + a2) / 2
        if a < a2 { a += Double.pi }
        vtxlist0.append(Pt(ptlist[i][0] + w * cos(a), ptlist[i][1] + w * sin(a)))
        vtxlist1.append(Pt(ptlist[i][0] - w * cos(a), ptlist[i][1] - w * sin(a)))
      }
    }
    let l = n - 1
    let a0 = atan2(ptlist[1][1] - ptlist[0][1], ptlist[1][0] - ptlist[0][0]) - Double.pi / 2
    let a1 = atan2(ptlist[l][1] - ptlist[l - 1][1], ptlist[l][0] - ptlist[l - 1][0]) - Double.pi / 2
    let w0 = wfun(0), w1 = wfun(1)
    vtxlist0.insert(Pt(ptlist[0][0] + w0 * cos(a0), ptlist[0][1] + w0 * sin(a0)), at: 0)
    vtxlist1.insert(Pt(ptlist[0][0] - w0 * cos(a0), ptlist[0][1] - w0 * sin(a0)), at: 0)
    vtxlist0.append(Pt(ptlist[l][0] + w1 * cos(a1), ptlist[l][1] + w1 * sin(a1)))
    vtxlist1.append(Pt(ptlist[l][0] - w1 * cos(a1), ptlist[l][1] - w1 * sin(a1)))
    return (vtxlist0, vtxlist1)
  }

  private func tranpoly(_ p0: Pt, _ p1: Pt, _ ptlist: [Pt]) -> [Pt] {
    let plist = ptlist.map { Pt(-$0[0], $0[1]) }
    let ang = atan2(p1[1] - p0[1], p1[0] - p0[0]) - Double.pi / 2
    let scl = distance(p0, p1)
    return plist.map { v in
      let d = distance(v, Pt(0, 0))
      let a = atan2(v[1], v[0])
      return Pt(p0[0] + d * scl * cos(ang + a), p0[1] + d * scl * sin(ang + a))
    }
  }

  private func flipper(_ plist: [Pt], _ fli: Bool) -> [Pt] { fli ? plist.map { Pt(-$0[0], $0[1]) } : plist }

  func hat01(_ p0: Pt, _ p1: Pt, fli: Bool = false) -> String {
    var canv = ""
    let seed = random()
    canv += poly(tranpoly(p0, p1, flipper([Pt(-0.3, 0.5), Pt(0.3, 0.8), Pt(0.2, 1), Pt(0, 1.1), Pt(-0.3, 1.15), Pt(-0.55, 1), Pt(-0.65, 0.5)], fli)),
                 fil: "rgba(100,100,100,0.8)")
    var qlist1: [Pt] = []
    for i in 0..<10 {
      let d = Double(i)
      qlist1.append(Pt(-0.3 - noise(d * 0.2, seed) * d * 0.1, 0.5 - d * 0.3))
    }
    canv += poly(tranpoly(p0, p1, flipper(qlist1, fli)), str: "rgba(100,100,100,0.8)", wid: 1)
    return canv
  }

  func hat02(_ p0: Pt, _ p1: Pt, fli: Bool = false) -> String {
    _ = random()
    return poly(tranpoly(p0, p1, flipper([Pt(-0.3, 0.5), Pt(-1.1, 0.5), Pt(-1.2, 0.6), Pt(-1.1, 0.7), Pt(-0.3, 0.8), Pt(0.3, 0.8), Pt(1.0, 0.7),
                                          Pt(1.3, 0.6), Pt(1.2, 0.5), Pt(0.3, 0.5)], fli)),
                fil: "rgba(100,100,100,0.8)")
  }

  func stick01(_ p0: Pt, _ p1: Pt, fli: Bool = false) -> String {
    let seed = random()
    var qlist1: [Pt] = []
    let l = 12.0
    for i in 0..<12 {
      let d = Double(i)
      qlist1.append(Pt(-noise(d * 0.1, seed) * 0.1 * sin((d / l) * Double.pi) * 5, 0 + d * 0.3))
    }
    return poly(tranpoly(p0, p1, flipper(qlist1, fli)), str: "rgba(100,100,100,0.5)", wid: 1)
  }

  //      2
  //    1/
  // 7/  | \_ 6
  // 8| 0 \ 5
  //      /3
  //     4

  /// The way from the root to each joint of the figure above.
  private static let sct: [[Int]] = [[0], [0, 1], [0, 1, 2], [0, 3], [0, 3, 4], [0, 1, 5], [0, 1, 5, 6], [0, 1, 7], [0, 1, 7, 8]]

  func man(_ xoff: Double, _ yoff0: Double, sca: Double = 0.5, hat: Item? = nil, ite: Item? = nil, fli: Bool = true,
           ang: [Double]? = nil, len: [Double]? = nil) -> String {
    var yoff = yoff0
    let hat = hat ?? { [unowned self] in self.hat01($0, $1, fli: $2) }
    let ite = ite ?? { _, _, _ in "" }
    let ang = ang ?? [0, -Double.pi / 2, normRand(0, 0), (Double.pi / 4) * random(), ((Double.pi * 3) / 4) * random(), (Double.pi * 3) / 4,
                      -Double.pi / 4, (-Double.pi * 3) / 4 - (Double.pi / 4) * random(), -Double.pi / 4]
    let len = (len ?? [0, 30, 20, 30, 30, 30, 30, 30, 30]).map { $0 * sca }
    var canv = ""
    func toGlobal(_ v: Pt) -> Pt { Pt((fli ? -1 : 1) * v[0] + xoff, v[1] + yoff) }
    func grot(_ ind: Int) -> Double {
      var rot = 0.0
      for p in ShanShui.sct[ind] { rot += ang[js: p] }
      return rot
    }
    func gpos(_ ind: Int) -> Pt {
      var pos = Pt(0, 0)
      for p in ShanShui.sct[ind] {
        let a = grot(p)
        pos[0] += len[js: p] * cos(a)
        pos[1] += len[js: p] * sin(a)
      }
      return pos
    }
    let pts = (0..<ang.count).map(gpos)
    yoff -= pts[4][1]

    func cloth(_ plist: [Pt], _ fun: (Double) -> Double) -> String {
      var canv = ""
      let tlist = bezmh(plist, 2)
      let (tlist1, t2) = expand(tlist, fun)
      // The original turns the second list round where it stands.
      let tlist2 = Array(t2.reversed())
      canv += poly((tlist1 + tlist2).map(toGlobal), fil: "white")
      canv += stroke(tlist1.map(toGlobal), wid: 1, col: "rgba(100,100,100,0.5)")
      canv += stroke(tlist2.map(toGlobal), wid: 1, col: "rgba(100,100,100,0.6)")
      return canv
    }
    func fsleeve(_ x: Double) -> Double { sca * 8 * (sin(0.5 * x * Double.pi) * jsPow(sin(x * Double.pi), 0.1) + (1 - x) * 0.4) }
    func fbody(_ x: Double) -> Double { sca * 11 * (sin(0.5 * x * Double.pi) * jsPow(sin(x * Double.pi), 0.1) + (1 - x) * 0.5) }
    func fhead(_ x: Double) -> Double { sca * 7 * jsPow(0.25 - jsPow(x - 0.5, 2), 0.3) }

    canv += ite(toGlobal(pts[8]), toGlobal(pts[6]), fli)

    canv += cloth([pts[1], pts[7], pts[8]], fsleeve)
    canv += cloth([pts[1], pts[0], pts[3], pts[4]], fbody)
    canv += cloth([pts[1], pts[5], pts[6]], fsleeve)
    canv += cloth([pts[1], pts[2]], fhead)

    let hlist = bezmh([pts[1], pts[2]], 2)
    var (hlist1, hlist2) = expand(hlist, fhead)
    hlist1.removeFirst(Int((Double(hlist1.count) * 0.1).rounded(.down)))
    hlist2.removeFirst(Int((Double(hlist2.count) * 0.95).rounded(.down)))
    canv += poly((hlist1 + hlist2.reversed()).map(toGlobal), fil: "rgba(100,100,100,0.6)")

    canv += hat(toGlobal(pts[1]), toGlobal(pts[2]), fli)
    return canv
  }
}

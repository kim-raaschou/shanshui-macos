import AppKit
import IOSurface
import QuartzCore

// pintura.frag of the original, without a GPU of our own: the scroll is kept
// as tiles, each a column of one strip already painted (paint.c). A finished
// tile is never touched again and one the front has not reached neither; in
// the tiles the front is crossing, only the pixels it changes are painted
// again. The system moves the tiles as the camera walks (Canvas).
final class Painting {
  static let shared = Painting()
  /// A tile's width, in the strip's pixels.
  static let tileWidth = Int(PAINT_TILE)

  struct Key: Hashable {
    let strip: String
    let j: Int
  }

  /// How a tile keeps its pixels: premultiplied BGRA over what is behind it
  /// (blend); BGRA with the paper in it, which the system need not blend
  /// (opaque); or one byte each, the ink's share over the paper (mono). Only
  /// the back layer, with nothing but the paper behind it, can be opaque or mono.
  enum Kind: String { case blend, opaque, mono }

  final class Tile {
    let kind: Kind
    let surface: IOSurface?
    let shares: NSMutableData?
    let c: Int, k: Int
    let x0: Int, x1: Int   // the strip's columns
    let y0: Int, y1: Int   // and rows: a layer's tile is only as tall as what it has
    let w: Int, h: Int     // the strip's size
    var front = 0.0       // where the front was when it was last painted
    var style = -1
    var list: OpaquePointer?
    var painted = 0
    var seen = 0

    /// `profile` is the colour space of the BGRA pixels, as IOSurface keeps it.
    init?(c: Int, k: Int, x0: Int, x1: Int, y0: Int, y1: Int, w: Int, h: Int, kind: Kind, profile: CFPropertyList?) {
      self.kind = kind
      self.c = c; self.k = k; self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1; self.w = w; self.h = h
      if kind == .mono {
        guard let d = NSMutableData(length: (x1 - x0) * (y1 - y0)) else { return nil }
        shares = d
        surface = nil
        return
      }
      guard let s = IOSurface(properties: [.width: x1 - x0, .height: y1 - y0, .bytesPerElement: 4, .pixelFormat: 0x42475241 as UInt32]) else { return nil }
      // Without it the system takes the pixels for the screen's own colours;
      // in the screen's own, it need not match them at every frame.
      if let profile { IOSurfaceSetValue(unsafeBitCast(s, to: IOSurfaceRef.self), kIOSurfaceColorSpace, profile) }
      surface = s
      shares = nil
    }

    deinit { freeList(list) }

    /// The pixels and the bytes of a row, to paint in.
    func withPixels(_ body: (UnsafeMutablePointer<UInt8>, Int) -> Void) {
      if let shares {
        body(shares.mutableBytes.assumingMemoryBound(to: UInt8.self), x1 - x0)
        return
      }
      guard let s = surface else { return }
      s.lock(options: [], seed: nil)
      body(s.baseAddress.assumingMemoryBound(to: UInt8.self), s.bytesPerRow)
      s.unlock(options: [], seed: nil)
    }

    /// The shares as the system's mask: a new one each time they change.
    var mask: CGImage? {
      guard let shares, let provider = CGDataProvider(data: shares) else { return nil }
      return CGImage(maskWidth: x1 - x0, height: y1 - y0, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: x1 - x0,
                     provider: provider, decode: [1, 0], shouldInterpolate: true)
    }
  }

  /// Everything that changes every pixel: the tiles are painted whole again.
  /// Mono tiles do not hold the colours (`shape` without them).
  private struct Style: Equatable {
    let paper: SIMD4<Float>, ink: SIMD4<Float>
    let shape: Shape
  }
  private struct Shape: Equatable {
    let spread: Double, softness: Double, grain: Double
    let space: CGColorSpace
  }

  /// An sRGB colour in `space`.
  private static func colour(_ c: SIMD4<Float>, in space: CGColorSpace) -> (Float, Float, Float) {
    let srgb = CGColor(colorSpace: Svg.srgb, components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), 1])
    guard let k = srgb?.converted(to: space, intent: .defaultIntent, options: nil)?.components, k.count >= 3 else { return (c.x, c.y, c.z) }
    return (Float(k[0]), Float(k[1]), Float(k[2]))
  }

  private(set) var tiles: [Key: Tile] = [:]
  /// The columns of a layer that have nothing in them: no tile is made.
  private var emptyColumns: Set<Key> = []
  /// Counts the paintings: a tile whose `painted` is this one has new pixels.
  private(set) var pass = 0
  private var style: Style?
  /// The paper's colour of the last painting, for what is behind the tiles.
  var paper: SIMD4<Float> { style?.paper ?? SIMD4<Float>(0, 0, 0, 1) }
  /// And the ink's, for the tiles that hold only its share (mono).
  var ink: SIMD4<Float> { style?.ink ?? SIMD4<Float>(1, 1, 1, 1) }
  /// Counts the styles, and the shapes alone; a tile is whole when its `style`
  /// is the one its kind goes by.
  private var generation = 0
  private var shapes = 0
  /// The style's colours in the tiles' own space, and that space for IOSurface:
  /// worked out when the style changes, not at every frame.
  private var shades = (paper: (Float(0), Float(0), Float(0)), ink: (Float(1), Float(1), Float(1)))
  private var profile: CFPropertyList?
  /// Freed memory will go back to the system in a moment (relieveSoon).
  private var relieving = false

  /// Brings the tiles up to the front, for windows that show `widths` of
  /// the world.
  private func follow(widths: [Double]) {
    let p = Landscape.shared
    pass += 1
    // Nothing is shown: the tiles go.
    guard let visible = widths.max(), visible > 0 else {
      // No painting follows to give it back later; once is enough.
      if !tiles.isEmpty { relieveSoon() }
      tiles = [:]
      emptyColumns = []
      return
    }
    let space = p.displayColors ? p.screenSpace : Svg.srgb
    let e = Style(paper: p.paperNow, ink: p.inkNow, shape: Shape(spread: p.spread, softness: p.softness, grain: p.grain, space: space))
    if e != style {
      // The surfaces are tagged with their colours: in others they are made again.
      if e.shape.space != style?.shape.space {
        // Mono tiles have no colours of their own: they stay.
        tiles = tiles.filter { $0.value.kind == .mono }
        profile = space.copyPropertyList()
      }
      if e.shape != style?.shape { shapes += 1 }
      style = e
      generation += 1
      emptyColumns = []
      shades = (Painting.colour(e.paper, in: space), Painting.colour(e.ink, in: space))
      relieveSoon()
    }
    let view = p.viewWidth, layers = p.layers, mists = p.mists, step = p.inkStep, back = p.back
    var d = Paint()
    d.width = view
    d.spread = e.shape.spread; d.softness = e.shape.softness
    d.paper = shades.paper
    d.ink = shades.ink
    // The paper is what is behind the tiles (Canvas), and the grain is on the
    // layer in front.

    for case let f? in p.strips {
      let camera = p.cameraOf(f.c), start = Double(f.k) * view
      guard start < camera + visible, start + view > camera else { continue }
      let w = f.picture.w, h = f.picture.h
      d.channels = Int32(f.picture.channels); d.w = Int32(w); d.h = Int32(h)
      d.ow = Int32(f.delay.w); d.oh = Int32(f.delay.h)
      d.start = start
      d.front = p.frontOf(f.c)
      d.grain = f.c == layers - 1 ? e.shape.grain : 0
      d.mist = mists[f.c]
      d.ground = f.c == 0 ? 1 : 0
      // Only the back layer has nothing but the paper behind it.
      let kind: Kind = f.c == 0 ? back : .blend
      d.mono = kind == .mono ? 1 : 0
      d.opaque = kind == .opaque ? 1 : 0
      f.picture.data.withUnsafeBytes { (q: UnsafeRawBufferPointer) in
        f.delay.data.withUnsafeBytes { (o: UnsafeRawBufferPointer) in
          d.q = q.baseAddress!.assumingMemoryBound(to: UInt8.self) + f.picture.start
          d.o = o.baseAddress!.assumingMemoryBound(to: UInt8.self) + f.delay.start
          for j in 0..<((w + Painting.tileWidth - 1) / Painting.tileWidth) {
            let x0 = j * Painting.tileWidth, x1 = min(w, x0 + Painting.tileWidth)
            let left = start + Double(x0) / Double(w) * view, right = start + Double(x1) / Double(w) * view
            guard left < camera + visible, right > camera else { continue }
            let key = Key(strip: f.key, j: j)
            if emptyColumns.contains(key) { continue }
            // Another kind chosen: the tile is made again.
            if let t = tiles[key], t.kind != kind {
              tiles[key] = nil
              relieveSoon()
            }
            if tiles[key] == nil {
              // A tile is as tall as what is painted in its columns.
              var y0: Int32 = 0, y1: Int32 = 0
              if extent(&d, Int32(x0), Int32(x1), &y0, &y1) == 0 { emptyColumns.insert(key); continue }
              tiles[key] = Tile(c: f.c, k: f.k, x0: x0, x1: x1, y0: Int(y0), y1: Int(y1), w: w, h: h, kind: kind, profile: profile)
            }
            guard let l = tiles[key] else { continue }
            l.seen = pass
            d.y0 = Int32(l.y0); d.y1 = Int32(l.y1)
            tile(l, &d, step)
          }
        }
      }
    }

    let before = tiles.count
    for (key, l) in tiles where l.seen != pass { tiles[key] = nil }
    if tiles.count < before { relieveSoon() }
    // Strips long gone are still in it.
    if emptyColumns.count > 256 { emptyColumns = [] }
  }

  /// Malloc keeps the pages of what was let go for itself. After a change
  /// that let go of much (a style, a kind, tiles gone), a moment later, once
  /// the layers and the pool have let go of it too, they go back to the system.
  private func relieveSoon() {
    if relieving { return }
    relieving = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
      relieving = false
      malloc_zone_pressure_relief(nil, 0)
    }
  }

  /// One tile, up to the front.
  private func tile(_ l: Tile, _ d: inout Paint, _ step: Double) {
    let x0 = Int32(l.x0), x1 = Int32(l.x1)
    // Mono tiles hold only the ink's share: the colours are the system's.
    let wanted = l.kind == .mono ? shapes : generation
    let full = l.style != wanted
    guard full || reaches(&d, x0, x1, l.front) != 0 else { l.front = d.front; return }
    // The step waits until it is worth painting; the next one takes it along.
    if !full, abs(d.front - l.front) < step { return }
    l.withPixels { pixels, stride in
      if full {
        freeList(l.list)
        l.list = nil
        paint(&d, x0, x1, pixels, stride)
        l.style = wanted
        l.painted = pass
      } else if advance(&d, &l.list, x0, x1, l.front, pixels, stride) != 0 {
        // A step that changed no pixel is nothing for the system to take.
        l.painted = pass
      }
    }
    l.front = d.front
  }

  /// One painting for every view of it; only the ones somebody sees count
  /// for what is kept painted.
  func show(_ views: [(canvas: Canvas, size: CGSize, scale: Double, visible: Bool)]) {
    // A timer alone does not empty the app's pool.
    autoreleasepool {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      follow(widths: views.filter(\.visible).map { Double($0.size.width) / max(1, Double($0.size.height)) * Generator.viewH })
      for v in views { v.canvas.arrange(width: Double(v.size.width), height: Double(v.size.height), scale: v.scale) }
      CATransaction.commit()
    }
  }
}

// One window's view of the tiles: a layer per tile, inside one layer per
// camera. As the camera walks only that one moves; moving it is the system's
// work, not ours.
final class Canvas {
  let root = CALayer()
  private var rolls: [Int: CALayer] = [:]
  private var leaves: [Painting.Key: CALayer] = [:]
  /// The kind of tile each layer was made for.
  private var kinds: [Painting.Key: Painting.Kind] = [:]
  private var color: SIMD4<Float>?
  private var inked: SIMD4<Float>?
  private var inkColor: CGColor?
  private static let still: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "sublayers": NSNull(), "backgroundColor": NSNull()]

  init() {
    root.masksToBounds = true
    root.actions = Canvas.still
  }

  /// Tells the system the surface a layer shows has new pixels. AppKit does
  /// not declare the call CoreAnimation has for it.
  private static let notify = Selector(("setContentsChanged"))
  static func changed(_ f: CALayer, _ s: IOSurface) {
    if f.responds(to: notify) { f.perform(notify) } else { f.contents = nil; f.contents = s }
  }

  func clear() {
    for (_, f) in leaves { f.removeFromSuperlayer() }
    leaves = [:]
    kinds = [:]
  }

  /// `width` and `height` are the window's size in points; `scale` its
  /// pixels per point.
  func arrange(width: Double, height: Double, scale: Double) {
    let p = Landscape.shared, painting = Painting.shared
    guard width > 0, height > 0, scale > 0 else { return }
    let paper = painting.paper
    if paper != color {
      color = paper
      root.backgroundColor = CGColor(colorSpace: Svg.srgb, components: [CGFloat(paper.x), CGFloat(paper.y), CGFloat(paper.z), 1])
    }
    let ink = painting.ink
    if ink != inked {
      inked = ink
      inkColor = CGColor(colorSpace: Svg.srgb, components: [CGFloat(ink.x), CGFloat(ink.y), CGFloat(ink.z), 1])
    }
    // Points per world unit.
    let pt = height / Generator.viewH
    let view = p.viewWidth
    // On whole pixels, so neighbours meet without a seam.
    func snap(_ x: Double) -> Double { (x * scale).rounded() / scale }
    for (key, f) in leaves where painting.tiles[key] == nil {
      f.removeFromSuperlayer()
      leaves[key] = nil
      kinds[key] = nil
    }
    for (key, l) in painting.tiles {
      // The tiles are placed from the screen the camera is in, so their
      // places stay small numbers however far the scroll has gone.
      let seen = p.cameraOf(l.c)
      let origin = (seen / view).rounded(.down) * view
      let r = rolls[l.c] ?? {
        let r = CALayer()
        r.anchorPoint = .zero
        r.zPosition = CGFloat(l.c)
        r.actions = Canvas.still
        root.addSublayer(r)
        rolls[l.c] = r
        return r
      }()
      let place = CGPoint(x: snap((origin - seen) * pt), y: 0)
      if r.position != place { r.position = place }
      let x = (Double(l.k) * view - origin) * pt
      let a = snap(x + Double(l.x0) / Double(l.w) * view * pt), b = snap(x + Double(l.x1) / Double(l.w) * view * pt)
      // A tile made again in the other kind needs a layer of that kind.
      if let f = leaves[key], kinds[key] != l.kind {
        f.removeFromSuperlayer()
        leaves[key] = nil
      }
      let f = leaves[key] ?? {
        let f = CALayer()
        f.anchorPoint = .zero
        f.actions = Canvas.still
        if l.kind == .mono {
          // Mono: the ink's colour, let through as much as the shares say.
          let m = CALayer()
          m.anchorPoint = .zero
          m.contentsGravity = .resize
          m.actions = Canvas.still
          m.contents = l.mask
          f.mask = m
        } else {
          f.contents = l.surface
          f.contentsGravity = .resize
          // Opaque: nothing behind it is drawn or blended.
          f.isOpaque = l.kind == .opaque
        }
        r.addSublayer(f)
        leaves[key] = f
        kinds[key] = l.kind
        return f
      }()
      // The layer's rows count from the top, the system's from the bottom.
      let top = snap(Double(l.y0) / Double(l.h) * height), bottom = snap(Double(l.y1) / Double(l.h) * height)
      let size = CGRect(x: 0, y: 0, width: b - a, height: bottom - top), corner = CGPoint(x: a, y: height - bottom)
      if f.bounds != size {
        f.bounds = size
        f.mask?.bounds = size
      }
      if f.position != corner { f.position = corner }
      if let m = f.mask {
        if f.backgroundColor != inkColor { f.backgroundColor = inkColor }
        if l.painted == painting.pass { m.contents = l.mask }
      } else if l.painted == painting.pass, let s = l.surface {
        Canvas.changed(f, s)
      }
    }
  }
}

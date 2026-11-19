import QuartzCore
import ScreenSaver

// The painting as a macOS screen saver: the same scroll and front as the
// background, in the system's screen saver host (which also shows it over
// the lock screen). One view per screen; they share one Landscape.
@objc(ShanShuiSaverView)
final class SaverView: ScreenSaverView {
  private static let activeViews = NSHashTable<SaverView>.weakObjects()
  private static var started = false
  private let canvas = Canvas()

  override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    prepare()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    prepare()
  }

  private func prepare() {
    // The view shows the painting's own layers.
    layer = canvas.root
    wantsLayer = true
    // The painting has its own clock; the host's is not used.
    animationTimeInterval = 3600
  }

  override var isOpaque: Bool { true }
  override var hasConfigureSheet: Bool { false }
  override var configureSheet: NSWindow? { nil }
  override func draw(_ rect: NSRect) {}

  override func startAnimation() {
    super.startAnimation()
    SaverView.activeViews.add(self)
    // The thumbnail's size before anything is made, or the first strip is
    // made for the whole screen.
    SaverView.thumbnail()
    SaverView.begin()
    SaverView.check()
  }

  override func setFrameSize(_ size: NSSize) {
    super.setFrameSize(size)
    if isPreview, SaverView.activeViews.contains(self) { SaverView.thumbnail() }
  }

  override func stopAnimation() {
    super.stopAnimation()
    SaverView.activeViews.remove(self)
    canvas.clear()
    SaverView.check()
    Landscape.shared.save()
  }

  private static func begin() {
    guard !started else { return }
    started = true
    Landscape.saver = true
    let p = Landscape.shared
    p.onChange = { redraw() }
    p.onFrame = { redraw() }
    p.begin()
    // The host does not always tell its views to stop, and may stay alive
    // after the saver is gone: this is what ends the painting then.
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main) { _ in
      for v in activeViews.allObjects where !v.isPreview { activeViews.remove(v); v.canvas.clear() }
      check()
      p.save()
    }
  }

  /// No view is being shown: the painting freezes.
  private static func check() {
    thumbnail()
    Landscape.shared.covered = activeViews.count == 0
    redraw()
  }

  /// Only the thumbnail in System Settings is shown: strips as small as it.
  /// One not laid out yet has no size, and is not counted.
  private static func thumbnail() {
    let views = activeViews.allObjects
    guard !views.isEmpty, views.allSatisfy(\.isPreview) else { Landscape.shared.preview = nil; return }
    let sizes = views.filter { $0.bounds.width > 0 && $0.bounds.height > 0 }.map { v -> (w: Int, h: Int) in
      let scale = v.window?.backingScaleFactor ?? 2
      return (Int((v.bounds.width * scale).rounded()), Int((v.bounds.height * scale).rounded()))
    }
    Landscape.shared.preview = sizes.max { $0.w * $0.h < $1.w * $1.h } ?? (640, 360)
  }

  private static func redraw() {
    Painting.shared.show(activeViews.allObjects.map { ($0.canvas, $0.bounds.size, Double($0.window?.backingScaleFactor ?? 2), true) })
  }
}

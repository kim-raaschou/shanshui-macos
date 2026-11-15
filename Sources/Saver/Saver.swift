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
    SaverView.begin()
    SaverView.check()
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
    Landscape.shared.covered = activeViews.count == 0
    redraw()
  }

  private static func redraw() {
    Painting.shared.show(activeViews.allObjects.map { ($0.canvas, $0.bounds.size, Double($0.window?.backingScaleFactor ?? 2), true) })
  }
}

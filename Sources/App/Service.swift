import AppKit
import QuartzCore

// Service.qml of the original: one window per monitor at the desktop's level:
// above the wallpaper, below the desktop's icons and every window. It takes no
// click, so what is underneath keeps answering. Turning off only hides the
// window; the wallpaper is never touched.
final class Service {
  final class PaintingView: NSView {
    let canvas = Canvas()
    override var isOpaque: Bool { true }
  }

  private var windows: [(window: NSWindow, view: PaintingView)] = []

  init() {
    let nc = NotificationCenter.default
    nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [unowned self] _ in
      Landscape.shared.measureScreen()
      build()
    }
    nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [unowned self] _ in
      check()
    }
    build()
  }

  private func build() {
    let screens = NSScreen.screens
    // As many screens as windows: the windows stay, placed again. The
    // notification also comes for the Dock, the menu bar and waking up.
    if screens.count == windows.count {
      for (j, screen) in zip(windows, screens) where j.window.frame != screen.frame { j.window.setFrame(screen.frame, display: false) }
      update()
      return
    }
    // The old windows go with their layers, or they keep the tiles they show.
    for j in windows {
      j.view.canvas.clear()
      j.window.orderOut(nil)
      j.window.contentView = nil
      j.window.close()
    }
    windows = screens.map { screen in
      let j = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
      j.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
      j.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
      j.ignoresMouseEvents = true
      // Opaque: the system need not draw the wallpaper underneath.
      j.isOpaque = true
      j.backgroundColor = .black
      j.hasShadow = false
      j.isReleasedWhenClosed = false
      j.animationBehavior = .none
      j.setAccessibilityElement(false)
      let v = PaintingView(frame: CGRect(origin: .zero, size: screen.frame.size))
      // The view shows the painting's own layers.
      v.layer = v.canvas.root
      v.wantsLayer = true
      j.contentView = v
      j.setFrame(screen.frame, display: false)
      return (j, v)
    }
    update()
  }

  /// Nobody sees any of the windows: the painting freezes.
  private func check() {
    let before = Landscape.shared.covered
    Landscape.shared.covered = !windows.contains { $0.window.occlusionState.contains(.visible) }
    if before != Landscape.shared.covered { redraw() }
  }

  /// Something changed: shows or hides the windows and paints them.
  func update() {
    let p = Landscape.shared
    for j in windows where p.active != j.window.isVisible {
      if p.active { j.window.orderFrontRegardless() } else { j.window.orderOut(nil) }
    }
    check()
    redraw()
  }

  func redraw() {
    // Turned off or covered, nothing is kept painted.
    let active = Landscape.shared.active
    Painting.shared.show(windows.map {
      ($0.view.canvas, $0.view.bounds.size, Double($0.window.backingScaleFactor), active && $0.window.occlusionState.contains(.visible))
    })
  }
}

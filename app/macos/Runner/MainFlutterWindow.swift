import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The Xiangqi board is tall (10 ranks) and the analysis table stacks
    // below it, so open with a portrait-friendly window large enough to show
    // a comfortably sized board. Clamp to the visible screen area and center.
    var windowFrame = self.frame
    let desired = NSSize(width: 760, height: 1040)
    if let visible = NSScreen.main?.visibleFrame {
      let size = NSSize(
        width: min(desired.width, visible.width),
        height: min(desired.height, visible.height))
      let origin = NSPoint(
        x: visible.midX - size.width / 2,
        y: visible.midY - size.height / 2)
      windowFrame = NSRect(origin: origin, size: size)
    }
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

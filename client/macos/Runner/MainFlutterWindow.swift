import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // unifiedCompact tells the OS to create a combined titlebar+toolbar
    // zone of compact height (~38px) and to vertically centre the traffic
    // lights within that zone — so no Y position is hardcoded anywhere.
    let toolbar = NSToolbar(identifier: "ZeroSSHToolbar")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unifiedCompact
    }

    // Flutter content extends into the toolbar area.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // Expose the actual right edge of the traffic-light buttons to Flutter
    // so the tab bar can reserve exactly the right amount of space —
    // no hardcoded pixel value on the Dart side.
    let channel = FlutterMethodChannel(
      name: "com.zerossh/window_chrome",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError()); return }
      switch call.method {
      case "trafficLightInset":
        // Right edge of the zoom button + a comfortable gap.
        if let zoom = self.standardWindowButton(.zoomButton) {
          // convert to window coordinates (buttons live in the titlebar view)
          let inWindow = zoom.convert(zoom.bounds, to: nil)
          result(Double(inWindow.maxX) + 8.0)
        } else {
          result(72.0)   // should never happen; safe fallback
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

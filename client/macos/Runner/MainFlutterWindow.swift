import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Keep the titlebar unified with the Flutter content area, but do not
    // attach an NSToolbar. A toolbar without a delegate causes continuous
    // layout validation on macOS and high idle CPU usage.
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
        // Right edge of the zoom button + a small gap.
        if let zoom = self.standardWindowButton(.zoomButton) {
          let inWindow = zoom.convert(zoom.bounds, to: nil)
          result(Double(inWindow.maxX) + 8.0)
        } else {
          result(72.0)
        }

      case "titlebarHeight":
        // Actual height of the native titlebar — use this as the Flutter
        // top-bar height so the traffic lights land exactly at center.
        let h = self.frame.height - self.contentLayoutRect.height
        result(Double(h))

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

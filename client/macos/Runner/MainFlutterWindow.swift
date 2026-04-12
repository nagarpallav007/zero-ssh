import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Unified transparent titlebar — Flutter draws edge-to-edge.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // Empty toolbar with .unifiedCompact style merges the titlebar and toolbar
    // into a single ~38px zone, vertically centering the traffic-light buttons.
    // The delegate returns empty item arrays immediately — no validation loop,
    // no idle CPU cost.
    let toolbar = NSToolbar(identifier: "main")
    toolbar.delegate = self
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unifiedCompact
    }

    // Expose the actual right edge of the traffic-light buttons to Flutter
    // so the tab bar can reserve exactly the right amount of horizontal space.
    let channel = FlutterMethodChannel(
      name: "com.zerossh/window_chrome",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError()); return }
      switch call.method {

      case "trafficLightInset":
        if let zoom = self.standardWindowButton(.zoomButton) {
          let inWindow = zoom.convert(zoom.bounds, to: nil)
          result(Double(inWindow.maxX) + 8.0)
        } else {
          result(72.0)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

// MARK: - NSToolbarDelegate

extension MainFlutterWindow: NSToolbarDelegate {
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
}

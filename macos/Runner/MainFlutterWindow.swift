import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var channel: FlutterMethodChannel?

  override func awakeFromNib() {
    configureFlutter()
    super.awakeFromNib()
  }

  func configureFlutter() {
    let controller = FlutterViewController()
    contentViewController = controller
    setContentSize(NSSize(width: 760, height: 500))
    minSize = NSSize(width: 500, height: 360)
    center()
    title = "轻贴"
    isReleasedWhenClosed = false
    delegate = self
    #if !LAN_CLIP_STANDALONE
    RegisterGeneratedPlugins(registry: controller)
    #endif
    channel = FlutterMethodChannel(name: "lan_clip/native", binaryMessenger: controller.engine.binaryMessenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "supportDirectory":
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        result(base.appendingPathComponent("dev.lanclip.lan_clip").path)
      case "writeImage":
        guard let data = call.arguments as? FlutterStandardTypedData,
              data.data.count <= 20 * 1024 * 1024,
              let image = NSImage(data: data.data), image.isValid else {
          result(FlutterError(code: "image", message: "图片无法解码", details: nil)); return
        }
        // Provide both PNG and TIFF so chat apps and document editors can paste.
        guard let tiff = image.tiffRepresentation else {
          result(FlutterError(code: "image", message: "图片无法转换", details: nil)); return
        }
        let item = NSPasteboardItem()
        item.setData(data.data, forType: .png)
        item.setData(tiff, forType: .tiff)
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([item]) { result(nil) }
        else { result(FlutterError(code: "clipboard", message: "剪贴板暂时不可用", details: nil)) }
      case "hide":
        self?.orderOut(nil); result(nil)
      case "quit":
        result(nil); NSApp.terminate(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}

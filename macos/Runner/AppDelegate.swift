import Cocoa
import FlutterMacOS

#if !LAN_CLIP_STANDALONE
@main
#endif
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?
  private var activity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let icon = NSImage(named: "StatusIcon")
      ?? Bundle.main.url(forResource: "StatusIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
      ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "轻贴")
    icon?.isTemplate = true
    icon?.size = NSSize(width: 16, height: 18)
    statusItem?.button?.image = icon
    statusItem?.button?.setAccessibilityLabel("轻贴")
    statusItem?.button?.toolTip = "轻贴"
    let menu = NSMenu()
    let open = menu.addItem(withTitle: "打开轻贴", action: #selector(showMainWindow), keyEquivalent: "")
    open.target = self
    menu.addItem(.separator())
    let quit = menu.addItem(withTitle: "退出轻贴", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    statusItem?.menu = menu
    activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
      reason: "接收手机发来的剪贴板内容")
  }
  @objc private func showMainWindow() {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func quitApp() { NSApp.terminate(nil) }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showMainWindow(); return true
  }
  override func applicationWillTerminate(_ notification: Notification) {
    if let activity = activity { ProcessInfo.processInfo.endActivity(activity) }
  }
}

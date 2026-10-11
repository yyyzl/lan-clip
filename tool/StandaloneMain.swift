// Local development launcher for Macs with Command Line Tools but no full Xcode.
// Shares the real native clipboard and menu-bar implementation with the Xcode app.
import Cocoa
import FlutterMacOS

@main
struct StandaloneMain {
  static func main() {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.configureFlutter()
    delegate.mainFlutterWindow = window
    application.delegate = delegate
    let menuBar = NSMenu()
    let appItem = NSMenuItem()
    menuBar.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "退出轻贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let editItem = NSMenuItem()
    menuBar.addItem(editItem)
    let editMenu = NSMenu(title: "编辑")
    editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    application.mainMenu = menuBar
    delegate.applicationMenu = appMenu
    window.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
    withExtendedLifetime(delegate) { withExtendedLifetime(window) { application.run() } }
  }
}

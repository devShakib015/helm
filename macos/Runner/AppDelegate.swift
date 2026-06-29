import Carbon
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Request notification permission once the app has fully launched — doing
    // this during window construction can suppress the system prompt.
    HelmNotifier.shared.requestAuthorization()

    // When macOS auto-launches Helm at login, start quietly in the menu bar:
    // no window, no Dock icon. Manual launches open the window as usual.
    if wasLaunchedAsLoginItem() {
      HelmSystem.shared.startHiddenInMenuBar()
    }
  }

  // Stay alive in the menu bar after the window closes (when resident). The
  // user quits via the menu-bar "Quit Helm" or Cmd-Q.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !HelmSystem.shared.resident
  }

  // Re-open (and reveal) the main window when the user clicks the Dock icon or
  // launches the app again.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    MainFlutterWindow.shared?.makeKeyAndOrderFront(nil)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// True when this launch was triggered by the login-items mechanism (which is
  /// how SMAppService registers Helm), detected via the Apple Event that
  /// accompanies launch.
  private func wasLaunchedAsLoginItem() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent,
          event.eventID == kAEOpenApplication else { return false }
    return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
      == keyAELaunchedAsLogInItem
  }
}

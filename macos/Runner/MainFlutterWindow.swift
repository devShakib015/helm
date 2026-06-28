import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Premium default + minimum window size.
    self.setContentSize(NSSize(width: 1200, height: 800))
    self.minSize = NSSize(width: 980, height: 660)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Native bridge: Trash + accurate volume capacity.
    let channel = FlutterMethodChannel(
      name: "helm/native",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { (call, result) in
      HelmNative.handle(call, result: result)
    }

    super.awakeFromNib()
  }
}

/// Native implementations the Dart side can't do safely or accurately:
///  • `moveToTrash` — recoverable removal via FileManager.
///  • `volumeInfo`  — capacity incl. purgeable space (matches "About This Mac").
enum HelmNative {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "moveToTrash":
      moveToTrash(call, result: result)
    case "volumeInfo":
      volumeInfo(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func moveToTrash(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String] else {
      result(FlutterError(code: "bad_args", message: "paths required", details: nil))
      return
    }
    let fm = FileManager.default
    var trashed: [String] = []
    var failed: [String] = []
    for path in paths {
      let url = URL(fileURLWithPath: path)
      do {
        try fm.trashItem(at: url, resultingItemURL: nil)
        trashed.append(path)
      } catch {
        failed.append(path)
      }
    }
    result(["trashed": trashed, "failed": failed])
  }

  private static func volumeInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let path = (args?["path"] as? String) ?? "/"
    let url = URL(fileURLWithPath: path)
    let keys: Set<URLResourceKey> = [
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeNameKey,
      .volumeIsInternalKey,
      .volumeLocalizedFormatDescriptionKey,
    ]
    do {
      let v = try url.resourceValues(forKeys: keys)
      let total = v.volumeTotalCapacity ?? 0
      let available = v.volumeAvailableCapacity ?? 0
      let important = v.volumeAvailableCapacityForImportantUsage.map { Int($0) } ?? available
      var map: [String: Any] = [
        "total": total,
        "available": available,
        "importantAvailable": important,
        "name": v.volumeName ?? "Macintosh HD",
        "internal": v.volumeIsInternal ?? true,
      ]
      if let fs = v.volumeLocalizedFormatDescription {
        map["fileSystem"] = fs
      }
      result(map)
    } catch {
      result(nil)
    }
  }
}

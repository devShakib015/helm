import Carbon.HIToolbox
import Cocoa
import Darwin
import FlutterMacOS
import ImageIO
import IOKit
import IOKit.ps
import ServiceManagement
import UserNotifications

class MainFlutterWindow: NSWindow {
  static weak var shared: MainFlutterWindow?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.setContentSize(NSSize(width: 1200, height: 800))
    self.minSize = NSSize(width: 940, height: 620)
    // Keep the window freely resizable and zoomable even with the transparent,
    // full-size title bar.
    self.styleMask.insert([.resizable, .miniaturizable, .closable])
    self.collectionBehavior.insert(.fullScreenPrimary)
    self.center()
    MainFlutterWindow.shared = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger

    let nativeChannel = FlutterMethodChannel(
      name: "helm/native", binaryMessenger: messenger)
    nativeChannel.setMethodCallHandler { (call, result) in
      HelmNative.handle(call, result: result)
    }

    let sysChannel = FlutterMethodChannel(
      name: "helm/system", binaryMessenger: messenger)
    HelmSystem.shared.channel = sysChannel
    sysChannel.setMethodCallHandler { (call, result) in
      HelmSystem.shared.handle(call, result: result)
    }

    super.awakeFromNib()
  }
}

// MARK: - Trash + volume capacity

enum HelmNative {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "moveToTrash": moveToTrash(call, result: result)
    case "volumeInfo": volumeInfo(call, result: result)
    default: result(FlutterMethodNotImplemented)
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
      do {
        try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
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
      .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey,
      .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey,
    ]
    do {
      let v = try url.resourceValues(forKeys: keys)
      let total = v.volumeTotalCapacity ?? 0
      let available = v.volumeAvailableCapacity ?? 0
      let important = v.volumeAvailableCapacityForImportantUsage.map { Int($0) } ?? available
      var map: [String: Any] = [
        "total": total, "available": available, "importantAvailable": important,
        "name": v.volumeName ?? "Macintosh HD",
        "internal": v.volumeIsInternal ?? true,
      ]
      if let fs = v.volumeLocalizedFormatDescription { map["fileSystem"] = fs }
      result(map)
    } catch {
      result(nil)
    }
  }
}

// MARK: - System stats, menu bar, clipboard, login item

final class HelmSystem: NSObject {
  static let shared = HelmSystem()
  var channel: FlutterMethodChannel?

  /// Whether the app stays alive (in the menu bar) after the window closes.
  var resident = true

  private var statusItem: NSStatusItem?
  private var clipTexts: [String] = []
  private var clipIds: [String] = []
  private var caffeineActive = false
  private var prevCPUTicks: [[UInt32]] = []
  private var prevNetIn: UInt64 = 0
  private var prevNetOut: UInt64 = 0
  private var prevNetTime: CFAbsoluteTime = 0

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "systemStats":
      result(systemStats())
    case "pbChangeCount":
      result(NSPasteboard.general.changeCount)
    case "pbReadText":
      result(NSPasteboard.general.string(forType: .string))
    case "pbConcealed":
      let types = NSPasteboard.general.types ?? []
      let concealed = types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        || types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
      result(concealed)
    case "pbWriteText":
      if let s = args?["text"] as? String {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        result(true)
      } else { result(false) }
    case "pbRead":
      pbRead(result) // may answer asynchronously (image encode off-main)
    case "pbWriteFiles":
      if let paths = args?["paths"] as? [String], !paths.isEmpty {
        let pb = NSPasteboard.general
        pb.clearContents()
        let urls = paths.map { NSURL(fileURLWithPath: $0) }
        result(pb.writeObjects(urls))
      } else { result(false) }
    case "pbWriteImage":
      if let path = args?["path"] as? String,
         let data = FileManager.default.contents(atPath: path),
         let img = NSImage(data: data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        result(pb.writeObjects([img]))
      } else { result(false) }
    case "pbWriteImageData":
      if let typed = args?["data"] as? FlutterStandardTypedData,
         let img = NSImage(data: typed.data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        result(pb.writeObjects([img]))
      } else { result(false) }
    case "notify":
      HelmNotifier.shared.post(
        title: (args?["title"] as? String) ?? "Helm",
        body: (args?["body"] as? String) ?? "",
        sound: (args?["sound"] as? Bool) ?? false,
        tool: args?["tool"] as? String)
      result(nil)
    case "setClipHotkey":
      if (args?["enabled"] as? Bool) ?? false,
         let key = args?["keyCode"] as? Int,
         let mods = args?["modifiers"] as? Int {
        HelmHotKey.shared.onFire = { [weak self] in self?.showClipPopup() }
        HelmHotKey.shared.register(keyCode: UInt32(key), modifiers: UInt32(mods))
      } else {
        HelmHotKey.shared.unregister()
      }
      result(nil)
    case "simulatePaste":
      simulatePaste()
      result(nil)
    case "axTrusted":
      result(AXIsProcessTrusted())
    case "sampleColor":
      sampleColor { hex in result(hex) }
    case "menuBarUpdate":
      updateMenuBar(args)
      result(nil)
    case "menuBarSetVisible":
      setMenuBarVisible((args?["visible"] as? Bool) ?? true)
      result(nil)
    case "setResident":
      resident = (args?["resident"] as? Bool) ?? true
      result(nil)
    case "setLaunchAtLogin":
      result(setLaunchAtLogin((args?["enabled"] as? Bool) ?? false))
    case "getLaunchAtLogin":
      result(getLaunchAtLogin())
    case "showWindow":
      showWindow()
      result(nil)
    case "zoomWindow":
      MainFlutterWindow.shared?.zoom(nil)
      result(nil)
    case "relaunchApp":
      relaunchApp()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Stats

  private func systemStats() -> [String: Any] {
    let cpu = cpuUsage()
    let mem = memory()
    let net = netRates()
    let disk = diskCapacity()
    let temps = tempReading()
    let bat = batteryInfo()
    return [
      "cpu": cpu.total,
      "cpuPerCore": cpu.perCore,
      "gpu": gpuUsage(),
      "memUsed": Int(mem.used),
      "memTotal": Int(mem.total),
      "netDown": net.down,
      "netUp": net.up,
      "diskTotal": Int(disk.total),
      "diskFree": Int(disk.free),
      "uptime": uptimeSeconds(),
      "tempCpu": temps.cpu as Any,
      "tempGpu": temps.gpu as Any,
      "fan": temps.fan as Any,
      "batteryPct": bat.pct as Any,
      "batteryCharging": bat.charging,
    ]
  }

  /// Battery charge via IOKit power sources. Returns (nil, false) on desktops
  /// or any read failure.
  private func batteryInfo() -> (pct: Int?, charging: Bool) {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
    else { return (nil, false) }
    for ps in list {
      guard let desc = IOPSGetPowerSourceDescription(blob, ps)?
        .takeUnretainedValue() as? [String: Any] else { continue }
      let cur = desc[kIOPSCurrentCapacityKey as String] as? Int
      let mx = desc[kIOPSMaxCapacityKey as String] as? Int
      let state = desc[kIOPSPowerSourceStateKey as String] as? String
      if let cur = cur, let mx = mx, mx > 0 {
        let pct = Int((Double(cur) / Double(mx) * 100).rounded())
        return (pct, state == (kIOPSACPowerValue as String))
      }
    }
    return (nil, false)
  }

  /// Best-effort SMC reading (Apple Silicon). Returns nils on any failure.
  private func tempReading() -> (cpu: Double?, gpu: Double?, fan: Double?) {
    return HelmSMC.shared.read()
  }

  private func cpuUsage() -> (total: Double, perCore: [Double]) {
    var count = mach_msg_type_number_t(0)
    var info: processor_info_array_t?
    var numCPUs = natural_t(0)
    let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &count)
    guard kr == KERN_SUCCESS, let info = info else { return (0, []) }
    defer {
      vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                    vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
    }
    let n = Int(numCPUs)
    var perCore: [Double] = []
    var cur: [[UInt32]] = []
    var busyDelta = 0.0
    var totalDelta = 0.0
    let havePrev = prevCPUTicks.count == n
    for i in 0..<n {
      let base = i * Int(CPU_STATE_MAX)
      let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
      let sys = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
      let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
      let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
      cur.append([user, sys, idle, nice])
      if havePrev {
        let p = prevCPUTicks[i]
        let du = Double(user &- p[0]), ds = Double(sys &- p[1])
        let di = Double(idle &- p[2]), dn = Double(nice &- p[3])
        let busy = du + ds + dn
        let tot = busy + di
        perCore.append(tot > 0 ? busy / tot * 100.0 : 0)
        busyDelta += busy
        totalDelta += tot
      } else {
        perCore.append(0)
      }
    }
    prevCPUTicks = cur
    let total = totalDelta > 0 ? busyDelta / totalDelta * 100.0 : 0
    return (total, perCore)
  }

  private func gpuUsage() -> Double {
    var iterator = io_iterator_t()
    guard IOServiceGetMatchingServices(
      kIOMasterPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    else { return 0 }
    defer { IOObjectRelease(iterator) }
    var service = IOIteratorNext(iterator)
    var best = 0.0
    while service != 0 {
      var props: Unmanaged<CFMutableDictionary>?
      if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
         let dict = props?.takeRetainedValue() as? [String: Any],
         let perf = dict["PerformanceStatistics"] as? [String: Any] {
        if let u = perf["Device Utilization %"] as? Int { best = max(best, Double(u)) }
        else if let u = perf["Device Utilization %"] as? Double { best = max(best, u) }
      }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
    return best
  }

  private func memory() -> (used: UInt64, total: UInt64) {
    var total: UInt64 = 0
    var len = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &total, &len, nil, 0)

    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let page = UInt64(pageSize)

    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard kr == KERN_SUCCESS else { return (0, total) }
    let wired = UInt64(stats.wire_count) * page
    let compressed = UInt64(stats.compressor_page_count) * page
    let anon = UInt64(stats.internal_page_count)
    let purgeable = UInt64(stats.purgeable_count)
    let app = (anon > purgeable ? anon - purgeable : 0) * page
    let used = wired + compressed + app
    return (min(used, total), total)
  }

  private func netRates() -> (down: Double, up: Double) {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0 else { return (0, 0) }
    defer { freeifaddrs(addrs) }
    var inB: UInt64 = 0
    var outB: UInt64 = 0
    var p = addrs
    while let cur = p {
      if let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) {
        let name = String(cString: cur.pointee.ifa_name)
        if name.hasPrefix("en") {
          if let d = cur.pointee.ifa_data {
            let data = d.assumingMemoryBound(to: if_data.self).pointee
            inB += UInt64(data.ifi_ibytes)
            outB += UInt64(data.ifi_obytes)
          }
        }
      }
      p = cur.pointee.ifa_next
    }
    let now = CFAbsoluteTimeGetCurrent()
    var down = 0.0
    var up = 0.0
    if prevNetTime > 0 {
      let dt = now - prevNetTime
      if dt > 0 {
        down = Double(inB &- prevNetIn) / dt
        up = Double(outB &- prevNetOut) / dt
      }
    }
    prevNetIn = inB
    prevNetOut = outB
    prevNetTime = now
    return (max(0, down), max(0, up))
  }

  private func diskCapacity() -> (total: UInt64, free: UInt64) {
    let url = URL(fileURLWithPath: "/")
    if let v = try? url.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
      .volumeAvailableCapacityKey,
    ]) {
      let total = UInt64(v.volumeTotalCapacity ?? 0)
      let free = UInt64(v.volumeAvailableCapacityForImportantUsage
        ?? Int64(v.volumeAvailableCapacity ?? 0))
      return (total, free)
    }
    return (0, 0)
  }

  private func uptimeSeconds() -> Double {
    var boottime = timeval()
    var size = MemoryLayout<timeval>.size
    var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
    if sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 {
      return Date().timeIntervalSince1970 - Double(boottime.tv_sec)
    }
    return 0
  }

  // MARK: Pasteboard (multi-type)

  /// Largest image the history will persist in full (larger ones keep only a
  /// thumbnail and can't be copied back). Applied to the ENCODED PNG — what
  /// is actually stored — never to raw TIFF pasteboard bytes.
  private static let maxStoredImageBytes = 24 * 1024 * 1024
  /// Refuse to even decode absurdly large pasteboard image payloads.
  private static let maxDecodedSourceBytes = 256 * 1024 * 1024
  /// Text is capped so a runaway copy (log dump, generated SQL…) can't bloat
  /// the history file.
  private static let maxTextChars = 1_000_000

  /// Reads the pasteboard's richest representation, in priority order:
  /// 1. **File URLs** (Finder copies) — stored as references ONLY. A 4 GB
  ///    movie stays a path; its bytes are never read.
  /// 2. **Image data** — bounded full PNG + a small thumbnail for the UI.
  ///    Decode/encode runs OFF the main thread (it can take seconds for big
  ///    pictures) and the result is delivered asynchronously.
  /// 3. **Plain text** — length-capped.
  private func pbRead(_ result: @escaping FlutterResult) {
    let pb = NSPasteboard.general
    var out: [String: Any] = ["change": pb.changeCount]

    // 1. Files: references only, never contents.
    if let urls = pb.readObjects(
         forClasses: [NSURL.self],
         options: [.urlReadingFileURLsOnly: true]) as? [URL],
       !urls.isEmpty {
      var total = 0
      let fm = FileManager.default
      for u in urls {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue,
           let attrs = try? fm.attributesOfItem(atPath: u.path),
           let size = attrs[.size] as? Int {
          total += size
        }
      }
      out["kind"] = "file"
      out["paths"] = urls.map { $0.path }
      out["bytes"] = total
      result(out)
      return
    }

    // 2. Images. Snapshot the raw data + a text fallback on the main thread,
    // then decode/encode on a background queue (pure CoreGraphics, so it's
    // thread-safe) and answer async — a big screenshot must never beachball
    // the app from the 800 ms poll.
    let pngSource = pb.data(forType: .png)
    let tiffSource = pngSource == nil ? pb.data(forType: .tiff) : nil
    let textFallback = pb.string(forType: .string)
    if let data = pngSource ?? tiffSource {
      let isPng = pngSource != nil
      DispatchQueue.global(qos: .userInitiated).async {
        var o = out
        let payload = HelmSystem.imagePayload(data: data, isPng: isPng)
        if payload["kind"] as? String == "image" {
          payload.forEach { o[$0] = $1 }
        } else if let s = textFallback {
          HelmSystem.textPayload(s).forEach { o[$0] = $1 }
        } else {
          o["kind"] = "none"
        }
        DispatchQueue.main.async { result(o) }
      }
      return
    }

    // 3. Text, capped.
    if let s = pb.string(forType: .string) {
      HelmSystem.textPayload(s).forEach { out[$0] = $1 }
      result(out)
      return
    }

    out["kind"] = "none"
    result(out)
  }

  private static func textPayload(_ s: String) -> [String: Any] {
    let truncated = s.count > maxTextChars
    return [
      "kind": "text",
      "text": truncated ? String(s.prefix(maxTextChars)) : s,
      "truncated": truncated,
    ]
  }

  /// Builds the image fields: full PNG (only when the ENCODED size fits the
  /// cap), a ≤512px thumbnail, true pixel dimensions, and the honest stored
  /// size. Pure CoreGraphics — safe off the main thread.
  private static func imagePayload(data: Data, isPng: Bool) -> [String: Any] {
    var out: [String: Any] = [:]
    guard data.count <= maxDecodedSourceBytes,
          let cg = decodeImage(data) else {
      out["kind"] = "none"
      return out
    }
    out["kind"] = "image"
    out["w"] = cg.width
    out["h"] = cg.height
    // A PNG source is kept byte-for-byte; TIFF (screenshots, Preview copies)
    // is re-encoded first — the cap judges the PNG we'd store, NOT the
    // inflated raw TIFF, so a 31 MB TIFF that's 4 MB as PNG still restores.
    let fullPng: Data? = isPng ? data : encodePng(cg, maxDim: 0)
    out["bytes"] = fullPng?.count ?? data.count
    if let full = fullPng, full.count <= maxStoredImageBytes {
      out["image"] = FlutterStandardTypedData(bytes: full)
    }
    if let thumb = encodePng(cg, maxDim: 512) {
      out["thumb"] = FlutterStandardTypedData(bytes: thumb)
    }
    return out
  }

  private static func decodeImage(_ data: Data) -> CGImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
  }

  /// PNG-encodes a CGImage, optionally downscaled so its longest side is
  /// [maxDim] (0 = keep full size). CoreGraphics only — no AppKit drawing,
  /// so it is safe on a background queue.
  private static func encodePng(_ image: CGImage, maxDim: Int) -> Data? {
    var img = image
    if maxDim > 0, max(image.width, image.height) > maxDim {
      let scale = CGFloat(maxDim) / CGFloat(max(image.width, image.height))
      let w = max(1, Int(CGFloat(image.width) * scale))
      let h = max(1, Int(CGFloat(image.height) * scale))
      guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      ctx.interpolationQuality = .high
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      guard let scaled = ctx.makeImage() else { return nil }
      img = scaled
    }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      out as CFMutableData, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
  }

  // MARK: Menu bar

  private func ensureStatusItem() {
    if statusItem == nil {
      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      statusItem?.menu = NSMenu()
    }
  }

  private func setMenuBarVisible(_ visible: Bool) {
    if visible {
      ensureStatusItem()
    } else if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  private func updateMenuBar(_ args: [String: Any]?) {
    // Clip data is stored unconditionally — the hotkey popup reads it even
    // when the menu bar is hidden. Only the status-item UI below is optional.
    clipTexts = (args?["clips"] as? [String]) ?? []
    clipIds = (args?["clipIds"] as? [String]) ?? []
    caffeineActive = (args?["caffeine"] as? Bool) ?? false
    // Visibility is controlled solely by setMenuBarVisible; don't resurrect
    // a hidden status item here.
    guard let button = statusItem?.button else { return }
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    let segs = (args?["segments"] as? [[String: Any]]) ?? []
    let attr = NSMutableAttributedString()
    for (i, seg) in segs.enumerated() {
      if i > 0 {
        attr.append(NSAttributedString(string: "  ", attributes: [.font: font]))
      }
      let text = seg["text"] as? String ?? ""
      let color = colorFromHex(seg["color"] as? String) ?? NSColor.labelColor
      attr.append(NSAttributedString(
        string: text, attributes: [.font: font, .foregroundColor: color]))
    }
    if attr.length == 0 {
      attr.append(NSAttributedString(string: "Helm", attributes: [.font: font]))
    }
    button.attributedTitle = attr
    rebuildMenu(details: (args?["details"] as? [String]) ?? [])
  }

  private func rebuildMenu(details: [String]) {
    let menu = statusItem?.menu ?? NSMenu()
    menu.removeAllItems()
    for d in details {
      let item = NSMenuItem(title: d, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    if !details.isEmpty { menu.addItem(.separator()) }

    if !clipTexts.isEmpty {
      let header = NSMenuItem(title: "Recent Clipboard", action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      // The dropdown shows the first 8; the hotkey popup gets the full list.
      for (i, text) in clipTexts.prefix(8).enumerated() {
        let item = NSMenuItem(
          title: clipPreview(text), action: #selector(clipClicked(_:)), keyEquivalent: "")
        item.target = self
        // Stable identity, not a positional index — the history can shift
        // (new copies, deletes, re-sorts) between menu display and click.
        if i < clipIds.count { item.representedObject = clipIds[i] }
        menu.addItem(item)
      }
      menu.addItem(.separator())
    }

    // Quick actions
    let caffeine = NSMenuItem(
      title: "Keep Awake", action: #selector(menuToggleCaffeine), keyEquivalent: "")
    caffeine.target = self
    caffeine.state = caffeineActive ? .on : .off
    menu.addItem(caffeine)

    let pick = NSMenuItem(
      title: "Pick Color from Screen", action: #selector(menuPickColor), keyEquivalent: "")
    pick.target = self
    menu.addItem(pick)
    menu.addItem(.separator())

    let open = NSMenuItem(title: "Open Helm", action: #selector(openHelm), keyEquivalent: "o")
    open.target = self
    menu.addItem(open)
    let quit = NSMenuItem(title: "Quit Helm", action: #selector(quitHelm), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    statusItem?.menu = menu
  }

  /// Single-line, truncated preview for a clipboard menu item.
  private func clipPreview(_ s: String) -> String {
    let oneLine = s.replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if oneLine.count > 52 { return String(oneLine.prefix(52)) + "…" }
    return oneLine.isEmpty ? "(empty)" : oneLine
  }

  /// Menu-bar clipboard item clicked → let Dart do the copy-back. Dart owns
  /// the full history (text, images, file references), so it restores the
  /// right representation; a plain-text write here would mangle non-text clips.
  /// Identified by the item's stable id so a shifting list can't mis-target.
  @objc private func clipClicked(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel?.invokeMethod("onClipCopy", arguments: ["id": id, "popup": false])
  }

  /// Global-hotkey quick-paste popup: shows the recent clips (labels + ids the
  /// menu bar already streams) in a floating panel at the cursor.
  private func showClipPopup() {
    HelmClipPopup.shared.onPick = { [weak self] id in
      self?.channel?.invokeMethod("onClipCopy", arguments: ["id": id, "popup": true])
    }
    HelmClipPopup.shared.toggle(labels: clipTexts.map(clipPreview), ids: clipIds)
  }

  /// Posts ⌘V to the frontmost app so a popup pick pastes in place. Requires
  /// the Accessibility grant; without it the events would be dropped, so this
  /// is a no-op when untrusted (the setting's UI explains the requirement).
  private func simulatePaste() {
    guard AXIsProcessTrusted() else { return }
    // Virtual keycodes are POSITIONAL: on Dvorak-style layouts the QWERTY-V
    // position types a different letter, so ⌘+9 would fire a different (maybe
    // destructive) shortcut. Resolve the keycode that types "v" on the ACTIVE
    // layout; fall back to the ANSI position.
    let vKey = HelmSystem.keyCode(for: "v") ?? 9
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      let src = CGEventSource(stateID: .combinedSessionState)
      let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
      down?.flags = .maskCommand
      let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
      up?.flags = .maskCommand
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
    }
  }

  /// The virtual keycode that produces [char] under the current keyboard
  /// layout, or nil when it can't be resolved.
  private static func keyCode(for char: Character) -> CGKeyCode? {
    guard let sourceRef = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let layoutPtr = TISGetInputSourceProperty(sourceRef, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
    return data.withUnsafeBytes { buf -> CGKeyCode? in
      guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress
      else { return nil }
      var deadKeys: UInt32 = 0
      var chars = [UniChar](repeating: 0, count: 4)
      var length = 0
      for code in 0..<128 {
        let err = UCKeyTranslate(
          layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
          UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
          &deadKeys, chars.count, &length, &chars)
        if err == noErr, length > 0,
           let scalar = Unicode.Scalar(chars[0]),
           Character(scalar) == char {
          return CGKeyCode(code)
        }
      }
      return nil
    }
  }

  /// Menu-bar "Keep Awake" toggle — handled by the Dart CaffeineController so
  /// the in-app tool and the menu stay in sync.
  @objc private func menuToggleCaffeine() {
    channel?.invokeMethod("onMenuAction", arguments: "toggleCaffeine")
  }

  /// Menu-bar "Pick Color from Screen" — opens the system eyedropper, copies the
  /// hex to the pasteboard, and tells Dart so the Color Picker records it. The
  /// clipboard watcher then surfaces the usual "Copied" notification.
  @objc private func menuPickColor() {
    sampleColor { [weak self] hex in
      guard let hex = hex else { return }
      let pb = NSPasteboard.general
      pb.clearContents()
      pb.setString(hex, forType: .string)
      self?.channel?.invokeMethod("onColorPicked", arguments: hex)
    }
  }

  /// Shows the system color sampler (loupe) and returns the picked color as a
  /// `#RRGGBB` hex string, or nil if cancelled. Sampling runs in the system's
  /// own process, so no Screen Recording permission is required.
  private func sampleColor(_ completion: @escaping (String?) -> Void) {
    if #available(macOS 10.15, *) {
      NSApp.activate(ignoringOtherApps: true)
      NSColorSampler().show { color in
        guard let color = color, let rgb = color.usingColorSpace(.sRGB) else {
          completion(nil)
          return
        }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        completion(String(format: "#%02X%02X%02X", r, g, b))
      }
    } else {
      completion(nil)
    }
  }

  @objc private func openHelm() { showWindow() }
  @objc private func quitHelm() { NSApp.terminate(nil) }

  private func showWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    MainFlutterWindow.shared?.makeKeyAndOrderFront(nil)
  }

  /// A notification was clicked: reveal the window and tell Dart which tool
  /// (if any) the notification wants shown.
  func openFromNotification(tool: String?) {
    showWindow()
    if let tool = tool {
      channel?.invokeMethod("onOpenTool", arguments: tool)
    }
  }

  /// Spawns a new instance of Helm and terminates this one. Used after the
  /// user grants Full Disk Access — macOS applies the grant at process launch.
  /// Only terminates once the replacement actually launched; on failure the
  /// current instance stays alive rather than stranding the user with nothing.
  private func relaunchApp() {
    let url = Bundle.main.bundleURL
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
      DispatchQueue.main.async {
        if app != nil { NSApp.terminate(nil) }
      }
    }
  }

  /// Starts the app quietly when launched at login: menu bar only — no window,
  /// no Dock icon. The window appears later if the user chooses "Open Helm".
  func startHiddenInMenuBar() {
    NSApp.setActivationPolicy(.accessory)
    ensureStatusItem()
    MainFlutterWindow.shared?.orderOut(nil)
  }

  // MARK: Login item

  private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
    if #available(macOS 13.0, *) {
      do {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
        return true
      } catch {
        return false
      }
    }
    return false
  }

  private func getLaunchAtLogin() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return false
  }

  private func colorFromHex(_ hex: String?) -> NSColor? {
    guard var h = hex else { return nil }
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
    return NSColor(
      red: CGFloat((v >> 16) & 0xFF) / 255.0,
      green: CGFloat((v >> 8) & 0xFF) / 255.0,
      blue: CGFloat(v & 0xFF) / 255.0,
      alpha: 1.0)
  }
}

// MARK: - SMC (temperatures & fans, Apple Silicon)

/// Reads Apple SMC sensor keys using a fixed 80-byte command buffer with
/// explicit field offsets — avoids Swift/C struct-layout mismatches. Read-only,
/// works on a non-sandboxed app without root, and returns nil on any failure.
final class HelmSMC {
  static let shared = HelmSMC()

  private var conn: io_connect_t = 0
  private var opened = false
  private var enumerated = false
  private var tempKeys: [(key: UInt32, type: UInt32, size: Int)] = []
  private var fanKey: (key: UInt32, type: UInt32, size: Int)?

  private static let structSize = 80
  private static let cmdRead: UInt8 = 5
  private static let cmdFromIndex: UInt8 = 8
  private static let cmdKeyInfo: UInt8 = 9
  private static let selector: UInt32 = 2

  func read() -> (cpu: Double?, gpu: Double?, fan: Double?) {
    guard open() else {
      return (nil, nil, nil)
    }
    if !enumerated {
      enumerate()
      enumerated = true
    }
    var cpuCore: [Double] = [] // Tp* / Te* — actual CPU die
    var gpu: [Double] = [] // Tg*
    var sane: [Double] = [] // plausible temps, used as a fallback
    for k in tempKeys {
      guard let v = value(k.key, k.type, k.size), v > 10, v < 110 else { continue }
      let name = string(k.key)
      if name.hasPrefix("Tg") {
        gpu.append(v)
      } else if name.hasPrefix("Tp") || name.hasPrefix("Te") {
        cpuCore.append(v)
      }
      if v > 20, v < 100 { sane.append(v) }
    }
    let cpuVals = cpuCore.isEmpty ? sane : cpuCore
    var fan: Double?
    if let f = fanKey, let v = value(f.key, f.type, f.size), v >= 0, v < 12000 {
      fan = v
    }
    return (
      cpuVals.isEmpty ? nil : cpuVals.reduce(0, +) / Double(cpuVals.count),
      gpu.isEmpty ? nil : gpu.reduce(0, +) / Double(gpu.count),
      fan
    )
  }

  private func open() -> Bool {
    if opened { return conn != 0 }
    opened = true
    let service = IOServiceGetMatchingService(
      kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
    guard service != 0 else { return false }
    let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
    IOObjectRelease(service)
    return kr == KERN_SUCCESS
  }

  /// One SMC transaction → the 80-byte output buffer (nil if result != 0).
  private func transact(key: UInt32, cmd: UInt8, data32: UInt32 = 0, dataSize: UInt32 = 0) -> [UInt8]? {
    var input = [UInt8](repeating: 0, count: HelmSMC.structSize)
    putLE32(&input, 0, key) // key
    putLE32(&input, 28, dataSize) // keyInfo.dataSize
    input[42] = cmd // data8 (command)
    putLE32(&input, 44, data32) // data32
    var output = [UInt8](repeating: 0, count: HelmSMC.structSize)
    var outSize = HelmSMC.structSize
    let kr = input.withUnsafeBytes { inPtr in
      output.withUnsafeMutableBytes { outPtr in
        IOConnectCallStructMethod(
          conn, HelmSMC.selector,
          inPtr.baseAddress, HelmSMC.structSize,
          outPtr.baseAddress, &outSize)
      }
    }
    guard kr == KERN_SUCCESS, output[40] == 0 else { return nil }
    return output
  }

  private func info(_ key: UInt32) -> (type: UInt32, size: Int)? {
    guard let out = transact(key: key, cmd: HelmSMC.cmdKeyInfo) else { return nil }
    return (getLE32(out, 32), Int(getLE32(out, 28)))
  }

  private func bytes(_ key: UInt32, _ size: Int) -> [UInt8]? {
    guard size > 0, let out = transact(key: key, cmd: HelmSMC.cmdRead, dataSize: UInt32(size))
    else { return nil }
    let n = min(size, 32)
    return Array(out[48..<48 + n])
  }

  private func keyCount() -> Int {
    let key = fourCC("#KEY")
    guard let i = info(key), let b = bytes(key, i.size), b.count >= 4 else { return 0 }
    return Int(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
  }

  private func keyAt(_ index: Int) -> UInt32 {
    guard let out = transact(key: 0, cmd: HelmSMC.cmdFromIndex, data32: UInt32(index))
    else { return 0 }
    return getLE32(out, 0)
  }

  private func enumerate() {
    let count = keyCount()
    if count <= 0 || count > 5000 { return }
    for i in 0..<count {
      let key = keyAt(i)
      if key == 0 { continue }
      guard let inf = info(key) else { continue }
      let name = string(key)
      let type = string(inf.type)
      if name.hasPrefix("T") && (type == "flt " || type == "sp78") {
        tempKeys.append((key, inf.type, inf.size))
      } else if name == "F0Ac" && (type == "flt " || type == "fpe2") {
        fanKey = (key, inf.type, inf.size)
      }
    }
  }

  private func value(_ key: UInt32, _ type: UInt32, _ size: Int) -> Double? {
    guard let b = bytes(key, size), b.count >= 2 else { return nil }
    switch string(type) {
    case "flt ":
      guard b.count >= 4 else { return nil }
      let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
      return Double(Float(bitPattern: bits))
    case "sp78":
      let raw = Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))
      return Double(raw) / 256.0
    case "fpe2":
      return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4.0
    default:
      return nil
    }
  }

  private func putLE32(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
    buf[off] = UInt8(v & 0xFF)
    buf[off + 1] = UInt8((v >> 8) & 0xFF)
    buf[off + 2] = UInt8((v >> 16) & 0xFF)
    buf[off + 3] = UInt8((v >> 24) & 0xFF)
  }

  private func getLE32(_ buf: [UInt8], _ off: Int) -> UInt32 {
    return UInt32(buf[off]) | UInt32(buf[off + 1]) << 8
      | UInt32(buf[off + 2]) << 16 | UInt32(buf[off + 3]) << 24
  }

  private func fourCC(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for c in s.utf8 { r = (r << 8) | UInt32(c) }
    return r
  }

  private func string(_ code: UInt32) -> String {
    let b = [
      UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
    ]
    return String(bytes: b, encoding: .ascii) ?? ""
  }
}

// MARK: - Global hotkey (Carbon — needs no special permissions)

/// Registers a system-wide hotkey via Carbon's RegisterEventHotKey, which —
/// unlike NSEvent global monitors — works without Accessibility or Input
/// Monitoring grants.
final class HelmHotKey {
  static let shared = HelmHotKey()
  var onFire: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  func register(keyCode: UInt32, modifiers: UInt32) {
    unregister()
    if handlerRef == nil {
      var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed))
      InstallEventHandler(
        GetApplicationEventTarget(),
        { _, _, userData -> OSStatus in
          guard let userData = userData else { return noErr }
          Unmanaged<HelmHotKey>.fromOpaque(userData).takeUnretainedValue()
            .onFire?()
          return noErr
        },
        1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
    let hkID = EventHotKeyID(signature: 0x48454C4D, id: 1) // 'HELM'
    RegisterEventHotKey(
      keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
  }

  func unregister() {
    if let ref = hotKeyRef {
      UnregisterEventHotKey(ref)
      hotKeyRef = nil
    }
  }
}

// MARK: - Quick-paste popup

/// Borderless floating panel at the cursor listing recent clips.
/// ↑/↓ moves the selection, ⏎ picks, esc closes, 1–9 quick-picks, and a click
/// picks. Non-activating, so the frontmost app keeps focus and an auto-paste
/// lands in the right place.
final class HelmClipPopup: NSPanel, NSWindowDelegate {
  static let shared = HelmClipPopup()

  var onPick: ((String) -> Void)?

  private var labels: [String] = []
  private var ids: [String] = []
  private var selectedIndex = 0
  private var rowViews: [NSView] = []

  private static let rowHeight: CGFloat = 30
  private static let panelWidth: CGFloat = 380

  private init() {
    super.init(
      contentRect: .zero,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered, defer: true)
    isFloatingPanel = true
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .transient]
    isOpaque = false
    backgroundColor = .clear
    hidesOnDeactivate = false
    delegate = self
  }

  override var canBecomeKey: Bool { true }

  func toggle(labels: [String], ids: [String]) {
    if isVisible {
      hide()
    } else {
      present(labels: labels, ids: ids)
    }
  }

  func hide() { orderOut(nil) }

  func windowDidResignKey(_ notification: Notification) { hide() }

  private func present(labels: [String], ids: [String]) {
    guard !labels.isEmpty, labels.count == ids.count else { return }
    self.labels = labels
    self.ids = ids
    selectedIndex = 0
    buildContent()

    // Position near the mouse, clamped inside the screen under it.
    let mouse = NSEvent.mouseLocation
    let size = frame.size
    var origin = NSPoint(x: mouse.x - 10, y: mouse.y - size.height + 10)
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
    if let vis = screen?.visibleFrame {
      origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - size.width - 8)
      origin.y = min(max(origin.y, vis.minY + 8), vis.maxY - size.height - 8)
    }
    setFrameOrigin(origin)
    makeKeyAndOrderFront(nil)
  }

  private func buildContent() {
    let height = CGFloat(labels.count) * HelmClipPopup.rowHeight + 16
    let root = NSVisualEffectView(
      frame: NSRect(x: 0, y: 0, width: HelmClipPopup.panelWidth, height: height))
    root.material = .menu
    root.state = .active
    root.blendingMode = .behindWindow
    root.wantsLayer = true
    root.layer?.cornerRadius = 12
    root.layer?.masksToBounds = true

    rowViews = []
    for (i, label) in labels.enumerated() {
      let y = height - 8 - CGFloat(i + 1) * HelmClipPopup.rowHeight
      let row = NSView(frame: NSRect(
        x: 6, y: y, width: HelmClipPopup.panelWidth - 12,
        height: HelmClipPopup.rowHeight))
      row.wantsLayer = true
      row.layer?.cornerRadius = 6
      row.identifier = NSUserInterfaceItemIdentifier("\(i)")

      if i < 9 {
        let num = NSTextField(labelWithString: "\(i + 1)")
        num.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        num.textColor = .tertiaryLabelColor
        num.frame = NSRect(x: 9, y: 7, width: 16, height: 16)
        row.addSubview(num)
      }

      let text = NSTextField(labelWithString: label)
      text.font = NSFont.systemFont(ofSize: 12.5)
      text.lineBreakMode = .byTruncatingTail
      text.frame = NSRect(x: 30, y: 6, width: row.bounds.width - 40, height: 18)
      row.addSubview(text)

      row.addGestureRecognizer(
        NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:))))
      root.addSubview(row)
      rowViews.append(row)
    }
    setContentSize(NSSize(width: HelmClipPopup.panelWidth, height: height))
    contentView = root
    highlight()
  }

  private func highlight() {
    for (i, row) in rowViews.enumerated() {
      row.layer?.backgroundColor = i == selectedIndex
        ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        : NSColor.clear.cgColor
    }
  }

  @objc private func rowClicked(_ g: NSClickGestureRecognizer) {
    if let raw = g.view?.identifier?.rawValue, let i = Int(raw) { pick(i) }
  }

  private func pick(_ index: Int) {
    guard index >= 0, index < ids.count else { return }
    let id = ids[index]
    hide()
    onPick?(id)
  }

  override func keyDown(with event: NSEvent) {
    switch Int(event.keyCode) {
    case kVK_Escape:
      hide()
    case kVK_DownArrow:
      selectedIndex = min(selectedIndex + 1, labels.count - 1)
      highlight()
    case kVK_UpArrow:
      selectedIndex = max(selectedIndex - 1, 0)
      highlight()
    case kVK_Return, kVK_ANSI_KeypadEnter:
      pick(selectedIndex)
    default:
      if let chars = event.charactersIgnoringModifiers,
         let d = Int(chars), d >= 1, d <= min(9, labels.count) {
        pick(d - 1)
      }
    }
  }
}

// MARK: - Notifications

/// Posts user notifications, preferring the modern UserNotifications framework
/// and falling back to the (deprecated, but authorization-free) legacy API when
/// the modern center is unauthorized or unavailable. Never throws; a denied or
/// unavailable notifier simply drops the message.
final class HelmNotifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = HelmNotifier()

  /// current() traps when the process has no bundle identifier; guard for it so
  /// this is safe even outside a normal .app bundle.
  private var center: UNUserNotificationCenter? {
    Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
  }

  func requestAuthorization() {
    guard let center = center else { return }
    center.delegate = self
    // Showing the system permission prompt the first time the app runs.
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  /// [tool]: when set, clicking the notification opens Helm on that tool
  /// (e.g. the login-item watchdog routes to "startup").
  func post(title: String, body: String, sound: Bool = false, tool: String? = nil) {
    // Always post through the modern center: the system enforces the user's
    // authorization choice (delivering once granted, dropping silently
    // otherwise) — no need to track the async grant state ourselves.
    if let center = center {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      if sound { content.sound = .default }
      if let tool = tool { content.userInfo = ["tool": tool] }
      center.add(UNNotificationRequest(
        identifier: UUID().uuidString, content: content, trigger: nil))
      return
    }
    // No bundle identifier (e.g. running outside an .app): legacy fallback.
    let n = NSUserNotification()
    n.title = title
    n.informativeText = body
    if sound { n.soundName = NSUserNotificationDefaultSoundName }
    NSUserNotificationCenter.default.deliver(n)
  }

  // Show banners even when Helm itself is frontmost.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  // Clicking a notification opens Helm, routed to the tool it names.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    HelmSystem.shared.openFromNotification(tool: info["tool"] as? String)
    completionHandler()
  }
}

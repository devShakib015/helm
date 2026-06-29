import Cocoa
import Darwin
import FlutterMacOS
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
    case "notify":
      HelmNotifier.shared.post(
        title: (args?["title"] as? String) ?? "Helm",
        body: (args?["body"] as? String) ?? "",
        sound: (args?["sound"] as? Bool) ?? false)
      result(nil)
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
    ensureStatusItem()
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
    clipTexts = (args?["clips"] as? [String]) ?? []
    caffeineActive = (args?["caffeine"] as? Bool) ?? false
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
      for (i, text) in clipTexts.enumerated() {
        let item = NSMenuItem(
          title: clipPreview(text), action: #selector(clipClicked(_:)), keyEquivalent: "")
        item.target = self
        item.tag = i
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

  @objc private func clipClicked(_ sender: NSMenuItem) {
    let i = sender.tag
    guard i >= 0, i < clipTexts.count else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(clipTexts[i], forType: .string)
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

  func post(title: String, body: String, sound: Bool = false) {
    // Always post through the modern center: the system enforces the user's
    // authorization choice (delivering once granted, dropping silently
    // otherwise) — no need to track the async grant state ourselves.
    if let center = center {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      if sound { content.sound = .default }
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
}

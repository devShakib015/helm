# Changelog

All notable changes to Helm are documented here.

## [1.3.0] — 2026-06-29

Organization and window polish.

### Added

- **Categorized tool rail** — tools are grouped into collapsible **Monitor**, **Manage** and **Utilities** sections (with Dashboard pinned on top and Settings in the footer), so the sidebar stays tidy as the toolset grows. The active tool's group expands automatically.
- **Dashboard tool launcher** — an "All Tools" section on the Dashboard lays out every tool grouped by category as clickable cards.
- **Resizable sidebar** — drag the rail's edge to widen or narrow it.
- **Double-click the title bar to zoom** the window (fill the screen), matching native window behaviour; the window is fully resizable and supports full-screen.

### Changed

- **Launch at login now starts in the background** — when macOS auto-launches Helm at login it comes up as a menu-bar item only (no window, no Dock icon). Launching Helm yourself still opens the window as usual.
- **Notification permission prompt** now appears on first launch (the request was moved out of window construction, where macOS could silently drop it).

## [1.2.0] — 2026-06-29

Notifications, a developer-grade **Color Picker**, and two new utility tools.

### Added

- **Notifications**
  - **Copy notifications** (Maccy-style) — a "Copied …" banner showing what you just put on the clipboard. Toggle under Settings ▸ Clipboard ▸ "Notify on copy".
  - **Threshold alerts** — get notified when a module crosses a limit you set: CPU, GPU, Memory, Disk and CPU Temp going *above* a threshold, or Battery dropping *below* one. Each is configured independently under Settings ▸ Alerts (per-metric on/off + threshold stepper), with hysteresis and a cooldown so a value hovering near the line doesn't spam you.
- **Color Picker** (new tool) — opens the macOS screen magnifier to sample any pixel, copies the color to the clipboard, and shows it in every developer format (HEX, HEX lower, RGB, RGBA, HSL, SwiftUI `Color`, `UIColor`, Flutter `Color`) with one-tap copy. Keeps a swatch history. Also available from the menu bar as **"Pick Color from Screen"**. Sampling runs in the system's own process — no Screen Recording permission required.
- **Keep Awake** (new tool) — prevents display and system sleep, indefinitely or for a preset duration (15 m / 30 m / 1 h / 2 h / 5 h), via a held `caffeinate` assertion. Toggle it from the page or straight from the menu bar (with a live checkmark); it releases automatically when Helm quits.
- **Quick Actions** (new tool) — power-user toggles (show hidden files, Desktop icons, auto-hide Dock, Dark Mode) and one-tap maintenance (Restart Finder / Dock / Menu Bar, Sleep Display, Empty Trash with confirmation).
- **Battery** added to live telemetry (IOKit power sources) — a new optional **menu-bar metric**, a dropdown line, and the source for the low-battery alert.

### Notes

- The first time Helm runs it asks for notification permission; allow it once and copy + threshold alerts will appear. You can fine-tune what's shown under System Settings ▸ Notifications ▸ Helm.

## [1.1.0] — 2026-06-29

Helm absorbs **Stats** and **Maccy** — no more separate menu-bar/clipboard apps.

### Added

- **Live menu-bar item** — a native `NSStatusItem` showing colored, configurable metrics (CPU/GPU/RAM/Disk/Network/Temp), with a dropdown of full readings, **recent clipboard items (click to copy)**, and Open/Quit. Customizable live from Settings; menu-bar-resident (stays running when the window closes).
- **Dashboard** (new first page) — device + macOS spec sheet (model, chip, P/E cores, memory, graphics, disk, display, identifiers, serial, live uptime) plus live CPU/GPU/RAM/SSD gauges.
- **CPU**, **GPU**, **Sensors** monitor pages with live gauges and history sparklines (CPU per-core breakdown). Sensors reads real **temperatures via a native Apple Silicon SMC reader** (CPU/GPU °C); also available as a menu-bar metric.
- **Clipboard manager** (Maccy-style) — pasteboard history with search, pin, delete, copy-back; ignores password-manager items; persisted to disk.
- **Settings** — Menu Bar (metrics, colored values, refresh interval), Clipboard (history size, ignore passwords, clear on quit), General (launch at login, keep running in menu bar), About.
- Native system telemetry via host/IOKit APIs (CPU, GPU utilization, memory, network, disk, uptime) — no elevated privileges.

### Notes

- Temperatures are read directly from the SMC (no root needed). Fan speed appears only on Macs that have fans — the MacBook Air is fanless, so no fan reading is shown.

## [1.0.0] — 2026-06-28

The first release. Helm ships as a **seven-tool** macOS toolkit.

### Tools

- **Storage** — full Storage Manager & Cleaner (see below).
- **Memory** — live RAM breakdown (`vm_stat`/`sysctl`), memory-pressure gauge, top processes by memory with one-tap Quit, and "Free Up Memory" (`purge`).
- **Uninstaller** — lists installed apps with sizes and finds every leftover (caches, support, containers, prefs, logs, launch agents) by bundle id + strict name match; removes app + leftovers to the Trash.
- **Startup** — login items (via System Events) and user Launch Agents, with read-only system daemons; remove/disable user items (`launchctl unload` + Trash).
- **Privacy** — trace cleaner for recent items, Safari/Chrome history & cookies, Quick Look cache, shell history and Terminal state; flush DNS; open Privacy settings.
- **Battery** — charge, condition, cycle count, max capacity and power source via `pmset` + `system_profiler`.
- **Network** — live download/upload throughput with sparklines (`netstat` sampling), interfaces (`ifconfig`), Wi-Fi, and established connections (`lsof`).

### Storage tool

- **Storage overview** — disk capacity with accurate purgeable space (matching “About This Mac”), animated donut and segmented bar.
- **Category breakdown** — disjoint, non-overlapping measurement of Applications, Documents, Desktop, Downloads, Photos, Music, Movies, Mail, Messages, Developer, Caches, Trash, and derived System Data.
- **Treemap explorer** — squarified treemap with breadcrumb drill-down and per-item move-to-Trash.
- **System Junk cleaner** — user/system caches, logs, Trash, saved app state, developer junk (Xcode DerivedData, simulators, npm/yarn/gradle/pip/CocoaPods…), browser caches, old downloads, mail attachments, and conservative app-leftover detection. Risk-aware selection.
- **Large & Old files** — size threshold, age filter, and sort controls.
- **Duplicate finder** — size → quick-hash → full-MD5 matching, with a guarantee that at least one copy always survives.
- **APFS local snapshots** — listing and one-tap thinning via `tmutil`.
- **Full Disk Access** detection with an inline guidance banner.
- **Multi-tool shell** — premium dark-glass UI, vibrancy window, and a sidebar previewing upcoming tools (Memory, Uninstaller, Startup, Privacy, Battery, Network).

### Safety

- All removals go to the **Trash** (recoverable). Only the Trash group is emptied permanently, with explicit confirmation.
- Protected OS paths are never scanned or deleted; symlinks are never followed.

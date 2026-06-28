# Changelog

All notable changes to Helm are documented here.

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

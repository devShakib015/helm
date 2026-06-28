<div align="center">

# ⎈ Helm

### Take the helm of your Mac.

A premium, native macOS management toolkit — starting with a complete **Storage Manager & Cleaner**, built to grow into a full suite of Mac tools.

Free • Open Source (MIT) • Built with Flutter

</div>

---

## What is Helm?

**Helm** is a beautiful, fast, all-in-one utility for macOS. It puts you in control of your Mac — analyzing what's using your disk, finding the junk worth clearing, and reclaiming space safely.

It's a **multi-tool platform**: seven tools — Storage, Memory, Uninstaller, Startup, Privacy, Battery and Network — each slotting into the same premium shell, with more to come.

> **Safe by design.** Helm never deletes destructively. Everything it removes goes to the **Trash**, so you can always get it back. The only exception is emptying the Trash itself — which you explicitly confirm.

## ✨ The Storage tool

| | Feature |
|---|---|
| 📊 | **Disk overview** — exact capacity including *purgeable* space, matching “About This Mac”. |
| 🍩 | **Category breakdown** — Applications, Documents, Photos, Music, Movies, Mail, Messages, Developer, Caches, Trash and the opaque *System Data*, all measured into disjoint, non-overlapping buckets. |
| 🗺️ | **Visual explorer** — a DaisyDisk-style **squarified treemap** with breadcrumb drill-down into any folder, down to individual files. |
| 🧹 | **System Junk cleaner** — user & system caches, logs, the Trash, saved app state, **developer junk** (Xcode DerivedData, simulators, npm/yarn/gradle/pip/CocoaPods caches…), browser caches, old downloads, mail attachments and conservative **app-leftover** detection. Safe items pre-selected; risky ones opt-in. |
| 📦 | **Large & Old files** — track down space hogs by size and age, with sort/filter controls. |
| 👯 | **Duplicate finder** — byte-for-byte content matching (size → quick hash → full MD5), always keeping at least one copy. |
| 🕰️ | **APFS snapshots** — surface and thin local Time Machine snapshots that quietly eat space. |
| 🔒 | **Full Disk Access aware** — works on most of your files immediately; guides you to grant FDA for an exact, complete picture. |

## 🎨 Design

A custom **“deep dark + glass”** design system: a frameless vibrancy window with the traffic lights overlaid on a translucent sidebar, native **SF Pro** typography, hand-built charts and treemaps (no chart dependency), and fluid motion throughout. It looks like a paid pro app — because it's meant to.

## 🏗️ Architecture

Helm is structured so new tools are easy to add and the heavy lifting never blocks the UI.

```
lib/
├─ app/                  # app shell: tool registry, sidebar, window root
│  └─ shell/
├─ core/                 # cross-tool foundation
│  ├─ models/            # pure-Dart, isolate-safe data models
│  ├─ services/          # native bridge, permissions, deletion, system info
│  ├─ theme/             # colors, typography, spacing
│  └─ widgets/           # reusable premium widgets
└─ tools/
   └─ storage/           # the Storage tool (self-contained)
      ├─ engine/         # isolate-based scanners (category, junk, large, dup)
      ├─ state/          # ChangeNotifier controllers
      └─ ui/             # views + storage-specific widgets
```

**Key engineering choices**

- **Background isolates** for every scan — the filesystem is walked off the UI thread, streaming live byte/file/path progress, fully cancellable.
- **Pure-Dart models** (no Flutter imports) so results copy cleanly across the isolate boundary.
- **Thin native layer** (Swift `MethodChannel`) for only what Dart can't do well: recoverable **Trash** removal (`FileManager.trashItem`) and accurate **purgeable** capacity (`URLResourceValues`).
- **Symlinks never followed** and protected OS paths (`/System`, `/usr`, …) are never touched — avoiding loops, double-counting (macOS firmlinks), and dangerous deletions.
- **Provider** for state, a single dark `ThemeData`, and `macos_window_utils` for the vibrancy window.

## 🚀 Build & run

Requires Flutter (stable) and Xcode.

```bash
flutter pub get
flutter run -d macos          # debug
flutter build macos --release # release .app
```

For distribution, Helm is intended to ship as a **notarized DMG** (not the Mac App Store) so it can request Full Disk Access. The app is **not sandboxed**; enable the Hardened Runtime in Xcode and notarize before sharing.

- **Bundle ID:** `com.devshakib.helm`
- **Minimum macOS:** 10.15+

## 🧰 The toolkit

Helm ships with **seven** tools, each in the same premium shell:

- 📊 **Storage** — analyze & reclaim disk space (categories, treemap, junk, large files, duplicates)
- 🧠 **Memory** — live RAM breakdown, top processes, quit apps, free inactive memory
- 🗑️ **Uninstaller** — remove an app *and* every leftover (caches, support, containers…) it leaves behind
- 🚀 **Startup** — manage login items and Launch Agents that run at boot
- 🛡️ **Privacy** — clear browsing/shell/recent-item traces and flush the DNS cache
- 🔋 **Battery** — health, cycle count, condition and power insights
- 📡 **Network** — live up/down throughput, interfaces, Wi-Fi and active connections

### Future ideas

- Login/keychain hygiene, duplicate-photo detection, scheduled auto-clean, menu-bar quick stats.

## 🔐 Privacy

Helm runs **entirely on your Mac**. It has no servers, no analytics, no network calls. Nothing about your files ever leaves the device.

## 📄 License

[MIT](LICENSE) © 2026 Shakib. Free to use, modify and share.

---

<div align="center">
Made with care for macOS by <b>Shakib</b>.
</div>

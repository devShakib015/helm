import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/settings_controller.dart';
import '../../core/services/native_system.dart';
import '../../core/utils/byte_format.dart';

/// What a stored clipboard entry holds.
enum ClipKind { text, image, file }

/// Outcome of a copy-back, so the UI can be honest about partial restores.
enum CopyStatus { ok, partial, failed }

/// One stored clipboard entry. Text carries its content inline; images point
/// at PNGs persisted next to the history; file copies carry paths only — the
/// referenced bytes are NEVER read or duplicated (a 4 GB movie stays a 4 GB
/// movie on disk, and a few dozen bytes in the history).
class ClipItem {
  ClipItem({
    required this.kind,
    this.text = '',
    this.files = const [],
    this.sizeBytes = 0,
    this.width = 0,
    this.height = 0,
    this.imagePath,
    this.thumbPath,
    this.truncated = false,
    required this.dedupeKey,
    required this.createdMs,
    this.pinned = false,
  });

  final ClipKind kind;
  final String text; // text content ('' for image/file)
  final List<String> files; // file kind: the copied paths
  final int sizeBytes; // image: encoded size; file: total file bytes
  final int width; // image pixels
  final int height;
  final String? imagePath; // full PNG (null if too large to persist)
  final String? thumbPath; // small preview PNG
  final bool truncated; // text was cut at the storage cap

  /// In "clear on quit" mode images are kept in MEMORY ONLY (never written to
  /// disk, honoring the privacy setting). These are transient — not serialized.
  Uint8List? imageBytes;
  Uint8List? thumbBytes;

  bool get imageRestorable =>
      kind == ClipKind.image && (imagePath != null || imageBytes != null);

  /// Stable identity used to fold repeat copies into one entry.
  final String dedupeKey;

  int createdMs;
  bool pinned;

  int get chars => text.length;

  /// Haystack for the search field.
  String get searchText =>
      kind == ClipKind.text ? text : files.map(_basename).join(' ');

  /// One-line label for lists, notifications and the menu bar.
  String get preview {
    switch (kind) {
      case ClipKind.text:
        final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        return oneLine.isEmpty ? '(empty)' : oneLine;
      case ClipKind.image:
        return 'Image $width×$height · ${formatBytes(sizeBytes)}';
      case ClipKind.file:
        if (files.length == 1) return _basename(files.first);
        return '${files.length} items';
    }
  }

  static String _basename(String p) =>
      p.endsWith('/') ? p : p.split('/').last;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'text': text,
        'files': files,
        'sizeBytes': sizeBytes,
        'w': width,
        'h': height,
        'imagePath': imagePath,
        'thumbPath': thumbPath,
        'truncated': truncated,
        'key': dedupeKey,
        'createdMs': createdMs,
        'pinned': pinned,
      };

  factory ClipItem.fromJson(Map<String, dynamic> j) {
    // v1 histories had only {text, createdMs, pinned} — migrate as text.
    final kindName = j['kind'] as String? ?? 'text';
    final kind = ClipKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => ClipKind.text,
    );
    final text = j['text'] as String? ?? '';
    return ClipItem(
      kind: kind,
      text: text,
      files: (j['files'] as List?)?.cast<String>() ?? const [],
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (j['w'] as num?)?.toInt() ?? 0,
      height: (j['h'] as num?)?.toInt() ?? 0,
      imagePath: j['imagePath'] as String?,
      thumbPath: j['thumbPath'] as String?,
      truncated: j['truncated'] as bool? ?? false,
      // v1 entries carry no key — derive the SAME md5-based key new text
      // ingests use, so re-copying an old snippet folds into it.
      dedupeKey: j['key'] as String? ?? 't:${hashBytes(utf8.encode(text))}',
      createdMs: (j['createdMs'] as num?)?.toInt() ?? 0,
      pinned: j['pinned'] as bool? ?? false,
    );
  }

  /// md5 hex of [bytes] — shared by ingest dedupe and v1 migration.
  static String hashBytes(List<int> bytes) => md5.convert(bytes).toString();
}

/// Maccy-style clipboard history: polls the pasteboard, dedupes, pins,
/// searches, and pastes back — for text, images AND file copies. Persists to
/// Application Support unless the user has chosen "clear on quit".
class ClipboardController extends ChangeNotifier {
  ClipboardController(this._settings) {
    _init();
  }

  final SettingsController _settings;
  final List<ClipItem> _items = [];
  String query = '';
  bool loaded = false;

  Timer? _timer;
  int _lastChange = -1;
  bool _disposed = false;
  bool _polling = false;
  bool _copying = false; // a copy-back is in flight — don't self-ingest it
  File? _file;
  Directory? _imagesDir;

  List<ClipItem> get items {
    final q = query.trim().toLowerCase();
    final list = _items
        .where((i) => q.isEmpty || i.searchText.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdMs.compareTo(a.createdMs);
    });
    return list;
  }

  int get count => _items.length;

  /// The slice mirrored into the menu-bar dropdown (first 8) and the hotkey
  /// quick-paste popup (all 15). Deliberately UNFILTERED — a search typed in
  /// the Clipboard tool must not silently hide entries from the menu bar.
  /// Items are identified by dedupeKey (see [copyById]).
  List<ClipItem> get menuItems {
    final list = [..._items];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdMs.compareTo(a.createdMs);
    });
    return list.take(15).toList();
  }

  Future<void> _init() async {
    await _load();
    await _sweepOrphanImages();
    _lastChange = await NativeSystem.pbChangeCount();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _poll());
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  /// Deletes files in clip_images that no loaded item references — heals the
  /// leaks from dropped entries and, in "clear on quit" sessions, removes any
  /// leftovers from before the setting was enabled.
  Future<void> _sweepOrphanImages() async {
    try {
      final dir = await _imagesDirectory();
      final referenced = <String>{
        for (final i in _items) ...[
          if (i.imagePath != null) i.imagePath!,
          if (i.thumbPath != null) i.thumbPath!,
        ],
      };
      await for (final f in dir.list(followLinks: false)) {
        if (f is File && !referenced.contains(f.path)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_disposed || _polling || _copying || !_settings.clipboardEnabled) {
      return;
    }
    final c = await NativeSystem.pbChangeCount();
    if (c == _lastChange || _disposed) return;
    _lastChange = c;
    if (_settings.clipboardIgnoreConcealed && await NativeSystem.pbConcealed()) {
      return;
    }
    _polling = true; // image encode/write can outlive one poll tick
    try {
      final m = await NativeSystem.pbRead();
      // A copy-back may have started while pbRead was in flight — what we
      // just read could be our OWN write. Never ingest it.
      if (m == null || _disposed || _copying) return;
      switch (m['kind'] as String? ?? 'none') {
        case 'text':
          final text = m['text'] as String? ?? '';
          if (text.trim().isEmpty) return;
          _ingest(ClipItem(
            kind: ClipKind.text,
            text: text,
            truncated: m['truncated'] == true,
            dedupeKey: 't:${ClipItem.hashBytes(utf8.encode(text))}',
            createdMs: DateTime.now().millisecondsSinceEpoch,
          ));
        case 'file':
          final paths = (m['paths'] as List?)?.cast<String>() ?? const [];
          if (paths.isEmpty) return;
          _ingest(ClipItem(
            kind: ClipKind.file,
            files: paths,
            sizeBytes: (m['bytes'] as num?)?.toInt() ?? 0,
            dedupeKey: 'f:${paths.join('|')}',
            createdMs: DateTime.now().millisecondsSinceEpoch,
          ));
        case 'image':
          final item = await _persistImage(m);
          if (item != null && !_disposed) _ingest(item);
      }
    } finally {
      _polling = false;
    }
  }

  /// Builds an image clip's item. Normally the PNGs go to disk beside the
  /// history; in "clear on quit" mode they stay in MEMORY ONLY, so nothing the
  /// user asked to be forgotten ever touches the disk. The full image is only
  /// present when its ENCODED size fit the native cap; the thumbnail always is.
  Future<ClipItem?> _persistImage(Map<String, dynamic> m) async {
    final thumb = m['thumb'];
    if (thumb is! Uint8List || thumb.isEmpty) return null;
    final full = m['image'];
    final fullBytes = full is Uint8List && full.isNotEmpty ? full : null;
    final hash = ClipItem.hashBytes(fullBytes ?? thumb);
    final key = 'i:$hash';
    // Repeat copy of an image we already store → reuse the existing entry.
    final existing = _items.indexWhere((i) => i.dedupeKey == key);
    if (existing >= 0) {
      final it = _items[existing];
      it.createdMs = DateTime.now().millisecondsSinceEpoch;
      return _items.removeAt(existing);
    }
    final base = ClipItem(
      kind: ClipKind.image,
      sizeBytes: (m['bytes'] as num?)?.toInt() ?? 0,
      width: (m['w'] as num?)?.toInt() ?? 0,
      height: (m['h'] as num?)?.toInt() ?? 0,
      dedupeKey: key,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (_settings.clipboardClearOnQuit) {
      base.thumbBytes = thumb;
      base.imageBytes = fullBytes;
      return base;
    }
    try {
      final dir = await _imagesDirectory();
      final thumbFile = File('${dir.path}/${hash}_t.png');
      await thumbFile.writeAsBytes(thumb, flush: false);
      String? imagePath;
      if (fullBytes != null) {
        final imageFile = File('${dir.path}/$hash.png');
        await imageFile.writeAsBytes(fullBytes, flush: false);
        imagePath = imageFile.path;
      }
      return ClipItem(
        kind: ClipKind.image,
        sizeBytes: base.sizeBytes,
        width: base.width,
        height: base.height,
        imagePath: imagePath,
        thumbPath: thumbFile.path,
        dedupeKey: key,
        createdMs: base.createdMs,
      );
    } catch (_) {
      return null;
    }
  }

  void _ingest(ClipItem item) {
    if (_disposed || _copying) return; // never ingest our own copy-back
    final idx = _items.indexWhere((i) => i.dedupeKey == item.dedupeKey);
    if (idx >= 0) {
      final old = _items.removeAt(idx);
      item.pinned = old.pinned;
    }
    _items.insert(0, item);
    _trim();
    _save();
    notifyListeners();
    if (_settings.clipboardNotify) {
      NativeSystem.notify('Copied', _notifyBody(item));
    }
  }

  String _notifyBody(ClipItem item) {
    switch (item.kind) {
      case ClipKind.text:
        final p = item.preview;
        return p.length > 120 ? '${p.substring(0, 120)}…' : p;
      case ClipKind.image:
        return '🖼 ${item.preview}';
      case ClipKind.file:
        final label = item.preview;
        return item.sizeBytes > 0
            ? '📄 $label · ${formatBytes(item.sizeBytes)}'
            : '📄 $label';
    }
  }

  void _trim() {
    final max = _settings.clipboardHistorySize;
    final nonPinned = _items.where((i) => !i.pinned).toList();
    if (nonPinned.length > max) {
      final toRemove = nonPinned.sublist(max).toSet();
      for (final r in toRemove) {
        _deleteImageFiles(r);
      }
      _items.removeWhere(toRemove.contains);
    }
  }

  /// Copies an item back to the pasteboard in its ORIGINAL representation.
  /// [CopyStatus.partial] means some (but not all) of a file clip's paths
  /// still existed and were restored; [CopyStatus.failed] means nothing was.
  Future<CopyStatus> copy(ClipItem item) async {
    // Block the poller for the whole write→changeCount window so our own
    // pasteboard write is never re-ingested as a "new" copy (an image would
    // even come back with different bytes after the round-trip re-encode).
    _copying = true;
    try {
      var status = CopyStatus.failed;
      switch (item.kind) {
        case ClipKind.text:
          if (await NativeSystem.pbWriteText(item.text)) {
            status = CopyStatus.ok;
          }
        case ClipKind.image:
          final p = item.imagePath;
          final ok = p != null && File(p).existsSync()
              ? await NativeSystem.pbWriteImage(p)
              : (item.imageBytes != null &&
                  await NativeSystem.pbWriteImageData(item.imageBytes!));
          if (ok) status = CopyStatus.ok;
        case ClipKind.file:
          final live = item.files.where((f) => File(f).existsSync() ||
              Directory(f).existsSync() || Link(f).existsSync()).toList();
          if (live.isNotEmpty && await NativeSystem.pbWriteFiles(live)) {
            status = live.length == item.files.length
                ? CopyStatus.ok
                : CopyStatus.partial;
          }
      }
      if (status != CopyStatus.failed) {
        _lastChange = await NativeSystem.pbChangeCount();
        item.createdMs = DateTime.now().millisecondsSinceEpoch;
        _save();
        if (!_disposed) notifyListeners();
      }
      return status;
    } finally {
      _copying = false;
    }
  }

  /// Copy-back for a click on the menu-bar dropdown, addressed by the item's
  /// stable dedupe key — immune to the list shifting between display & click.
  Future<void> copyById(String id) async {
    final idx = _items.indexWhere((i) => i.dedupeKey == id);
    if (idx < 0) return;
    await copy(_items[idx]);
  }

  void togglePin(ClipItem item) {
    item.pinned = !item.pinned;
    _save();
    notifyListeners();
  }

  void delete(ClipItem item) {
    _items.remove(item);
    _deleteImageFiles(item);
    _save();
    notifyListeners();
  }

  void clearAll() {
    for (final i in _items.where((i) => !i.pinned)) {
      _deleteImageFiles(i);
    }
    _items.removeWhere((i) => !i.pinned);
    _save();
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void _deleteImageFiles(ClipItem item) {
    if (item.kind != ClipKind.image) return;
    for (final p in [item.imagePath, item.thumbPath]) {
      if (p == null) continue;
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
  }

  Future<Directory> _imagesDirectory() async {
    if (_imagesDir != null) return _imagesDir!;
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/clip_images');
    await dir.create(recursive: true);
    _imagesDir = dir;
    return dir;
  }

  Future<void> _load() async {
    if (_settings.clipboardClearOnQuit) return; // memory-only
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/clipboard_history.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final list = (json.decode(raw) as List)
            .map((e) => ClipItem.fromJson(Map<String, dynamic>.from(e as Map)))
            // Self-heal: drop image entries whose preview file vanished.
            .where((i) =>
                i.kind != ClipKind.image ||
                (i.thumbPath != null && File(i.thumbPath!).existsSync()))
            .toList();
        _items
          ..clear()
          ..addAll(list);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_settings.clipboardClearOnQuit) return;
    try {
      _file ??= File(
          '${(await getApplicationSupportDirectory()).path}/clipboard_history.json');
      await _file!
          .writeAsString(json.encode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

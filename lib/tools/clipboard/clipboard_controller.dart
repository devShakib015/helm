import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/settings_controller.dart';
import '../../core/services/native_system.dart';

/// One stored clipboard entry (text).
class ClipItem {
  ClipItem({required this.text, required this.createdMs, this.pinned = false});

  final String text;
  int createdMs;
  bool pinned;

  int get lines => '\n'.allMatches(text).length + 1;
  int get chars => text.length;

  Map<String, dynamic> toJson() =>
      {'text': text, 'createdMs': createdMs, 'pinned': pinned};

  factory ClipItem.fromJson(Map<String, dynamic> j) => ClipItem(
        text: j['text'] as String? ?? '',
        createdMs: (j['createdMs'] as num?)?.toInt() ?? 0,
        pinned: j['pinned'] as bool? ?? false,
      );
}

/// Maccy-style clipboard history: polls the pasteboard, dedupes, pins,
/// searches, and pastes back. Persists to Application Support unless the user
/// has chosen "clear on quit" (then it stays in memory only).
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
  File? _file;

  List<ClipItem> get items {
    final q = query.trim().toLowerCase();
    final list = _items
        .where((i) => q.isEmpty || i.text.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdMs.compareTo(a.createdMs);
    });
    return list;
  }

  int get count => _items.length;

  Future<void> _init() async {
    await _load();
    _lastChange = await NativeSystem.pbChangeCount();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _poll());
    loaded = true;
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_disposed || !_settings.clipboardEnabled) return;
    final c = await NativeSystem.pbChangeCount();
    if (c == _lastChange) return;
    _lastChange = c;
    if (_settings.clipboardIgnoreConcealed && await NativeSystem.pbConcealed()) {
      return;
    }
    final text = await NativeSystem.pbReadText();
    if (text == null || text.trim().isEmpty) return;
    _add(text, notify: true);
  }

  void _add(String text, {bool notify = false}) {
    final idx = _items.indexWhere((i) => i.text == text);
    var pinned = false;
    if (idx >= 0) {
      pinned = _items[idx].pinned;
      _items.removeAt(idx);
    }
    _items.insert(
      0,
      ClipItem(
        text: text,
        createdMs: DateTime.now().millisecondsSinceEpoch,
        pinned: pinned,
      ),
    );
    _trim();
    _save();
    notifyListeners();
    // Maccy-style: surface what was just copied (only for genuine external
    // copies, never the app's own copy-back).
    if (notify && _settings.clipboardNotify) {
      NativeSystem.notify('Copied', _notifyPreview(text));
    }
  }

  /// Single-line, length-capped preview for the "Copied" notification.
  String _notifyPreview(String s) {
    final oneLine = s
        .replaceAll('\n', ' ')
        .replaceAll('\t', ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length > 120 ? '${oneLine.substring(0, 120)}…' : oneLine;
  }

  void _trim() {
    final max = _settings.clipboardHistorySize;
    final nonPinned = _items.where((i) => !i.pinned).toList();
    if (nonPinned.length > max) {
      final toRemove = nonPinned.sublist(max).toSet();
      _items.removeWhere(toRemove.contains);
    }
  }

  /// Copies an item back to the pasteboard (and moves it to the top).
  Future<void> copy(ClipItem item) async {
    await NativeSystem.pbWriteText(item.text);
    _lastChange = await NativeSystem.pbChangeCount();
    _add(item.text);
  }

  void togglePin(ClipItem item) {
    item.pinned = !item.pinned;
    _save();
    notifyListeners();
  }

  void delete(ClipItem item) {
    _items.remove(item);
    _save();
    notifyListeners();
  }

  void clearAll() {
    _items.removeWhere((i) => !i.pinned);
    _save();
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
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
      await _file!.writeAsString(json.encode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

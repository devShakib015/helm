import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/native_system.dart';

/// One picked color, stored as an uppercase `#RRGGBB` hex string.
class PickedColor {
  PickedColor({required this.hex, required this.createdMs});

  final String hex;
  final int createdMs;

  Map<String, dynamic> toJson() => {'hex': hex, 'createdMs': createdMs};

  factory PickedColor.fromJson(Map<String, dynamic> j) => PickedColor(
        hex: (j['hex'] as String?) ?? '#000000',
        createdMs: (j['createdMs'] as num?)?.toInt() ?? 0,
      );
}

/// Drives the Color Picker: opens the system eyedropper, copies the picked
/// color to the clipboard, and keeps a persisted history of swatches. Also
/// receives colors picked from the menu-bar item via [receivePick].
class ColorPickerController extends ChangeNotifier {
  ColorPickerController() {
    _load();
  }

  final List<PickedColor> _history = [];
  bool _picking = false;
  File? _file;
  bool _disposed = false;

  List<PickedColor> get history => List.unmodifiable(_history);
  PickedColor? get last => _history.isEmpty ? null : _history.first;
  bool get picking => _picking;

  /// Opens the screen eyedropper. On pick, copies the hex to the clipboard and
  /// records it. Returns the picked hex (or null if cancelled).
  Future<String?> pick() async {
    _picking = true;
    _safeNotify();
    final hex = await NativeSystem.sampleColor();
    _picking = false;
    if (hex != null) {
      await NativeSystem.pbWriteText(hex);
      _record(hex);
    }
    _safeNotify();
    return hex;
  }

  /// A color picked from the menu-bar item: the native side already copied it to
  /// the clipboard, so we just record it.
  void receivePick(String hex) => _record(hex);

  /// Copies an existing swatch back to the clipboard and floats it to the top.
  Future<void> copy(String hex) async {
    await NativeSystem.pbWriteText(hex);
    _record(hex);
  }

  void _record(String hex) {
    final norm = hex.toUpperCase();
    _history.removeWhere((c) => c.hex.toUpperCase() == norm);
    _history.insert(
      0,
      PickedColor(hex: norm, createdMs: DateTime.now().millisecondsSinceEpoch),
    );
    if (_history.length > 100) _history.removeRange(100, _history.length);
    _save();
    _safeNotify();
  }

  void delete(PickedColor c) {
    _history.remove(c);
    _save();
    _safeNotify();
  }

  void clear() {
    _history.clear();
    _save();
    _safeNotify();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/color_history.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final list = (json.decode(raw) as List)
            .map((e) => PickedColor.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _history
          ..clear()
          ..addAll(list);
        _safeNotify();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      _file ??= File(
          '${(await getApplicationSupportDirectory()).path}/color_history.json');
      await _file!
          .writeAsString(json.encode(_history.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---- Color format helpers ----

/// Parses a `#RRGGBB` (or `RRGGBB`) hex string into a Flutter [Color].
Color colorFromHex(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length != 6) return const Color(0xFF000000);
  final v = int.tryParse(h, radix: 16) ?? 0;
  return Color(0xFF000000 | v);
}

/// (r, g, b) 0–255 from a hex string.
({int r, int g, int b}) rgbFromHex(String hex) {
  final c = colorFromHex(hex);
  // ignore: deprecated_member_use
  return (r: c.red, g: c.green, b: c.blue);
}

/// (h 0–360, s 0–100, l 0–100) from a hex string.
({int h, int s, int l}) hslFromHex(String hex) {
  final rgb = rgbFromHex(hex);
  final r = rgb.r / 255, g = rgb.g / 255, b = rgb.b / 255;
  final max = [r, g, b].reduce((a, b) => a > b ? a : b);
  final min = [r, g, b].reduce((a, b) => a < b ? a : b);
  final l = (max + min) / 2;
  double h = 0, s = 0;
  final d = max - min;
  if (d != 0) {
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  return (h: (h * 360).round(), s: (s * 100).round(), l: (l * 100).round());
}

/// One named, copyable representation of a color (label → value).
class ColorFormat {
  const ColorFormat(this.label, this.value);
  final String label;
  final String value;
}

/// Every developer-friendly representation of a hex color.
List<ColorFormat> colorFormats(String hex) {
  final rgb = rgbFromHex(hex);
  final hsl = hslFromHex(hex);
  final upper = hex.toUpperCase();
  String f(double v) => v.toStringAsFixed(3);
  return [
    ColorFormat('HEX', upper),
    ColorFormat('HEX (lower)', hex.toLowerCase()),
    ColorFormat('RGB', 'rgb(${rgb.r}, ${rgb.g}, ${rgb.b})'),
    ColorFormat('RGBA', 'rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 1)'),
    ColorFormat('HSL', 'hsl(${hsl.h}, ${hsl.s}%, ${hsl.l}%)'),
    ColorFormat(
      'SwiftUI',
      'Color(red: ${f(rgb.r / 255)}, green: ${f(rgb.g / 255)}, blue: ${f(rgb.b / 255)})',
    ),
    ColorFormat(
      'UIColor',
      'UIColor(red: ${f(rgb.r / 255)}, green: ${f(rgb.g / 255)}, blue: ${f(rgb.b / 255)}, alpha: 1)',
    ),
    ColorFormat('Flutter', 'Color(0xFF${upper.replaceAll('#', '')})'),
  ];
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/shell.dart';

/// One connected Bluetooth device battery reading. AirPods report multiple
/// components (left / right / case) as separate entries.
class BtDevice {
  const BtDevice({
    required this.name,
    required this.percent,
    this.kind = '',
    this.address = '',
  });

  final String name; // "AirPods Pro · Left"
  final int percent; // 0..100
  final String kind; // minor type when known (Headphones, Mouse, Keyboard…)
  final String address; // normalized MAC, '' when the source doesn't report it
}

/// Battery levels for connected Bluetooth devices (AirPods, Magic Keyboard /
/// Mouse / Trackpad…). Two sources merged: `system_profiler` (AirPods report
/// per-component levels there) and `ioreg`'s HID battery info (Apple input
/// devices). Polled every 60 s — `system_profiler` is slow, so never more.
class BtDevicesController extends ChangeNotifier {
  BtDevicesController() {
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
  }

  List<BtDevice> devices = const [];
  bool loaded = false;

  Timer? _timer;
  bool _disposed = false;
  bool _running = false;

  Future<void> _tick() async {
    if (_disposed || _running) return;
    _running = true;
    try {
      final found = <BtDevice>[];
      final seenAddr = <String>{};
      final seenName = <String>{};
      found.addAll(await _fromSystemProfiler());
      for (final d in found) {
        if (d.address.isNotEmpty) seenAddr.add(d.address);
        seenName.add(d.name.split(' · ').first.toLowerCase());
      }
      // Dedupe primarily by MAC address — the two sources render the same
      // device's NAME differently often enough that name matching misses.
      for (final d in await _fromIoreg()) {
        if (d.address.isNotEmpty && seenAddr.contains(d.address)) continue;
        if (seenName.contains(d.name.toLowerCase())) continue;
        found.add(d);
      }
      if (_disposed) return;
      devices = found;
      loaded = true;
      if (!_disposed) notifyListeners();
    } finally {
      _running = false;
    }
  }

  /// Lowercased hex-only MAC so "AA:BB:CC" and "aa-bb-cc" compare equal.
  static String _normAddress(Object? raw) => raw is String
      ? raw.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '')
      : '';

  Future<List<BtDevice>> _fromSystemProfiler() async {
    try {
      final r = await Shell.run(
        'system_profiler', ['SPBluetoothDataType', '-json'],
        timeout: const Duration(seconds: 30),
      );
      if (r.code != 0 || r.out.isEmpty) return const [];
      final root = json.decode(r.out) as Map<String, dynamic>;
      final sections = root['SPBluetoothDataType'] as List? ?? const [];
      final out = <BtDevice>[];
      for (final section in sections) {
        final connected =
            (section as Map)['device_connected'] as List? ?? const [];
        for (final entry in connected) {
          final map = Map<String, dynamic>.from(entry as Map);
          for (final e in map.entries) {
            final name = e.key;
            final props = Map<String, dynamic>.from(e.value as Map);
            final kind = (props['device_minorType'] as String?) ?? '';
            final address = _normAddress(props['device_address']);
            for (final p in props.entries) {
              if (!p.key.startsWith('device_batteryLevel')) continue;
              final pct = _percent(p.value);
              if (pct == null) continue;
              final part = p.key.substring('device_batteryLevel'.length);
              out.add(BtDevice(
                name: part.isEmpty ? name : '$name · $part',
                percent: pct,
                kind: kind,
                address: address,
              ));
            }
          }
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<BtDevice>> _fromIoreg() async {
    try {
      final r = await Shell.run('/bin/bash', [
        '-c',
        'ioreg -r -c AppleDeviceManagementHIDEventService -a | plutil -convert json -o - -',
      ]);
      if (r.code != 0 || r.out.isEmpty) return const [];
      final list = json.decode(r.out) as List;
      final out = <BtDevice>[];
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final pct = m['BatteryPercent'];
        final name = m['Product'];
        if (pct is num && name is String && name.isNotEmpty) {
          out.add(BtDevice(
            name: name,
            percent: pct.toInt(),
            address: _normAddress(m['DeviceAddress']),
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  int? _percent(Object? raw) {
    if (raw is num) return raw.toInt().clamp(0, 100);
    if (raw is String) {
      final m = RegExp(r'(\d+)').firstMatch(raw);
      if (m != null) return int.parse(m.group(1)!).clamp(0, 100);
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

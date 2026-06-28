import 'dart:convert';

import '../../../core/services/shell.dart';

/// An immutable snapshot of the Mac's battery health and power state, parsed
/// from `pmset -g batt` and `system_profiler SPPowerDataType -json`.
///
/// When [hasBattery] is false the machine is a desktop (or `pmset` reported no
/// internal battery) and the UI should show the "running on AC power" state.
class BatteryInfo {
  const BatteryInfo({
    required this.hasBattery,
    this.chargePercent,
    this.charging = false,
    this.fullyCharged = false,
    this.powerSource,
    this.stateLabel,
    this.timeRemaining,
    this.cycleCount,
    this.condition,
    this.maxCapacityPercent,
    this.chargerName,
    this.chargerWatts,
    this.chargerConnected = false,
  });

  /// False on desktops / when no internal battery is present.
  final bool hasBattery;

  /// Current charge as a whole percent (0..100), or null if unknown.
  final int? chargePercent;

  /// True while the battery is actively charging.
  final bool charging;

  /// True when the battery has reached full charge.
  final bool fullyCharged;

  /// "AC Power" or "Battery Power" — where the Mac is drawing power from now.
  final String? powerSource;

  /// Human label for the raw battery state ("Charging", "Discharging", …).
  final String? stateLabel;

  /// Time remaining text from pmset ("3:21 remaining", "Calculating…").
  final String? timeRemaining;

  /// Charge cycles the battery has been through.
  final int? cycleCount;

  /// Apple's condition rating ("Good", "Normal", "Service Recommended", …).
  final String? condition;

  /// Maximum capacity vs. design, as a whole percent (e.g. 92), or null.
  final int? maxCapacityPercent;

  /// Connected adapter name (e.g. "30W USB-C Power Adapter").
  final String? chargerName;

  /// Adapter wattage, if reported.
  final int? chargerWatts;

  /// True when an AC adapter is physically connected.
  final bool chargerConnected;

  static const BatteryInfo none = BatteryInfo(hasBattery: false);

  /// 0..1 fraction for the ring gauge.
  double get fraction =>
      chargePercent == null ? 0 : (chargePercent! / 100).clamp(0.0, 1.0);

  bool get onAcPower => powerSource == 'AC Power';
}

/// Reads battery health and power state from macOS command-line utilities.
/// Every method degrades gracefully — parsing failures yield nulls rather than
/// throwing, so the UI always has something safe to render.
class BatteryService {
  const BatteryService();

  Future<BatteryInfo> read() async {
    final pm = await _readPmset();
    // No internal battery → desktop / AC-only Mac.
    if (pm == null) return BatteryInfo.none;

    final profile = await _readProfiler();

    return BatteryInfo(
      hasBattery: true,
      chargePercent: profile.chargePercent ?? pm.percent,
      charging: profile.charging ?? pm.charging,
      fullyCharged: profile.fullyCharged ?? (pm.percent == 100 && !pm.charging),
      powerSource: pm.powerSource,
      stateLabel: pm.stateLabel,
      timeRemaining: pm.timeRemaining,
      cycleCount: profile.cycleCount,
      condition: profile.condition,
      maxCapacityPercent: profile.maxCapacityPercent,
      chargerName: profile.chargerName,
      chargerWatts: profile.chargerWatts,
      chargerConnected: profile.chargerConnected,
    );
  }

  // ---- pmset --------------------------------------------------------------

  Future<_PmsetResult?> _readPmset() async {
    try {
      final r = await Shell.run(
        'pmset',
        const ['-g', 'batt'],
        timeout: const Duration(seconds: 10),
      );
      return _parsePmset(r.out);
    } catch (_) {
      return null;
    }
  }

  /// Parses output like:
  ///   Now drawing from 'AC Power'
  ///    -InternalBattery-0 (id=7209059)	90%; discharging; 3:21 remaining
  ///
  /// Returns null when there's no internal battery line (a desktop Mac).
  _PmsetResult? _parsePmset(String out) {
    if (out.trim().isEmpty) return null;

    String? powerSource;
    final drawing = RegExp(r"Now drawing from '([^']+)'").firstMatch(out);
    if (drawing != null) powerSource = drawing.group(1)?.trim();

    final battLine = out
        .split('\n')
        .firstWhere((l) => l.contains('InternalBattery'), orElse: () => '');
    if (battLine.trim().isEmpty) {
      // Some Macs phrase the no-battery case explicitly.
      if (out.toLowerCase().contains('no batteries')) return null;
      return null;
    }

    int? percent;
    final pct = RegExp(r'(\d+)%').firstMatch(battLine);
    if (pct != null) percent = int.tryParse(pct.group(1)!);

    // The line is semicolon-separated: "90%; discharging; 3:21 remaining".
    final parts = battLine.split(';').map((p) => p.trim()).toList();
    String? rawState;
    String? timeRemaining;
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i];
      if (p.isEmpty) continue;
      final lower = p.toLowerCase();
      if (rawState == null &&
          (lower.contains('charging') ||
              lower.contains('discharging') ||
              lower.contains('charged') ||
              lower.contains('attached') ||
              lower.contains('finishing'))) {
        rawState = p;
      } else if (lower.contains('remaining') ||
          lower.contains('until full') ||
          lower.contains('estimate') ||
          lower.contains('calculating')) {
        timeRemaining = _cleanTime(p);
      }
    }

    final lowerState = (rawState ?? '').toLowerCase();
    final charging = lowerState.contains('charging') &&
        !lowerState.contains('discharging') &&
        !lowerState.contains('not charging');

    return _PmsetResult(
      percent: percent,
      powerSource: powerSource,
      stateLabel: _stateLabel(rawState),
      charging: charging,
      timeRemaining: timeRemaining,
    );
  }

  String? _cleanTime(String raw) {
    var s = raw.replaceAll(RegExp(r'present:\s*\w+'), '').trim();
    if (s.startsWith('(') && s.endsWith(')')) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.toLowerCase().contains('no estimate')) return 'Calculating…';
    if (s.toLowerCase().contains('calculating')) return 'Calculating…';
    return s.isEmpty ? null : s;
  }

  String? _stateLabel(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final l = raw.toLowerCase();
    if (l.contains('not charging')) return 'Not Charging';
    if (l.contains('finishing')) return 'Finishing Charge';
    if (l.contains('charged')) return 'Charged';
    if (l.contains('discharging')) return 'Discharging';
    if (l.contains('charging')) return 'Charging';
    if (l.contains('ac attached')) return 'AC Attached';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  // ---- system_profiler ----------------------------------------------------

  Future<_ProfilerResult> _readProfiler() async {
    try {
      final r = await Shell.run(
        'system_profiler',
        const ['SPPowerDataType', '-json'],
        timeout: const Duration(seconds: 25),
      );
      if (r.out.trim().isEmpty) return _ProfilerResult.empty;
      final decoded = jsonDecode(r.out);
      return _parseProfiler(decoded);
    } catch (_) {
      return _ProfilerResult.empty;
    }
  }

  _ProfilerResult _parseProfiler(dynamic decoded) {
    try {
      final list = decoded is Map ? decoded['SPPowerDataType'] : null;
      if (list is! List) return _ProfilerResult.empty;

      Map? batteryDict;
      Map? chargerDict;
      for (final entry in list) {
        if (entry is! Map) continue;
        final name = entry['_name']?.toString() ?? '';
        // The battery dict carries the health/charge sub-dicts; match by those
        // keys rather than relying on a single _name spelling.
        if (entry.containsKey('sppower_battery_health_info') ||
            entry.containsKey('sppower_battery_charge_info') ||
            name == 'spbattery_information') {
          batteryDict ??= entry;
        }
        if (entry.containsKey('sppower_ac_charger_information') ||
            entry.containsKey('sppower_ac_charger_name') ||
            entry.containsKey('sppower_ac_charger_watts') ||
            name == 'sppower_ac_charger_information') {
          chargerDict ??= entry;
        }
      }

      int? chargePercent;
      bool? charging;
      bool? fullyCharged;
      int? cycleCount;
      String? condition;
      int? maxCapacity;

      if (batteryDict != null) {
        final charge = batteryDict['sppower_battery_charge_info'];
        if (charge is Map) {
          chargePercent = _asInt(charge['sppower_battery_state_of_charge']);
          charging = _asBool(charge['sppower_battery_is_charging']);
          fullyCharged = _asBool(charge['sppower_battery_fully_charged']);
        }
        final health = batteryDict['sppower_battery_health_info'];
        if (health is Map) {
          cycleCount = _asInt(health['sppower_battery_cycle_count']);
          condition = _asString(health['sppower_battery_health']);
          maxCapacity = _asPercent(
            health['sppower_battery_health_maximum_capacity'] ??
                health['sppower_battery_maximum_capacity'] ??
                health['sppower_battery_health_maximum_capacity_percent'],
          );
        }
        // Some macOS versions surface charging directly on the battery dict.
        charging ??= _asBool(batteryDict['sppower_battery_is_charging']);
      }

      String? chargerName;
      int? chargerWatts;
      bool chargerConnected = false;
      final cd = chargerDict?['sppower_ac_charger_information'] is Map
          ? chargerDict!['sppower_ac_charger_information'] as Map
          : chargerDict;
      if (cd is Map) {
        chargerName = _asString(cd['sppower_ac_charger_name']);
        chargerWatts = _asInt(cd['sppower_ac_charger_watts']);
        chargerConnected =
            _asBool(cd['sppower_battery_charger_connected']) ?? false;
        // A named adapter present at all means a charger is attached.
        if (chargerName != null && chargerName.isNotEmpty) {
          chargerConnected = true;
        }
      }

      return _ProfilerResult(
        chargePercent: chargePercent,
        charging: charging,
        fullyCharged: fullyCharged,
        cycleCount: cycleCount,
        condition: condition,
        maxCapacityPercent: maxCapacity,
        chargerName: chargerName,
        chargerWatts: chargerWatts,
        chargerConnected: chargerConnected,
      );
    } catch (_) {
      return _ProfilerResult.empty;
    }
  }

  // ---- defensive coercion -------------------------------------------------

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) {
      final m = RegExp(r'-?\d+').firstMatch(v);
      if (m != null) return int.tryParse(m.group(0)!);
    }
    return null;
  }

  String? _asString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == 'yes' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == '0') return false;
    return null;
  }

  /// Reads a capacity that may be "92%", "92", or 92.
  int? _asPercent(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) {
      final m = RegExp(r'\d+').firstMatch(v);
      if (m != null) return int.tryParse(m.group(0)!);
    }
    return null;
  }
}

class _PmsetResult {
  const _PmsetResult({
    this.percent,
    this.powerSource,
    this.stateLabel,
    this.charging = false,
    this.timeRemaining,
  });
  final int? percent;
  final String? powerSource;
  final String? stateLabel;
  final bool charging;
  final String? timeRemaining;
}

class _ProfilerResult {
  const _ProfilerResult({
    this.chargePercent,
    this.charging,
    this.fullyCharged,
    this.cycleCount,
    this.condition,
    this.maxCapacityPercent,
    this.chargerName,
    this.chargerWatts,
    this.chargerConnected = false,
  });

  final int? chargePercent;
  final bool? charging;
  final bool? fullyCharged;
  final int? cycleCount;
  final String? condition;
  final int? maxCapacityPercent;
  final String? chargerName;
  final int? chargerWatts;
  final bool chargerConnected;

  static const _ProfilerResult empty = _ProfilerResult();
}

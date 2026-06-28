import 'dart:convert';

import '../../../core/services/shell.dart';

/// Cumulative byte counters for the machine at a moment in time, summed across
/// active physical (`en*`) interfaces.
class TrafficCounters {
  const TrafficCounters({required this.inBytes, required this.outBytes});

  final int inBytes;
  final int outBytes;

  static const zero = TrafficCounters(inBytes: 0, outBytes: 0);
}

/// A physical network interface and its current addressing/status.
class NetInterface {
  const NetInterface({
    required this.name,
    required this.ipv4,
    required this.active,
  });

  final String name;
  final String? ipv4;
  final bool active;
}

/// One established TCP connection (process + remote endpoint).
class NetConnection {
  const NetConnection({
    required this.process,
    required this.local,
    required this.remote,
  });

  final String process;
  final String local;
  final String remote;
}

/// Current Wi-Fi association details, when available.
class WifiInfo {
  const WifiInfo({this.ssid, this.signalDbm, this.rateMbps});

  final String? ssid;
  final int? signalDbm;
  final int? rateMbps;

  bool get hasData => ssid != null && ssid!.isNotEmpty;

  /// 0..1 signal quality, mapping roughly -90 dBm (poor) .. -30 dBm (great).
  double? get quality {
    final s = signalDbm;
    if (s == null) return null;
    final clamped = s.clamp(-90, -30);
    return (clamped + 90) / 60.0;
  }
}

/// Parses standard macOS networking utilities (`netstat`, `ifconfig`, `lsof`,
/// `system_profiler`) into typed snapshots. Everything is wrapped in try/catch
/// and degrades to empty/zero values rather than throwing to the UI.
class NetworkService {
  /// Sums unique per-interface `Ibytes`/`Obytes` for active physical
  /// interfaces (names starting `en`). `netstat -ib` lists several rows per
  /// interface; only the first row per interface name (the `<Link#N>` row)
  /// carries the real counters, so we take the first row seen for each name to
  /// avoid double counting.
  Future<TrafficCounters> readCounters() async {
    try {
      final out = await Shell.out(
        'netstat',
        const ['-ib'],
        timeout: const Duration(seconds: 6),
      );
      if (out.isEmpty) return TrafficCounters.zero;

      var totalIn = 0;
      var totalOut = 0;
      final seen = <String>{};

      final lines = const LineSplitter().convert(out);
      for (final line in lines) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 7) continue;
        final name = fields.first;
        if (!name.startsWith('en')) continue;
        if (seen.contains(name)) continue; // first row per interface only
        seen.add(name);

        // Columns from the right are stable regardless of whether the optional
        // Address column is present:
        //   ... Ibytes Opkts Oerrs Obytes Coll
        // so Ibytes = NF-5, Obytes = NF-2 (0-based on the last index NF-1).
        final last = fields.length - 1;
        final ibytes = int.tryParse(fields[last - 4]);
        final obytes = int.tryParse(fields[last - 1]);
        if (ibytes == null || obytes == null) continue;

        totalIn += ibytes;
        totalOut += obytes;
      }
      return TrafficCounters(inBytes: totalIn, outBytes: totalOut);
    } catch (_) {
      return TrafficCounters.zero;
    }
  }

  /// Reads en0/en1 IPv4 address and active status from `ifconfig`.
  Future<List<NetInterface>> readInterfaces() async {
    final result = <NetInterface>[];
    for (final name in const ['en0', 'en1']) {
      try {
        final out = await Shell.out(
          'ifconfig',
          [name],
          timeout: const Duration(seconds: 4),
        );
        if (out.isEmpty) continue;

        String? ipv4;
        var active = false;
        for (final raw in const LineSplitter().convert(out)) {
          final line = raw.trim();
          if (line.startsWith('inet ')) {
            final m = RegExp(r'inet (\d+\.\d+\.\d+\.\d+)').firstMatch(line);
            if (m != null) ipv4 = m.group(1);
          } else if (line.startsWith('status:')) {
            active = line.contains('active');
          }
        }
        result.add(NetInterface(name: name, ipv4: ipv4, active: active));
      } catch (_) {
        // Skip interfaces that error out.
      }
    }
    return result;
  }

  /// Lists established TCP connections via `lsof`, parsed into process + the
  /// `local->remote` NAME column. Capped at [cap] rows.
  Future<List<NetConnection>> readConnections({int cap = 60}) async {
    try {
      final r = await Shell.run(
        'lsof',
        const ['-nP', '-iTCP', '-sTCP:ESTABLISHED'],
        timeout: const Duration(seconds: 15),
      );
      if (r.out.isEmpty) return const [];

      final conns = <NetConnection>[];
      final seen = <String>{};
      final lines = const LineSplitter().convert(r.out);
      for (final line in lines) {
        if (line.startsWith('COMMAND')) continue; // header
        final fields = line.split(RegExp(r'\s+'));
        if (fields.length < 9) continue;
        final process = fields.first;

        // The NAME column holds 'local->remote'. Find the token with '->'.
        String? endpoint;
        for (final f in fields) {
          if (f.contains('->')) {
            endpoint = f;
            break;
          }
        }
        if (endpoint == null) continue;

        final parts = endpoint.split('->');
        if (parts.length != 2) continue;
        final local = parts[0];
        final remote = parts[1];

        final key = '$process|$remote';
        if (seen.contains(key)) continue;
        seen.add(key);

        conns.add(NetConnection(
          process: process,
          local: local,
          remote: remote,
        ));
        if (conns.length >= cap) break;
      }
      return conns;
    } catch (_) {
      return const [];
    }
  }

  /// Reads current Wi-Fi SSID/signal/rate from `system_profiler`. Returns an
  /// empty [WifiInfo] if the call is slow, empty, or unparseable.
  Future<WifiInfo> readWifi() async {
    try {
      final out = await Shell.out(
        'system_profiler',
        const ['SPAirPortDataType', '-json'],
        timeout: const Duration(seconds: 10),
      );
      if (out.isEmpty) return const WifiInfo();

      final decoded = json.decode(out);
      if (decoded is! Map) return const WifiInfo();

      final root = decoded['SPAirPortDataType'];
      if (root is! List) return const WifiInfo();

      for (final entry in root) {
        if (entry is! Map) continue;
        final ifaces = entry['spairport_airport_interfaces'];
        if (ifaces is! List) continue;
        for (final iface in ifaces) {
          if (iface is! Map) continue;
          final current = iface['spairport_current_network_information'];
          if (current is! Map) continue;

          final ssid = current['_name'];
          int? signal;
          final sn = current['spairport_signal_noise'];
          if (sn is String) {
            final m = RegExp(r'(-?\d+)\s*dBm').firstMatch(sn);
            if (m != null) signal = int.tryParse(m.group(1)!);
          }
          int? rate;
          final r = current['spairport_network_rate'];
          if (r is num) rate = r.toInt();

          return WifiInfo(
            ssid: ssid is String ? ssid : null,
            signalDbm: signal,
            rateMbps: rate,
          );
        }
      }
      return const WifiInfo();
    } catch (_) {
      return const WifiInfo();
    }
  }
}

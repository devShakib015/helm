/// A single live sample of system telemetry from the native `systemStats` call.
/// Pure data; no Flutter imports.
class SystemStats {
  const SystemStats({
    this.cpu = 0,
    this.cpuPerCore = const [],
    this.gpu = 0,
    this.memUsed = 0,
    this.memTotal = 0,
    this.netDown = 0,
    this.netUp = 0,
    this.diskTotal = 0,
    this.diskFree = 0,
    this.uptime = 0,
    this.tempCpu,
    this.tempGpu,
    this.fan,
    this.batteryPct,
    this.batteryCharging = false,
  });

  final double cpu; // 0..100 total
  final List<double> cpuPerCore; // 0..100 per logical core
  final double gpu; // 0..100
  final int memUsed;
  final int memTotal;
  final double netDown; // bytes/sec
  final double netUp; // bytes/sec
  final int diskTotal;
  final int diskFree;
  final double uptime; // seconds
  final double? tempCpu; // °C, null if unavailable
  final double? tempGpu;
  final double? fan; // rpm
  final int? batteryPct; // 0..100, null on desktops / read failure
  final bool batteryCharging; // true when on AC power

  double get memPct => memTotal > 0 ? memUsed / memTotal * 100 : 0;
  int get diskUsed => (diskTotal - diskFree).clamp(0, diskTotal);
  double get diskPct => diskTotal > 0 ? diskUsed / diskTotal * 100 : 0;

  static double _d(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);
  static int _i(Object? v) => v is num ? v.toInt() : 0;
  static double? _dn(Object? v) => v is num ? v.toDouble() : null;
  static int? _in(Object? v) => v is num ? v.toInt() : null;

  factory SystemStats.fromMap(Map<String, dynamic> m) {
    return SystemStats(
      cpu: _d(m['cpu']),
      cpuPerCore: (m['cpuPerCore'] as List?)?.map((e) => _d(e)).toList() ?? const [],
      gpu: _d(m['gpu']),
      memUsed: _i(m['memUsed']),
      memTotal: _i(m['memTotal']),
      netDown: _d(m['netDown']),
      netUp: _d(m['netUp']),
      diskTotal: _i(m['diskTotal']),
      diskFree: _i(m['diskFree']),
      uptime: _d(m['uptime']),
      tempCpu: _dn(m['tempCpu']),
      tempGpu: _dn(m['tempGpu']),
      fan: _dn(m['fan']),
      batteryPct: _in(m['batteryPct']),
      batteryCharging: m['batteryCharging'] == true,
    );
  }

  static const SystemStats empty = SystemStats();
}

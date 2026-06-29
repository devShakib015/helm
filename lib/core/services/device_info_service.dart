import 'shell.dart';
import 'native_bridge.dart';

/// Static facts about the machine + OS, for the Dashboard.
class DeviceInfo {
  const DeviceInfo({
    this.modelName = 'Mac',
    this.modelIdentifier = '',
    this.modelNumber = '',
    this.chip = '',
    this.coresTotal = 0,
    this.coresPerformance = 0,
    this.coresEfficiency = 0,
    this.memory = '',
    this.graphics = '',
    this.gpuCores = 0,
    this.serial = '',
    this.osName = 'macOS',
    this.osVersion = '',
    this.osBuild = '',
    this.diskName = 'Macintosh HD',
    this.diskTotalBytes = 0,
    this.displayResolution = '',
    this.displayRefresh = '',
    this.displaySize = '',
  });

  final String modelName;
  final String modelIdentifier;
  final String modelNumber;
  final String chip;
  final int coresTotal;
  final int coresPerformance;
  final int coresEfficiency;
  final String memory;
  final String graphics;
  final int gpuCores;
  final String serial;
  final String osName;
  final String osVersion;
  final String osBuild;
  final String diskName;
  final int diskTotalBytes;
  final String displayResolution;
  final String displayRefresh;
  final String displaySize;
}

class DeviceInfoService {
  static const Map<String, String> _osNames = {
    '26': 'Tahoe',
    '15': 'Sequoia',
    '14': 'Sonoma',
    '13': 'Ventura',
    '12': 'Monterey',
    '11': 'Big Sur',
  };

  Future<DeviceInfo> load() async {
    final hw = await Shell.out(
      'system_profiler',
      const ['SPHardwareDataType', 'SPDisplaysDataType', '-detailLevel', 'mini'],
      timeout: const Duration(seconds: 25),
    );
    final swName = await Shell.out('sw_vers', const ['-productName']);
    final swVer = await Shell.out('sw_vers', const ['-productVersion']);
    final swBuild = await Shell.out('sw_vers', const ['-buildVersion']);
    final vol = await NativeBridge.volumeInfo('/');

    String field(String label) {
      final m = RegExp('$label:\\s*(.+)').firstMatch(hw);
      return m?.group(1)?.trim() ?? '';
    }

    final coresRaw = field('Total Number of Cores'); // "10 (4 performance and 6 efficiency)"
    var total = 0, perf = 0, eff = 0;
    final totalM = RegExp(r'^(\d+)').firstMatch(coresRaw);
    if (totalM != null) total = int.tryParse(totalM.group(1)!) ?? 0;
    final peM = RegExp(r'(\d+)\s*performance.*?(\d+)\s*efficiency').firstMatch(coresRaw);
    if (peM != null) {
      perf = int.tryParse(peM.group(1)!) ?? 0;
      eff = int.tryParse(peM.group(2)!) ?? 0;
    }

    // Graphics: "Chipset Model" appears under SPDisplaysDataType.
    final chipset = field('Chipset Model');
    final coresGpuM = RegExp(r'Total Number of Cores:\s*(\d+)').allMatches(hw).toList();
    // The 2nd "Total Number of Cores" (if present) is usually the GPU.
    var gpuCores = 0;
    if (coresGpuM.length > 1) {
      gpuCores = int.tryParse(coresGpuM[1].group(1) ?? '') ?? 0;
    }

    // Display resolution: "Resolution: 3420 x 2224 ..." possibly with "@ 60Hz".
    final resM = RegExp(r'Resolution:\s*([0-9]+\s*x\s*[0-9]+)([^\n]*)').firstMatch(hw);
    var resolution = '';
    var refresh = '';
    if (resM != null) {
      resolution = resM.group(1)!.replaceAll(RegExp(r'\s+'), '');
      final tail = resM.group(2) ?? '';
      final hz = RegExp(r'(\d+(?:\.\d+)?)\s*Hz').firstMatch(tail);
      if (hz != null) refresh = '${hz.group(1)} Hz';
    }

    final verMajor = swVer.trim().split('.').first;
    final marketing = _osNames[verMajor];

    return DeviceInfo(
      modelName: field('Model Name').isEmpty ? 'Mac' : field('Model Name'),
      modelIdentifier: field('Model Identifier'),
      modelNumber: field('Model Number'),
      chip: field('Chip'),
      coresTotal: total,
      coresPerformance: perf,
      coresEfficiency: eff,
      memory: field('Memory'),
      graphics: chipset.isEmpty ? field('Chip') : chipset,
      gpuCores: gpuCores,
      serial: field('Serial Number (system)'),
      osName: marketing != null ? 'macOS $marketing' : (swName.trim().isEmpty ? 'macOS' : swName.trim()),
      osVersion: swVer.trim(),
      osBuild: swBuild.trim(),
      diskName: (vol?['name'] as String?) ?? 'Macintosh HD',
      diskTotalBytes: (vol?['total'] as int?) ?? 0,
      displayResolution: resolution,
      displayRefresh: refresh,
      displaySize: '',
    );
  }
}

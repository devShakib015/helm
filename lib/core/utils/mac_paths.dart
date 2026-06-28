import 'dart:io';

/// Central catalogue of well-known macOS file-system locations.
///
/// Everything is derived from `$HOME` at runtime so the same build works for
/// any user account. Paths that don't exist on a given machine are simply
/// skipped by the scanners — this is just the master list of "places to look".
class MacPaths {
  MacPaths._();

  static final String home =
      Platform.environment['HOME'] ?? '/Users/${Platform.environment['USER'] ?? 'user'}';

  // ---- Top-level user folders --------------------------------------------
  static String get desktop => '$home/Desktop';
  static String get documents => '$home/Documents';
  static String get downloads => '$home/Downloads';
  static String get pictures => '$home/Pictures';
  static String get music => '$home/Music';
  static String get movies => '$home/Movies';
  static String get publicFolder => '$home/Public';

  // ---- Library ------------------------------------------------------------
  static String get userLibrary => '$home/Library';
  static String get userCaches => '$home/Library/Caches';
  static String get userLogs => '$home/Library/Logs';
  static String get userAppSupport => '$home/Library/Application Support';
  static String get userContainers => '$home/Library/Containers';
  static String get userGroupContainers => '$home/Library/Group Containers';
  static String get userPreferences => '$home/Library/Preferences';
  static String get savedAppState => '$home/Library/Saved Application State';
  static String get userMail => '$home/Library/Mail';
  static String get userMessages => '$home/Library/Messages';
  static String get mobileSync =>
      '$home/Library/Application Support/MobileSync/Backup';

  static const String systemLibrary = '/Library';
  static const String systemCaches = '/Library/Caches';
  static const String systemLogs = '/Library/Logs';
  static const String varLog = '/private/var/log';
  static const String varFolders = '/private/var/folders';

  // ---- Trash --------------------------------------------------------------
  static String get userTrash => '$home/.Trash';

  // ---- Applications -------------------------------------------------------
  static const String systemApplications = '/Applications';
  static String get userApplications => '$home/Applications';

  // ---- Developer junk -----------------------------------------------------
  static String get xcodeDeveloper => '$home/Library/Developer/Xcode';
  static String get xcodeDerivedData =>
      '$home/Library/Developer/Xcode/DerivedData';
  static String get xcodeArchives => '$home/Library/Developer/Xcode/Archives';
  static String get xcodeDeviceSupport =>
      '$home/Library/Developer/Xcode/iOS DeviceSupport';
  static String get xcodeWatchSupport =>
      '$home/Library/Developer/Xcode/watchOS DeviceSupport';
  static String get coreSimulator =>
      '$home/Library/Developer/CoreSimulator/Devices';
  static String get coreSimulatorCaches =>
      '$home/Library/Developer/CoreSimulator/Caches';
  static String get xcodePreviews =>
      '$home/Library/Developer/Xcode/UserData/Previews';

  static String get npmCache => '$home/.npm/_cacache';
  static String get npmCacheRoot => '$home/.npm';
  static String get yarnCache => '$home/Library/Caches/Yarn';
  static String get pnpmStore => '$home/Library/pnpm/store';
  static String get gradleCache => '$home/.gradle/caches';
  static String get pipCache => '$home/Library/Caches/pip';
  static String get pubCache => '$home/.pub-cache';
  static String get cocoapodsCache => '$home/Library/Caches/CocoaPods';
  static String get carthageCache => '$home/Library/Caches/org.carthage.CarthageKit';
  static String get goCache => '$home/Library/Caches/go-build';
  static String get cargoCache => '$home/.cargo/registry/cache';
  static String get composerCache => '$home/.composer/cache';
  static String get homebrewCache => '$home/Library/Caches/Homebrew';
  static String get dockerData => '$home/Library/Containers/com.docker.docker/Data';

  /// Developer junk groups: (displayName, path).
  static List<({String name, String path})> developerCaches() => [
        (name: 'Xcode DerivedData', path: xcodeDerivedData),
        (name: 'Xcode Archives', path: xcodeArchives),
        (name: 'iOS DeviceSupport', path: xcodeDeviceSupport),
        (name: 'watchOS DeviceSupport', path: xcodeWatchSupport),
        (name: 'iOS Simulators', path: coreSimulator),
        (name: 'Simulator Caches', path: coreSimulatorCaches),
        (name: 'Xcode Previews', path: xcodePreviews),
        (name: 'npm cache', path: npmCache),
        (name: 'Yarn cache', path: yarnCache),
        (name: 'pnpm store', path: pnpmStore),
        (name: 'Gradle cache', path: gradleCache),
        (name: 'pip cache', path: pipCache),
        (name: 'CocoaPods cache', path: cocoapodsCache),
        (name: 'Carthage cache', path: carthageCache),
        (name: 'Go build cache', path: goCache),
        (name: 'Cargo cache', path: cargoCache),
        (name: 'Composer cache', path: composerCache),
        (name: 'Homebrew cache', path: homebrewCache),
      ];

  // ---- Browser caches -----------------------------------------------------
  static List<({String name, String path})> browserCaches() => [
        (name: 'Safari Caches', path: '$home/Library/Caches/com.apple.Safari'),
        (name: 'Google Chrome', path: '$home/Library/Caches/Google/Chrome'),
        (
          name: 'Chrome Service Worker',
          path:
              '$home/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage'
        ),
        (name: 'Brave', path: '$home/Library/Caches/BraveSoftware/Brave-Browser'),
        (name: 'Microsoft Edge', path: '$home/Library/Caches/Microsoft Edge'),
        (name: 'Arc', path: '$home/Library/Caches/company.thebrowser.Browser'),
        (
          name: 'Firefox',
          path: '$home/Library/Caches/Firefox/Profiles'
        ),
        (name: 'Opera', path: '$home/Library/Caches/com.operasoftware.Opera'),
      ];

  /// TCC-protected location used to probe Full Disk Access. Present on every
  /// account; readable only when Helm has Full Disk Access.
  static String get tccProbe =>
      '$home/Library/Application Support/com.apple.TCC/TCC.db';

  /// Secondary probes in case the primary is absent.
  static List<String> get fdaProbePaths => [
        tccProbe,
        '$home/Library/Mail',
        '$home/Library/Safari',
        '$home/Library/Messages',
        '$home/Library/Cookies',
      ];

  /// Directories Helm must never recurse into or offer for deletion — touching
  /// these can break the OS or the running app itself.
  static const Set<String> protectedRoots = {
    '/System',
    '/usr',
    '/bin',
    '/sbin',
    '/private/var/db',
    '/private/var/vm',
    '/.vol',
    '/dev',
    '/cores',
    '/Network',
  };

  /// Returns true if [path] is inside a protected OS location.
  static bool isProtected(String path) {
    for (final root in protectedRoots) {
      if (path == root || path.startsWith('$root/')) return true;
    }
    return false;
  }
}

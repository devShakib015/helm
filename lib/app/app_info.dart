/// Static product and author metadata, surfaced in Settings ▸ About and the
/// About dialog. Values here are the single source of truth — nothing about
/// the author is hardcoded in the UI.
class AppInfo {
  AppInfo._();

  // ---- Product ------------------------------------------------------------
  static const String name = 'Helm';
  static const String version = '1.5.1';
  static const String tagline =
      'Take the helm of your Mac. Fifteen native tools in one window — '
      'storage, monitoring, clipboard and more.';

  /// Helm's standing promise to its users. Deliberately part of the product
  /// metadata, not marketing copy: every feature is free, permanently.
  static const String freePledge =
      'Free forever — every feature, no paid tier, no accounts, no telemetry.';

  static const String license = 'MIT License';
  static const String copyright = '© 2026 K M Shahriar Hossain';

  // ---- Author -------------------------------------------------------------
  static const String author = 'K M Shahriar Hossain';
  static const String authorHandle = 'devShakib';
  static const String authorRole = 'CTO at Shpper';

  // ---- Links --------------------------------------------------------------
  static const String portfolio = 'https://devshakib.jumyn.com';
  static const String repo = 'https://github.com/devShakib015/helm';
  static const String releases =
      'https://github.com/devShakib015/helm/releases/latest';
  static const String issues =
      'https://github.com/devShakib015/helm/issues/new';

  /// Where to find the author. Order is the order shown in the UI.
  static const List<({String label, String url})> authorLinks = [
    (label: 'Portfolio', url: portfolio),
    (label: 'GitHub', url: 'https://github.com/devShakib015'),
    (label: 'pub.dev', url: 'https://pub.dev/publishers/jumyn.com/packages'),
    (label: 'X', url: 'https://x.com/devshakib015'),
    (label: 'dev.to', url: 'https://dev.to/devshakib'),
    (label: 'Instagram', url: 'https://www.instagram.com/devshakib/'),
  ];
}

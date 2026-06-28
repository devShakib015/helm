/// Where a startup entry comes from. The kind determines whether Helm can
/// safely modify it without root and how it's grouped in the UI.
enum StartupKind {
  /// A classic "Login Item" managed by System Events (the list in
  /// System Settings ▸ General ▸ Login Items).
  loginItem,

  /// A LaunchAgent in the user's `~/Library/LaunchAgents` — runs at login for
  /// this user. Modifiable without root.
  userAgent,

  /// A LaunchAgent in `/Library/LaunchAgents` — runs for every user. Removing
  /// it needs root, so Helm treats it as read-only.
  systemAgent,

  /// A LaunchDaemon in `/Library/LaunchDaemons` — runs at boot as root.
  /// Read-only.
  systemDaemon,
}

/// One thing that launches automatically at login or boot.
class StartupItem {
  StartupItem({
    required this.name,
    required this.path,
    required this.kind,
    this.enabled = true,
    this.canModify = false,
  });

  /// Display name — the login item's name, or the agent/daemon Label (falls
  /// back to the plist filename).
  final String name;

  /// The on-disk path (the app path for login items, the plist path for
  /// agents/daemons). May be empty for login items whose path can't be read.
  final String path;

  final StartupKind kind;

  /// Whether the entry is currently active. User agents with a `Disabled`
  /// key set to true read as disabled.
  final bool enabled;

  /// Whether Helm can remove this without administrator privileges.
  final bool canModify;
}

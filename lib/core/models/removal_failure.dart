/// Why one path could not be removed.
///
/// Helm used to report removals as a bare count — "Moved 3 items to Trash · 1
/// skipped" — because the Swift side caught the error from `trashItem` and threw
/// it away. That is unhelpful in the ordinary case and actively misleading in
/// the most common one: an app installed from a `.pkg` leaves a launch agent or
/// a helper tool under `/Library`, which is `root:wheel` and not writable by the
/// user, so the removal is refused every single time and the app can only say
/// "skipped". The reason is the whole message.
enum RemovalReason {
  /// The OS refused: the item, or the folder holding it, belongs to another
  /// user — almost always `root`. `/Library/LaunchAgents`, `/Library/
  /// LaunchDaemons`, `/Library/PrivilegedHelperTools`, `/Library/Application
  /// Support` and `/Library/Preferences` are all like this on a stock Mac.
  permission,

  /// Nothing there to remove. Reported for completeness; the native side now
  /// counts this as success, since it is the outcome the caller wanted.
  notFound,

  /// Something has the file open, or it is on a read-only volume.
  inUse,

  /// Helm's own guard refused the path — a container root, an OS internal, or
  /// something malformed. Never the user's fault and never silent.
  guarded,

  /// The OS gave a reason Helm does not classify. [RemovalFailure.message]
  /// carries its exact words rather than a guess.
  unknown,
}

/// One refused path, with the OS's own explanation attached.
class RemovalFailure {
  const RemovalFailure({
    required this.path,
    required this.reason,
    required this.message,
  });

  /// Helm's guard refused this one before it ever reached the OS.
  RemovalFailure.guarded(this.path)
      : reason = RemovalReason.guarded,
        message = 'Refused by Helm’s safety guard.';

  final String path;
  final RemovalReason reason;

  /// The system's own words, or Helm's for [RemovalReason.guarded]. Shown to
  /// the user verbatim — a paraphrase here would be a guess about someone
  /// else's error.
  final String message;

  /// Classifies an `NSError` from `FileManager.trashItem`.
  ///
  /// The codes are `NSCocoaErrorDomain`'s: 513 `NSFileWriteNoPermissionError`,
  /// 257 `NSFileReadNoPermissionError`, 4 `NSFileNoSuchFileError`, 516
  /// `NSFileWriteFileExistsError`, 640 `NSFileWriteVolumeReadOnlyError`. The
  /// POSIX errno underneath is checked too, because Foundation does not always
  /// map one to the other.
  factory RemovalFailure.fromNative(Map<Object?, Object?> raw) {
    final path = (raw['path'] as String?) ?? '';
    final code = (raw['code'] as num?)?.toInt() ?? 0;
    final domain = (raw['domain'] as String?) ?? '';
    final message = (raw['message'] as String?)?.trim();
    final underCode = (raw['underlyingCode'] as num?)?.toInt();
    final underDomain = (raw['underlyingDomain'] as String?) ?? '';

    const eperm = 1, eacces = 13, ebusy = 16, erofs = 30, enoent = 2;
    final posix = underDomain == 'NSPOSIXErrorDomain' ? underCode : null;

    final reason = switch (true) {
      _ when domain == 'NSCocoaErrorDomain' && (code == 513 || code == 257) =>
        RemovalReason.permission,
      _ when domain == 'NSCocoaErrorDomain' && code == 4 =>
        RemovalReason.notFound,
      _ when domain == 'NSCocoaErrorDomain' && code == 640 =>
        RemovalReason.inUse,
      _ when posix == eperm || posix == eacces => RemovalReason.permission,
      _ when posix == ebusy || posix == erofs => RemovalReason.inUse,
      _ when posix == enoent => RemovalReason.notFound,
      _ => RemovalReason.unknown,
    };

    return RemovalFailure(
      path: path,
      reason: reason,
      message: (message == null || message.isEmpty)
          ? 'The system refused this item without giving a reason.'
          : message,
    );
  }

  /// True when an administrator password would have made the difference. This
  /// is what the UI needs to say out loud, because the user's next question is
  /// always "so how do I remove it".
  bool get needsAdmin => reason == RemovalReason.permission;

  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}

/// A one-line summary of [failures], suitable for a snackbar.
///
/// Leads with the reason rather than the count: "1 skipped" was the old
/// message, and it is the part that told the user nothing.
String summariseFailures(List<RemovalFailure> failures) {
  if (failures.isEmpty) return '';
  final admin = failures.where((f) => f.needsAdmin).length;
  final n = failures.length;
  final items = n == 1 ? 'item' : 'items';
  if (admin == n) {
    return n == 1
        ? '1 item needs an administrator to remove'
        : '$n items need an administrator to remove';
  }
  if (admin > 0) {
    return '$n $items skipped · $admin need an administrator';
  }
  return '$n $items skipped · ${failures.first.message}';
}

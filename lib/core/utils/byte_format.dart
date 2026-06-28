/// Human-readable byte formatting.
///
/// macOS (Finder, About This Mac, System Settings) reports sizes in **decimal**
/// units since OS X 10.6 — 1 KB = 1000 bytes. Helm matches that everywhere so
/// the numbers we show line up with what the user sees in Finder.
library;

const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

/// Splits a byte count into a numeric string and its unit, e.g. `(1.2, 'GB')`.
({String value, String unit}) formatBytesParts(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return (value: '0', unit: 'B');
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1000 && unitIndex < _units.length - 1) {
    size /= 1000;
    unitIndex++;
  }
  // Whole numbers and bytes/KB read cleaner without trailing decimals.
  final useDecimals = unitIndex >= 2 && size < 100;
  final str = useDecimals
      ? size.toStringAsFixed(decimals)
      : size.toStringAsFixed(0);
  // Trim a trailing ".0".
  final trimmed = str.endsWith('.0') ? str.substring(0, str.length - 2) : str;
  return (value: trimmed, unit: _units[unitIndex]);
}

/// Full formatted string, e.g. `1.2 GB`.
String formatBytes(int bytes, {int decimals = 1}) {
  final p = formatBytesParts(bytes, decimals: decimals);
  return '${p.value} ${p.unit}';
}

/// Compact count with thousands separators, e.g. `12,403`.
String formatCount(int count) {
  final s = count.abs().toString();
  final buf = StringBuffer(count < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// A short relative age like `3 days ago`, `2 years ago`, or `today`.
String formatAge(DateTime? when, {DateTime? now}) {
  if (when == null) return 'unknown';
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);
  if (diff.isNegative) return 'just now';
  final days = diff.inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  if (days < 365) {
    final months = (days / 30).floor();
    return months == 1 ? '1 month ago' : '$months months ago';
  }
  final years = (days / 365).floor();
  return years == 1 ? '1 year ago' : '$years years ago';
}

/// Short date like `Jun 28, 2026`.
String formatDate(DateTime? when) {
  if (when == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[when.month - 1]} ${when.day}, ${when.year}';
}

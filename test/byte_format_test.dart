import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/utils/byte_format.dart';

void main() {
  group('formatBytes (decimal, Finder-style)', () {
    test('formats bytes, KB, MB, GB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1000), '1 KB');
      expect(formatBytes(1500), '2 KB');
      expect(formatBytes(1000 * 1000), '1 MB');
      expect(formatBytes(1500 * 1000 * 1000), '1.5 GB');
    });

    test('parts split value and unit', () {
      final p = formatBytesParts(2 * 1000 * 1000 * 1000);
      expect(p.value, '2');
      expect(p.unit, 'GB');
    });
  });

  group('formatCount', () {
    test('adds thousands separators', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(12403), '12,403');
      expect(formatCount(1000000), '1,000,000');
    });
  });

  group('formatAge', () {
    test('handles recent and old dates', () {
      final now = DateTime(2026, 6, 28);
      expect(formatAge(now, now: now), 'today');
      expect(formatAge(now.subtract(const Duration(days: 1)), now: now), 'yesterday');
      expect(formatAge(now.subtract(const Duration(days: 400)), now: now), '1 year ago');
      expect(formatAge(null), 'unknown');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/models/cleanable_group.dart';

/// The cleaner's selection rules decide what a single "Clean Up" click
/// removes. A regression here silently deletes things the user never ticked —
/// which is exactly the bug class that once put Xcode Archives and iOS
/// Simulators into a one-click sweep.
CleanableItem _item(String name, CleanupRisk risk) => CleanableItem(
      path: '/tmp/$name',
      name: name,
      sizeBytes: 100,
      risk: risk,
    );

CleanableGroup _group(List<CleanableItem> items,
        {CleanupRisk risk = CleanupRisk.safe}) =>
    CleanableGroup(
      kind: CleanupKind.developerJunk,
      title: 'Test',
      description: '',
      risk: risk,
      items: items,
    );

void main() {
  group('default selection', () {
    test('safe items start ticked, caution items do not', () {
      final safe = _item('derived-data', CleanupRisk.safe);
      final caution = _item('xcode-archives', CleanupRisk.caution);
      expect(safe.selected, isTrue);
      expect(caution.selected, isFalse,
          reason: 'risky items must be an explicit, deliberate choice');
    });
  });

  group('group checkbox on a MIXED group', () {
    late CleanableGroup g;
    setUp(() {
      g = _group([
        _item('derived-data', CleanupRisk.safe),
        _item('npm-cache', CleanupRisk.safe),
        _item('xcode-archives', CleanupRisk.caution),
        _item('ios-simulators', CleanupRisk.caution),
      ]);
    });

    test('ticking it selects ONLY the safe items', () {
      g.selectAll(true);
      final picked = g.items.where((i) => i.selected).map((i) => i.name).toSet();
      expect(picked, {'derived-data', 'npm-cache'});
    });

    test('unticking clears everything, including caution items', () {
      for (final i in g.items) {
        i.selected = true;
      }
      g.selectAll(false);
      expect(g.items.every((i) => !i.selected), isTrue);
      expect(g.noneSelected, isTrue);
    });

    test('allSelected stays false while caution items are untouched', () {
      g.selectAll(true);
      expect(g.allSelected, isFalse,
          reason: 'a full checkmark would misrepresent what will be deleted');
    });

    test('allSelected is true only when literally everything is ticked', () {
      for (final i in g.items) {
        i.selected = true;
      }
      expect(g.allSelected, isTrue);
    });

    test('selectedBytes counts only what is actually ticked', () {
      g.selectAll(true);
      expect(g.selectedCount, 2);
      expect(g.selectedBytes, 200);
      expect(g.totalBytes, 400);
    });
  });

  group('group checkbox on a UNIFORMLY caution group', () {
    test('ticking the header selects all — it is already a single explicit '
        'risk decision', () {
      final g = _group(
        [
          _item('old-download-a', CleanupRisk.caution),
          _item('old-download-b', CleanupRisk.caution),
        ],
        risk: CleanupRisk.caution,
      );
      g.selectAll(true);
      expect(g.items.every((i) => i.selected), isTrue);
    });
  });

  group('"Select Safe" sweep', () {
    test('never ticks caution items, even in an all-caution group', () {
      // The regression that shipped once: the uniform-caution fallback made a
      // broad "Select Safe" sweep tick release archives and simulators.
      final g = _group(
        [
          _item('xcode-archives', CleanupRisk.caution),
          _item('ios-simulators', CleanupRisk.caution),
        ],
        risk: CleanupRisk.safe,
      );
      g.selectSafeOnly();
      expect(g.items.every((i) => !i.selected), isTrue,
          reason: 'a broad sweep must never pick up risky items');
      expect(g.selectedBytes, 0);
    });

    test('ticks exactly the safe items in a mixed group', () {
      final g = _group([
        _item('caches', CleanupRisk.safe),
        _item('archives', CleanupRisk.caution),
      ]);
      for (final i in g.items) {
        i.selected = true; // start dirty
      }
      g.selectSafeOnly();
      expect(g.items.firstWhere((i) => i.name == 'caches').selected, isTrue);
      expect(g.items.firstWhere((i) => i.name == 'archives').selected, isFalse);
    });
  });

  group('empty group', () {
    test('is inert and never reports itself as fully selected', () {
      final g = _group([]);
      expect(g.isEmpty, isTrue);
      expect(g.allSelected, isFalse);
      expect(g.noneSelected, isTrue);
      g.selectAll(true);
      expect(g.selectedBytes, 0);
    });
  });
}

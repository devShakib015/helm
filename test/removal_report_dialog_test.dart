import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/models/removal_failure.dart';
import 'package:helm/core/widgets/confirm.dart';

/// The report is shown at the exact moment something already went wrong, so it
/// has to be the one thing in the app that cannot itself fail. These check it
/// renders, says the useful sentence, and does not overflow on the long paths
/// it exists to display.
void main() {
  RemovalFailure perm(String path) => RemovalFailure(
        path: path,
        reason: RemovalReason.permission,
        message: '“${path.split('/').last}” couldn’t be moved to the trash '
            'because you don’t have permission to access it.',
      );

  Future<void> show(
    WidgetTester tester, {
    required int removed,
    required List<RemovalFailure> failed,
    Size size = const Size(1200, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showRemovalReport(context, removed: removed, failed: failed),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is shown when nothing failed', (tester) async {
    await show(tester, removed: 5, failed: const []);
    expect(find.textContaining('could not be removed'), findsNothing);
  });

  testWidgets('the admin case names the remedy, not just the count',
      (tester) async {
    await show(tester, removed: 3, failed: [
      perm('/Library/LaunchAgents/com.example.helper.plist'),
      perm('/Library/PrivilegedHelperTools/com.example.helper'),
    ]);

    expect(find.text('2 items could not be removed'), findsOneWidget);
    expect(find.textContaining('Need an administrator'), findsOneWidget);
    expect(find.textContaining('not as an administrator'), findsOneWidget);
    // Hedged, because the error says the OS refused — not why.
    expect(find.textContaining('Usually that is because'), findsOneWidget);
    // The old dead end, and the wrong guess that used to stand in for it.
    expect(find.textContaining('Full Disk Access'), findsNothing);
    // Both items named, so the user can go and deal with them.
    expect(find.text('com.example.helper.plist'), findsOneWidget);
    expect(find.text('com.example.helper'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('singular reads as English', (tester) async {
    await show(tester, removed: 4, failed: [perm('/Library/x/y.plist')]);
    expect(find.text('One item could not be removed'), findsOneWidget);
    expect(find.textContaining('Needs an administrator'), findsOneWidget);
  });

  testWidgets('when nothing at all was removed it says so', (tester) async {
    await show(tester, removed: 0, failed: [perm('/Library/x/y.plist')]);
    expect(find.textContaining('Nothing was removed'), findsOneWidget);
  });

  testWidgets('a long list is capped and the remainder counted, not dropped',
      (tester) async {
    await show(tester, removed: 1, failed: [
      for (var i = 0; i < 10; i++) perm('/Library/LaunchAgents/item$i.plist'),
    ]);
    expect(find.text('10 items could not be removed'), findsOneWidget);
    expect(find.text('and 4 more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed reasons are separated so the actionable half stands out',
      (tester) async {
    await show(tester, removed: 2, failed: [
      perm('/Library/LaunchAgents/a.plist'),
      const RemovalFailure(
        path: '/Volumes/ReadOnly/b',
        reason: RemovalReason.inUse,
        message: 'The volume is read only.',
      ),
    ]);
    expect(find.textContaining('Needs an administrator'), findsOneWidget);
    expect(find.textContaining('Other reason'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('very long paths do not overflow the dialog', (tester) async {
    final deep = '/Library/Application Support/'
        '${'a-very-long-vendor-folder-name/' * 8}trailing-item.plist';
    await show(tester, removed: 0, failed: [perm(deep)],
        size: const Size(900, 700));
    expect(tester.takeException(), isNull);
  });
}

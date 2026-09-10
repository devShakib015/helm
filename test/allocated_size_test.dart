@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helm/tools/storage/engine/fs_util.dart';
import 'package:helm/tools/storage/engine/native_stat.dart';

/// The storage tool answers "what does this cost me", not "what does this
/// contain". Everything below is a case where those two numbers disagree, and
/// where summing `st_size` — which is what shipped through v1.5.1 — gives an
/// answer that contradicts About This Mac.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('helm_alloc_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Sum of `st_blocks * 512` over every regular file under [dir], read from
  /// /usr/bin/stat rather than from the code under test. Ground truth has to
  /// come from somewhere other than the thing being tested.
  int duBytesOfFiles(Directory dir) {
    final files = dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
    if (files.isEmpty) return 0;
    final res = Process.runSync('/usr/bin/stat', ['-f', '%b', ...files]);
    expect(res.exitCode, 0, reason: 'stat(1) failed: ${res.stderr}');
    return (res.stdout as String)
        .trim()
        .split('\n')
        .map((l) => int.parse(l.trim()) * 512)
        .fold(0, (a, b) => a + b);
  }

  test('the native lstat path is actually in use', () {
    // Without this the rest of the file would pass trivially: factsFor falls
    // back to Dart's stat, where allocatedBytes degrades to st_size and every
    // assertion below about the two disagreeing would be testing nothing.
    expect(nativeStatAvailable, isTrue,
        reason: 'FFI lstat did not resolve or failed its ABI self-check, so '
            'sizes silently fell back to st_size');
  });

  test('a zero-byte file holding a resource fork is not free', () {
    // This is the Icon\r that macOS writes into every folder with a custom
    // icon, reproduced without depending on one existing: the icon lives in
    // com.apple.ResourceFork, which st_size does not describe.
    final f = File('${tmp.path}/forked.bin')..createSync();
    final res = Process.runSync(
      '/usr/bin/xattr',
      ['-w', 'com.apple.ResourceFork', 'A' * 60000, f.path],
    );
    expect(res.exitCode, 0, reason: 'xattr failed: ${res.stderr}');

    final facts = factsFor(f.path)!;
    expect(facts.logicalBytes, 0, reason: 'the data fork really is empty');
    expect(facts.allocatedBytes, greaterThanOrEqualTo(60000),
        reason: 'the fork occupies real blocks and must be counted');
    expect(facts.allocatedBytes, duBytesOfFiles(tmp));
  });

  test('a sparse file is not charged for the hole', () {
    final f = File('${tmp.path}/sparse.bin');
    f.openSync(mode: FileMode.write)
      ..setPositionSync(50 * 1024 * 1024 - 1)
      ..writeByteSync(0)
      ..closeSync();

    final facts = factsFor(f.path)!;
    expect(facts.logicalBytes, 50 * 1024 * 1024);
    expect(facts.allocatedBytes, lessThan(facts.logicalBytes),
        reason: 'a hole occupies no blocks');
    expect(facts.allocatedBytes, duBytesOfFiles(tmp));
  });

  test('an ordinary file is charged to the block boundary', () {
    final f = File('${tmp.path}/plain.txt')..writeAsStringSync('x' * 100);
    final facts = factsFor(f.path)!;
    expect(facts.logicalBytes, 100);
    expect(facts.allocatedBytes % 512, 0, reason: 'st_blocks is a block count');
    expect(facts.allocatedBytes, greaterThanOrEqualTo(facts.logicalBytes));
  });

  test('FsUtil totals agree with what the disk actually reports', () {
    // A tree mixing all three divergences, walked by the real scanner.
    Directory('${tmp.path}/a/b').createSync(recursive: true);
    File('${tmp.path}/a/plain.txt').writeAsStringSync('y' * 5000);
    File('${tmp.path}/a/b/plain2.txt').writeAsStringSync('z' * 20000);

    final sparse = File('${tmp.path}/a/sparse.bin');
    sparse.openSync(mode: FileMode.write)
      ..setPositionSync(20 * 1024 * 1024 - 1)
      ..writeByteSync(0)
      ..closeSync();

    final forked = File('${tmp.path}/a/b/forked.bin')..createSync();
    Process.runSync('/usr/bin/xattr',
        ['-w', 'com.apple.ResourceFork', 'A' * 60000, forked.path]);

    final truth = duBytesOfFiles(tmp);

    final measured = FsUtil.measure('${tmp.path}/a');
    expect(measured.bytes, truth);
    expect(measured.files, 4);

    // walkTree builds the treemap, so it has to reach the same total by a
    // different route — per-node aggregation rather than a flat sum.
    final tree = FsUtil.walkTree('${tmp.path}/a', maxDepth: 8);
    expect(tree.sizeBytes, truth);
    expect(tree.fileCount, 4);

    // And the same again through sizedChildren, which feeds the cleaner lists.
    final children = FsUtil.sizedChildren('${tmp.path}/a');
    expect(children.fold<int>(0, (s, c) => s + c.bytes), truth);

    // The headline: summing st_size instead would have been wrong by more than
    // the entire real total, in both directions at once.
    final logical = tmp
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .fold<int>(0, (s, f) => s + f.statSync().size);
    expect(logical, greaterThan(truth * 10),
        reason: 'the sparse file alone should blow the st_size sum apart');
  });

  test('an unreadable path reports nothing rather than zero', () {
    expect(factsFor('${tmp.path}/does-not-exist'), isNull);
  });
}

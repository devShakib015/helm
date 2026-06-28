import 'dart:io';

import '../../../core/models/scan_node.dart';
import '../../../core/models/storage_category.dart';
import '../../../core/utils/mac_paths.dart';
import 'fs_util.dart';
import 'scan_session.dart';

/// One bucket of the category plan: which [CategoryKind] and which roots feed
/// it. Roots are deliberately mutually disjoint (no root is an ancestor of
/// another) so category sizes never double-count.
class _CatPlan {
  const _CatPlan(this.kind, this.paths);
  final CategoryKind kind;
  final List<String> paths;
}

List<_CatPlan> _plan() => [
      _CatPlan(CategoryKind.applications,
          [MacPaths.systemApplications, MacPaths.userApplications]),
      _CatPlan(CategoryKind.documents, [MacPaths.documents]),
      _CatPlan(CategoryKind.desktop, [MacPaths.desktop]),
      _CatPlan(CategoryKind.downloads, [MacPaths.downloads]),
      _CatPlan(CategoryKind.photos, [MacPaths.pictures]),
      _CatPlan(CategoryKind.music, [MacPaths.music]),
      _CatPlan(CategoryKind.movies, [MacPaths.movies]),
      _CatPlan(CategoryKind.mail, [MacPaths.userMail]),
      _CatPlan(CategoryKind.messages, [MacPaths.userMessages]),
      _CatPlan(CategoryKind.developer, [
        MacPaths.xcodeDeveloper, // ~/Library/Developer (DerivedData, sims, …)
        MacPaths.gradleCache,
        MacPaths.pubCache,
        '${MacPaths.home}/.cargo',
        MacPaths.npmCacheRoot,
        '${MacPaths.home}/.composer',
      ]),
      _CatPlan(CategoryKind.caches,
          [MacPaths.userCaches, MacPaths.systemCaches]),
      _CatPlan(CategoryKind.trash, [MacPaths.userTrash]),
    ];

/// Isolate entry point for the full category scan.
void categoryScanEntry(ScanBoot<int> boot) {
  final send = boot.sendPort;
  final maxDepth = boot.arg;

  var pendBytes = 0;
  var pendFiles = 0;
  String? pendPath;

  void flush({bool force = false}) {
    if (force || pendFiles >= 1200) {
      send.send(ScanTick(bytes: pendBytes, files: pendFiles, path: pendPath));
      pendBytes = 0;
      pendFiles = 0;
    }
  }

  void onProg(int b, int f, String? dir) {
    pendBytes += b;
    pendFiles += f;
    if (dir != null) pendPath = dir;
    flush();
  }

  final results = <StorageCategory>[];

  for (final plan in _plan()) {
    final roots = <ScanNode>[];
    var size = 0;
    var count = 0;
    var denied = false;

    for (final p in plan.paths) {
      if (FileSystemEntity.typeSync(p, followLinks: false) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      final tree = FsUtil.walkTree(p, maxDepth: maxDepth, onProgress: onProg);
      roots.add(tree);
      size += tree.sizeBytes;
      count += tree.fileCount;
      if (tree.accessDenied) denied = true;
    }

    ScanNode? root;
    if (roots.length == 1) {
      root = roots.first;
    } else if (roots.length > 1) {
      root = ScanNode(
        path: plan.paths.first,
        name: plan.kind.name,
        isDirectory: true,
        sizeBytes: size,
        fileCount: count,
        children: roots,
      );
    }
    root?.collapseSmall(keep: 250);
    root?.sortBySize();

    results.add(StorageCategory(
      kind: plan.kind,
      sizeBytes: size,
      itemCount: count,
      paths: plan.paths,
      root: root,
      accessDenied: denied,
    ));
    flush(force: true);
  }

  send.send(ScanResultMsg(results));
}

/// Drives a full category scan in a background isolate.
class CategoryScanner {
  ScanSession<List<StorageCategory>> start({int maxDepth = 8}) {
    return startScan<int, List<StorageCategory>>(categoryScanEntry, maxDepth);
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/scan_node.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/hoverable.dart';

class _Tile {
  _Tile(this.node, this.rect, this.color);
  final ScanNode node;
  final Rect rect;
  final Color color;
}

const _palette = [
  Color(0xFF5AC8FA),
  Color(0xFF5E9EFF),
  Color(0xFF7B61FF),
  Color(0xFFA78BFA),
  Color(0xFFFB7185),
  Color(0xFFFB923C),
  Color(0xFFFBBF24),
  Color(0xFF34D399),
  Color(0xFF22D3EE),
  Color(0xFFC084FC),
];

/// Squarified treemap. Each child of the current folder becomes a tile sized by
/// its share of the total; tapping a folder drills in.
class Treemap extends StatelessWidget {
  const Treemap({
    super.key,
    required this.nodes,
    required this.onTap,
    this.maxTiles = 42,
  });

  final List<ScanNode> nodes;
  final ValueChanged<ScanNode> onTap;
  final int maxTiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final tiles = _layout(size);
        if (tiles.isEmpty) {
          return const SizedBox.expand();
        }
        return Stack(
          children: [
            for (final tile in tiles)
              Positioned.fromRect(
                rect: tile.rect.deflate(1.5),
                child: _TreemapCell(tile: tile, onTap: () => onTap(tile.node)),
              ),
          ],
        );
      },
    );
  }

  List<_Tile> _layout(Size size) {
    if (size.width <= 0 || size.height <= 0) return const [];
    final ranked = [...nodes.where((n) => n.sizeBytes > 0)]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    if (ranked.isEmpty) return const [];

    // Cap the tile count; fold the long tail into one "Other" tile.
    List<ScanNode> shown;
    if (ranked.length > maxTiles) {
      shown = ranked.sublist(0, maxTiles - 1);
      final rest = ranked.sublist(maxTiles - 1);
      final otherSize = rest.fold<int>(0, (s, n) => s + n.sizeBytes);
      final otherCount = rest.fold<int>(0, (s, n) => s + n.fileCount);
      shown = [
        ...shown,
        ScanNode(
          path: '',
          name: '${rest.length} smaller items',
          isDirectory: false,
          sizeBytes: otherSize,
          fileCount: otherCount,
        ),
      ];
    } else {
      shown = ranked;
    }

    final total = shown.fold<int>(0, (s, n) => s + n.sizeBytes).toDouble();
    if (total <= 0) return const [];
    final scale = size.width * size.height / total;
    final areas = shown.map((n) => n.sizeBytes * scale).toList();

    final rects = _squarify(areas, Offset.zero & size);
    final tiles = <_Tile>[];
    for (var i = 0; i < rects.length && i < shown.length; i++) {
      tiles.add(_Tile(shown[i], rects[i], _palette[i % _palette.length]));
    }
    return tiles;
  }

  // ---- Squarified treemap layout ----------------------------------------
  List<Rect> _squarify(List<double> areas, Rect rect) {
    final result = <Rect>[];
    final remaining = List<double>.from(areas);
    var r = rect;
    final row = <double>[];

    double worst(List<double> rowAreas, double side) {
      if (rowAreas.isEmpty) return double.infinity;
      final sum = rowAreas.fold<double>(0, (s, a) => s + a);
      final maxA = rowAreas.reduce(math.max);
      final minA = rowAreas.reduce(math.min);
      final s2 = sum * sum;
      final side2 = side * side;
      return math.max(side2 * maxA / s2, s2 / (side2 * minA));
    }

    while (remaining.isNotEmpty) {
      final side = math.min(r.width, r.height);
      final next = remaining.first;
      if (row.isEmpty ||
          worst(row, side) >= worst([...row, next], side)) {
        row.add(next);
        remaining.removeAt(0);
      } else {
        r = _layoutRow(row, r, result);
        row.clear();
      }
    }
    if (row.isNotEmpty) _layoutRow(row, r, result);
    return result;
  }

  Rect _layoutRow(List<double> row, Rect rect, List<Rect> out) {
    final sum = row.fold<double>(0, (s, a) => s + a);
    final horizontal = rect.width >= rect.height;
    if (horizontal) {
      final rowWidth = sum / rect.height;
      var y = rect.top;
      for (final a in row) {
        final h = a / rowWidth;
        out.add(Rect.fromLTWH(rect.left, y, rowWidth, h));
        y += h;
      }
      return Rect.fromLTWH(
          rect.left + rowWidth, rect.top, rect.width - rowWidth, rect.height);
    } else {
      final rowHeight = sum / rect.width;
      var x = rect.left;
      for (final a in row) {
        final w = a / rowHeight;
        out.add(Rect.fromLTWH(x, rect.top, w, rowHeight));
        x += w;
      }
      return Rect.fromLTWH(
          rect.left, rect.top + rowHeight, rect.width, rect.height - rowHeight);
    }
  }
}

class _TreemapCell extends StatelessWidget {
  const _TreemapCell({required this.tile, required this.onTap});
  final _Tile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final node = tile.node;
    final showLabel = tile.rect.width > 54 && tile.rect.height > 30;
    final isDir = node.isDirectory && node.path.isNotEmpty;
    return Hoverable(
      enabled: isDir,
      onTap: isDir ? onTap : null,
      cursor: isDir ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tile.color.withValues(alpha: hovered ? 0.55 : 0.36),
              tile.color.withValues(alpha: hovered ? 0.32 : 0.18),
            ],
          ),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: tile.color.withValues(alpha: hovered ? 0.9 : 0.45),
            width: hovered ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.all(7),
        child: !showLabel
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isDir)
                        const Icon(Icons.folder_rounded,
                            size: 12, color: Colors.white70),
                      if (isDir) const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    formatBytes(node.sizeBytes),
                    style: AppType.micro.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

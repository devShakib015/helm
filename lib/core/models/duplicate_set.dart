import 'file_entry.dart';

/// A set of byte-identical files. Keeping one copy and removing the rest
/// reclaims [reclaimableBytes].
class DuplicateSet {
  DuplicateSet({
    required this.hash,
    required this.sizeBytes,
    required this.files,
  });

  /// Content hash shared by every file in the set.
  final String hash;

  /// Logical size of one copy — `st_size`, necessarily shared by every file in
  /// the set because they are byte-identical. This is the set's identity and
  /// what "N copies · X each" means.
  ///
  /// Deliberately *not* the disk cost: two identical files can occupy different
  /// numbers of blocks when macOS has compressed one of them and not the other,
  /// so the space question is answered by [reclaimableBytes] instead.
  final int sizeBytes;

  final List<FileEntry> files;

  int get copies => files.length;

  /// Space actually freed by keeping one copy and removing the rest.
  ///
  /// Summed from each copy's own allocated size rather than multiplying one
  /// number by `copies - 1`, because those allocations can differ even when the
  /// contents do not. The copy assumed kept is the largest, so this never
  /// promises back more than deleting would give.
  int get reclaimableBytes {
    if (files.length < 2) return 0;
    var total = 0;
    var largest = 0;
    for (final f in files) {
      total += f.sizeBytes;
      if (f.sizeBytes > largest) largest = f.sizeBytes;
    }
    return total - largest;
  }
}

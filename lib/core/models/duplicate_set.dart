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

  /// Size of a single copy.
  final int sizeBytes;

  final List<FileEntry> files;

  int get copies => files.length;

  /// Space freed by removing all but one copy.
  int get reclaimableBytes => sizeBytes * (files.length - 1);
}

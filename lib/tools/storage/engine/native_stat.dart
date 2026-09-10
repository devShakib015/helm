/// `lstat(2)` for the storage scanners, because Dart's [FileStat] does not
/// expose the field a disk tool actually needs.
///
/// `st_size` is a statement about **content**; `st_blocks` is a statement about
/// the **disk**. They come apart in three directions on macOS, all of them
/// common:
///
///   * **Compressed files.** macOS transparently compresses much of `/System`
///     and many app bundles. `/bin/ls` on this machine reports 154,208 bytes
///     and occupies 40,960.
///   * **Sparse files.** A 50 MB sparse file reports 52,428,800 and occupies
///     16,384.
///   * **Resource forks and xattrs.** The `Icon\r` file macOS writes into every
///     folder with a custom icon reports **0** bytes and occupies **61,440** —
///     the icon lives in `com.apple.ResourceFork`, which `st_size` does not
///     describe and `st_blocks` does.
///
/// Sum `st_size` across a volume and the total disagrees with About This Mac in
/// both directions at once, and when a user sees two numbers they believe
/// Apple's. Correctly. `du` has always used `st_blocks`; that is the whole
/// reason `du` and `ls -l` disagree.
///
/// This has no Flutter imports on purpose — every scanner runs inside a
/// background isolate, where a platform channel would need a root isolate token
/// and would cost a message hop per file across ~140,000 files. A direct
/// syscall is both simpler and faster than the `URLResourceKey
/// .totalFileAllocatedSizeKey` route on the Swift side.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// What one `lstat` call yields, in the three forms the scanners ask for.
class FileFacts {
  const FileFacts({
    required this.allocatedBytes,
    required this.logicalBytes,
    required this.modifiedMs,
  });

  /// What the file costs the disk — `st_blocks * 512`. POSIX fixes that unit at
  /// 512 regardless of `st_blksize`, which is why this is not `st_blksize`.
  ///
  /// This is the number every total, treemap rectangle and "space you would get
  /// back" figure is built from.
  final int allocatedBytes;

  /// What the file contains — `st_size`. Still the right key for *identity*
  /// questions: two byte-identical files always share this, and may not share
  /// [allocatedBytes] if one of them is compressed and the other is not.
  final int logicalBytes;

  final int modifiedMs;
}

/// POSIX fixes `st_blocks` in 512-byte units. Not `st_blksize`.
const int _blockUnit = 512;

/// macOS `PATH_MAX`. Paths longer than this cannot be stat'd at all, so this is
/// a ceiling rather than a guess — but the buffer still grows rather than
/// truncating, so a caller gets a clean `null` from the syscall instead of a
/// silently wrong answer about a different path.
const int _initialPathBytes = 1024;

typedef _LstatNative = Int32 Function(Pointer<Utf8>, Pointer<_Stat>);
typedef _LstatDart = int Function(Pointer<Utf8>, Pointer<_Stat>);

/// Darwin's 64-bit-inode `struct stat`. Verified against the platform headers:
/// `sizeof` 144, `st_ino` at 8, `st_mtimespec` at 48, `st_size` at 96,
/// `st_blocks` at 104. The reserved tail is declared rather than omitted so
/// that [sizeOf] can be checked against 144 at startup — a struct that ends
/// early would still read the right fields today and drift silently later.
final class _Timespec extends Struct {
  @Int64()
  external int tvSec;
  @Int64()
  external int tvNsec;
}

final class _Stat extends Struct {
  @Int32()
  external int stDev;
  @Uint16()
  external int stMode;
  @Uint16()
  external int stNlink;
  @Uint64()
  external int stIno;
  @Uint32()
  external int stUid;
  @Uint32()
  external int stGid;
  @Int32()
  external int stRdev;
  // 4 bytes of padding here: timespec is 8-aligned. Dart inserts it.
  external _Timespec stAtimespec;
  external _Timespec stMtimespec;
  external _Timespec stCtimespec;
  external _Timespec stBirthtimespec;
  @Int64()
  external int stSize;
  @Int64()
  external int stBlocks;
  @Int32()
  external int stBlksize;
  @Uint32()
  external int stFlags;
  @Uint32()
  external int stGen;
  @Int32()
  external int stLspare;
  @Int64()
  external int stQspare0;
  @Int64()
  external int stQspare1;
}

/// Resolved once per isolate. Dart statics are per-isolate, and every scanner
/// is single-threaded within its own, so the scratch buffers below are reused
/// across calls rather than allocated 140,000 times.
_LstatDart? _lstat;
Pointer<_Stat>? _statBuf;
Pointer<Utf8>? _pathBuf;
int _pathCapacity = 0;
bool _initialised = false;

/// True once the native path has been resolved *and* proved correct.
bool get nativeStatAvailable {
  _init();
  return _lstat != null;
}

void _init() {
  if (_initialised) return;
  _initialised = true;
  if (!Platform.isMacOS) return;

  try {
    final lib = DynamicLibrary.process();

    // On x86_64 the plain `lstat` symbol is the *legacy* 32-bit-inode call with
    // a different struct layout; `lstat$INODE64` is the one this struct
    // describes. On arm64 that suffixed symbol does not exist and plain `lstat`
    // is already the 64-bit one. Try the suffixed name first so Intel Macs —
    // Helm ships universal — do not read fields at the wrong offsets.
    _LstatDart? fn;
    for (final symbol in const ['lstat\$INODE64', 'lstat']) {
      try {
        fn = lib.lookupFunction<_LstatNative, _LstatDart>(symbol);
        break;
      } on ArgumentError {
        continue;
      }
    }
    if (fn == null) return;

    if (sizeOf<_Stat>() != 144) return;

    _statBuf = calloc<_Stat>();
    _growPath(_initialPathBytes);

    // Prove the offsets rather than trust them. If the ABI were wrong, the
    // field at offset 96 would not agree with what Dart reports for a file both
    // can see — and a wrong `st_size` means a wrong `st_blocks` eight bytes
    // later. Any disagreement disables the native path entirely.
    final probe = Platform.resolvedExecutable;
    final native = _rawStat(fn, probe);
    final dartSize = File(probe).statSync().size;
    if (native == null || native.stSize != dartSize || native.stBlocks <= 0) {
      _release();
      return;
    }

    _lstat = fn;
  } catch (_) {
    _release();
  }
}

void _release() {
  final s = _statBuf;
  final p = _pathBuf;
  if (s != null) calloc.free(s);
  if (p != null) calloc.free(p);
  _statBuf = null;
  _pathBuf = null;
  _pathCapacity = 0;
  _lstat = null;
}

void _growPath(int bytes) {
  final old = _pathBuf;
  if (old != null) calloc.free(old);
  _pathBuf = calloc<Uint8>(bytes).cast<Utf8>();
  _pathCapacity = bytes;
}

/// Runs the call into the shared buffer and hands back the struct, or null when
/// the syscall failed (missing file, no permission, path too long).
_Stat? _rawStat(_LstatDart fn, String path) {
  final bytes = utf8.encode(path);
  if (bytes.length + 1 > _pathCapacity) {
    _growPath(bytes.length + 1);
  }
  final buf = _pathBuf!.cast<Uint8>();
  buf.asTypedList(_pathCapacity).setRange(0, bytes.length, bytes);
  buf[bytes.length] = 0;

  if (fn(_pathBuf!, _statBuf!) != 0) return null;
  return _statBuf!.ref;
}

/// [FileFacts] for [path].
///
/// Falls back to Dart's own `stat` when the native call is unavailable, in
/// which case [FileFacts.allocatedBytes] degrades to `st_size` — the old
/// behaviour, which is wrong in the ways described above but never worse than
/// what shipped before. Returns null only when the file cannot be stat'd at
/// all, which callers already have to handle.
FileFacts? factsFor(String path) {
  _init();
  final fn = _lstat;
  if (fn != null) {
    final st = _rawStat(fn, path);
    if (st != null) {
      return FileFacts(
        allocatedBytes: st.stBlocks * _blockUnit,
        logicalBytes: st.stSize,
        modifiedMs: st.stMtimespec.tvSec * 1000 +
            st.stMtimespec.tvNsec ~/ 1000000,
      );
    }
    return null;
  }

  try {
    final st = File(path).statSync();
    return FileFacts(
      allocatedBytes: st.size,
      logicalBytes: st.size,
      modifiedMs: st.modified.millisecondsSinceEpoch,
    );
  } catch (_) {
    return null;
  }
}

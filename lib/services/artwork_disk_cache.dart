import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'bounded_load_gate.dart';

enum ArtworkDiskWriteResult {
  written,
  skippedInvalidPayload,
  rejectedByGate,
  failed,
}

class DiskArtwork {
  const DiskArtwork({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Small persistent cache for artwork bytes sized for their display role.
///
/// The cache index is scanned once per process in the background. Subsequent
/// writes update the index incrementally, so trimming does not repeatedly
/// enumerate and stat every thumbnail while the user is scrolling.
class ArtworkDiskCache {
  ArtworkDiskCache._();

  static final ArtworkDiskCache instance = ArtworkDiskCache._();
  static const int _maxBytes = 64 * 1024 * 1024;
  static const int _trimWriteBudgetBytes = 48 * 1024 * 1024;
  static Future<Directory>? _directoryFuture;
  static final BoundedLoadGate _writeGate = BoundedLoadGate(
    maxConcurrent: 1,
    maxQueued: 24,
  );

  final Map<String, _ArtworkCacheEntry> _cacheIndex =
      <String, _ArtworkCacheEntry>{};
  final Map<String, _ArtworkCacheEntry> _pendingIndexUpdates =
      <String, _ArtworkCacheEntry>{};
  Future<void>? _cacheIndexFuture;
  Future<void>? _trimFuture;
  Completer<void>? _trimCompleter;
  bool _trimInProgress = false;
  int _activeReads = 0;
  bool _cacheIndexReady = false;
  bool _cacheIndexScheduled = false;
  int _knownCacheBytes = 0;
  int _bytesWrittenSinceTrim = 0;

  Future<Directory> _directory() =>
      _directoryFuture ??= getApplicationSupportDirectory().then((root) async {
        final directory = Directory('${root.path}/artwork-thumbnails-v2');
        await directory.create(recursive: true);
        // Index construction is intentionally deferred from the first read/write.
        // It must not compete with the first visible artwork requests.
        if (!_cacheIndexScheduled && !_cacheIndexReady) {
          _cacheIndexScheduled = true;
          unawaited(
            Future<void>.delayed(const Duration(seconds: 2))
                .then((_) => _ensureCacheIndex(directory))
                .whenComplete(() => _cacheIndexScheduled = false),
          );
        }
        return directory;
      });

  String _fileName(String key) {
    var hash = 0xcbf29ce484222325;
    for (final byte in key.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  Future<DiskArtwork?> read(String key) async {
    final pendingTrim = _trimCompleter;
    if (pendingTrim != null) await pendingTrim.future;
    _activeReads++;
    try {
      final file = File('${(await _directory()).path}/${_fileName(key)}.art');
      if (!await file.exists()) {
        return null;
      }
      final data = await file.readAsBytes();
      if (data.length < 8) {
        return null;
      }
      final header = ByteData.sublistView(data, 0, 8);
      final width = header.getUint32(0);
      final height = header.getUint32(4);
      if (width == 0 || height == 0 || data.length == 8) {
        return null;
      }
      // Do not touch the file timestamp on every cache hit. This keeps reads
      // read-only; eviction uses the last successful write time instead.
      return DiskArtwork(
        bytes: Uint8List.sublistView(data, 8),
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    } finally {
      _activeReads--;
    }
  }

  Future<ArtworkDiskWriteResult> write(
    String key,
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    final pendingTrim = _trimCompleter;
    if (pendingTrim != null) await pendingTrim.future;
    final permitResult = await _writeGate.acquireWithResult();
    if (permitResult != LoadPermitResult.acquired) {
      return ArtworkDiskWriteResult.rejectedByGate;
    }
    try {
      if (bytes.isEmpty ||
          bytes.length > _maxBytes ~/ 2 ||
          width <= 0 ||
          height <= 0) {
        return ArtworkDiskWriteResult.skippedInvalidPayload;
      }
      final directory = await _directory();
      final file = File('${directory.path}/${_fileName(key)}.art');
      final header =
          ByteData(8)
            ..setUint32(0, width)
            ..setUint32(4, height);
      final data =
          Uint8List(8 + bytes.length)
            ..setRange(0, 8, header.buffer.asUint8List())
            ..setRange(8, 8 + bytes.length, bytes);

      // Publish atomically so an interrupted write cannot look like a valid hit.
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsBytes(data, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }

      final entry = _ArtworkCacheEntry(
        path: file.path,
        sizeBytes: data.length,
        modifiedAt: DateTime.now(),
      );
      _updateCacheIndex(entry);
      _bytesWrittenSinceTrim += data.length;
      final shouldScheduleTrim =
          _cacheIndexReady
              ? _knownCacheBytes > _maxBytes
              : _bytesWrittenSinceTrim >= _trimWriteBudgetBytes;
      if (shouldScheduleTrim) _bytesWrittenSinceTrim = 0;
      if (shouldScheduleTrim) _scheduleTrim(directory);
      return ArtworkDiskWriteResult.written;
    } catch (_) {
      return ArtworkDiskWriteResult.failed;
    } finally {
      _writeGate.release();
    }
  }

  void _updateCacheIndex(_ArtworkCacheEntry entry) {
    if (!_cacheIndexReady) {
      _pendingIndexUpdates[entry.path] = entry;
      return;
    }
    final previous = _cacheIndex[entry.path];
    if (previous != null) _knownCacheBytes -= previous.sizeBytes;
    _cacheIndex[entry.path] = entry;
    _knownCacheBytes += entry.sizeBytes;
  }

  Future<void> _ensureCacheIndex(Directory directory) {
    if (_cacheIndexReady) return Future<void>.value();
    final existing = _cacheIndexFuture;
    if (existing != null) return existing;
    final scan = _scanCacheIndex(directory);
    _cacheIndexFuture = scan.whenComplete(() {
      _cacheIndexFuture = null;
      if (_cacheIndexReady && _knownCacheBytes > _maxBytes) {
        _scheduleTrim(directory);
      }
    });
    return _cacheIndexFuture!;
  }

  Future<void> _scanCacheIndex(Directory directory) async {
    var indexedBytes = 0;
    try {
      final files =
          await directory
              .list()
              .where((entity) => entity is File && entity.path.endsWith('.art'))
              .cast<File>()
              .toList();
      final discovered = <String, _ArtworkCacheEntry>{};
      for (final file in files) {
        try {
          final stat = await file.stat();
          final entry = _ArtworkCacheEntry(
            path: file.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          );
          discovered[file.path] = entry;
          indexedBytes += stat.size;
        } catch (_) {
          // A cache entry can disappear while the index is being scanned.
        }
      }

      _cacheIndex
        ..clear()
        ..addAll(discovered);
      _knownCacheBytes = indexedBytes;
      // Apply writes that completed while the one-time directory scan was in
      // flight. The latest update for a path wins over the scanned metadata.
      for (final update in _pendingIndexUpdates.values) {
        final previous = _cacheIndex[update.path];
        if (previous != null) _knownCacheBytes -= previous.sizeBytes;
        _cacheIndex[update.path] = update;
        _knownCacheBytes += update.sizeBytes;
      }
      _pendingIndexUpdates.clear();
      _cacheIndexReady = true;
      _bytesWrittenSinceTrim = 0;
    } catch (_) {
      // The cache remains usable even if an index scan cannot complete.
    }
  }

  void _scheduleTrim(Directory directory) {
    if (_trimFuture != null) return;
    _trimFuture = Future<void>(() async {
      await _ensureCacheIndex(directory);
      if (!_cacheIndexReady) {
        _bytesWrittenSinceTrim = _trimWriteBudgetBytes;
        return;
      }
      // Wait for a quiet window, but keep retries bounded so maintenance can
      // never become a permanent background task.
      var idle = false;
      for (var attempt = 1; attempt <= 4; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_writeGate.activeLoads == 0 &&
            _writeGate.queuedLoads == 0 &&
            _activeReads == 0) {
          idle = true;
          break;
        }
      }
      if (!idle) {
        _bytesWrittenSinceTrim = _trimWriteBudgetBytes;
        return;
      }
      await _trim();
    }).whenComplete(() => _trimFuture = null);
  }

  Future<void> _trim() async {
    if (_trimInProgress) return;
    _trimInProgress = true;
    final maintenanceCompleter = Completer<void>();
    _trimCompleter = maintenanceCompleter;
    try {
      if (!_cacheIndexReady) {
        return;
      }

      final bytesBeforeTrim = _knownCacheBytes;
      if (bytesBeforeTrim <= _maxBytes) {
        return;
      }

      final sortClock = Stopwatch()..start();
      final entries =
          _cacheIndex.values.toList()
            ..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      sortClock.stop();
      final deleteClock = Stopwatch()..start();
      var deletedFiles = 0;
      var deleteFailures = 0;
      for (final entry in entries) {
        if (_knownCacheBytes <= _maxBytes) break;
        try {
          await File(entry.path).delete();
          _cacheIndex.remove(entry.path);
          _knownCacheBytes -= entry.sizeBytes;
          deletedFiles++;
        } catch (_) {
          deleteFailures++;
        }
      }
      deleteClock.stop();
    } catch (error) {
    } finally {
      _trimInProgress = false;
      if (identical(_trimCompleter, maintenanceCompleter)) {
        _trimCompleter = null;
      }
      if (!maintenanceCompleter.isCompleted) maintenanceCompleter.complete();
    }
  }
}

class _ArtworkCacheEntry {
  const _ArtworkCacheEntry({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
}

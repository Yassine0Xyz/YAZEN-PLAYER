import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persistent cache for resolved YouTube audio streams.
///
/// A YouTube stream URL is temporary and changes over time, so the cache key is
/// the stable video ID rather than the resolved URL. just_audio downloads into
/// the cache file while playing and writes a `.part` file until the download is
/// complete; the marker file below makes offline reuse explicit and safe.
class YouTubeAudioCache {
  YouTubeAudioCache({Directory? rootDirectory})
    : _rootDirectory = rootDirectory;

  static const _directoryName = 'youtube_audio_cache';
  static const _audioExtension = '.audio';
  static const _completeExtension = '.complete';
  static const defaultMaxBytes = 512 * 1024 * 1024;
  static const defaultMaxAge = Duration(days: 30);

  final Directory? _rootDirectory;
  final Map<String, StreamSubscription<double>> _progressSubscriptions = {};
  final Map<String, HttpClient> _activeClients = {};

  Future<Directory> get _directory async {
    final directory =
        _rootDirectory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, _directoryName),
        );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _audioFile(String videoId) async {
    final directory = await _directory;
    return File(p.join(directory.path, '${_safeKey(videoId)}$_audioExtension'));
  }

  Future<File> _completeMarker(String videoId) async {
    final directory = await _directory;
    return File(
      p.join(directory.path, '${_safeKey(videoId)}$_completeExtension'),
    );
  }

  Future<File> cachedFile(String videoId) => _audioFile(videoId);

  Future<bool> hasComplete(String videoId) async {
    final audioFile = await _audioFile(videoId);
    final marker = await _completeMarker(videoId);
    final complete = await audioFile.exists() && await marker.exists();
    if (complete) {
      // The marker timestamp acts as a lightweight last-access timestamp.
      await marker.setLastModified(DateTime.now());
    }
    return complete;
  }

  Future<AudioSource> sourceFor({
    required String videoId,
    required Uri streamUri,
    required MediaItem tag,
  }) async {
    await prune(excludeVideoId: videoId);
    final audioFile = await _audioFile(videoId);
    if (await hasComplete(videoId)) {
      return AudioSource.uri(Uri.file(audioFile.path), tag: tag);
    }

    final source = LockCachingAudioSource(
      streamUri,
      cacheFile: audioFile,
      tag: tag,
    );

    await _progressSubscriptions[videoId]?.cancel();
    _progressSubscriptions[videoId] = source.downloadProgressStream.listen((
      progress,
    ) async {
      if (progress >= 1.0) {
        final marker = await _completeMarker(videoId);
        await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
        await _progressSubscriptions.remove(videoId)?.cancel();
      }
    });
    return source;
  }

  Future<void> prune({
    int maxBytes = defaultMaxBytes,
    Duration maxAge = defaultMaxAge,
    String? excludeVideoId,
  }) async {
    final directory = await _directory;
    final now = DateTime.now();
    final entries =
        <({File audio, File marker, DateTime lastAccess, int bytes})>[];

    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith(_audioExtension)) continue;
      final key = p.basenameWithoutExtension(entity.path);
      if (excludeVideoId != null && key == _safeKey(excludeVideoId)) continue;
      final marker = File(p.join(directory.path, '$key$_completeExtension'));
      if (!await marker.exists()) {
        if (now.difference(await entity.lastModified()) > maxAge) {
          await entity.delete();
        }
        continue;
      }
      final lastAccess = await marker.lastModified();
      if (now.difference(lastAccess) > maxAge) {
        await entity.delete();
        await marker.delete();
        continue;
      }
      entries.add((
        audio: entity,
        marker: marker,
        lastAccess: lastAccess,
        bytes: await entity.length(),
      ));
    }

    var total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    if (total <= maxBytes) return;

    entries.sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await entry.audio.delete();
      if (await entry.marker.exists()) await entry.marker.delete();
      total -= entry.bytes;
    }
  }

  Future<File> downloadToCache({
    required String videoId,
    required Uri streamUri,
    void Function(double progress)? onProgress,
  }) async {
    await prune(excludeVideoId: videoId);
    final audioFile = await _audioFile(videoId);
    final marker = await _completeMarker(videoId);
    if (await hasComplete(videoId)) return audioFile;

    final partial = File('${audioFile.path}.part');
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _activeClients[videoId] = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(streamUri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'YAZEN/1.0 (Android music player)',
      );
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Stream download failed: ${response.statusCode}',
          uri: streamUri,
        );
      }

      final contentLength = response.contentLength;
      var received = 0;
      sink = partial.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await audioFile.exists()) await audioFile.delete();
      await partial.rename(audioFile.path);
      await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
      onProgress?.call(1.0);
      return audioFile;
    } catch (_) {
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      _activeClients.remove(videoId);
      client.close(force: true);
    }
  }

  Future<void> cancelDownload(String videoId) async {
    _activeClients.remove(videoId)?.close(force: true);
    final audioFile = await _audioFile(videoId);
    final partial = File('${audioFile.path}.part');
    if (await partial.exists()) await partial.delete();
  }

  Future<int> totalBytes() async {
    final directory = await _directory;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith(_audioExtension)) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clear(String videoId) async {
    await _progressSubscriptions.remove(videoId)?.cancel();
    final audioFile = await _audioFile(videoId);
    final marker = await _completeMarker(videoId);
    final partial = File('${audioFile.path}.part');
    for (final file in <File>[audioFile, marker, partial]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> clearAll() async {
    for (final subscription in _progressSubscriptions.values) {
      await subscription.cancel();
    }
    _progressSubscriptions.clear();
    final directory = await _directory;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> dispose() async {
    for (final subscription in _progressSubscriptions.values) {
      await subscription.cancel();
    }
    _progressSubscriptions.clear();
    for (final client in _activeClients.values) {
      client.close(force: true);
    }
    _activeClients.clear();
  }

  String _safeKey(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return normalized.isEmpty ? 'unknown' : normalized;
  }
}

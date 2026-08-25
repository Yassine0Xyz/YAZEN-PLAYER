import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';
import '../models/media_track.dart';
import 'youtube_service.dart';

const _downloadEventsPortName = 'yazen.download.events';

@pragma('vm:entry-point')
void _yazenDownloadCallback(String id, int status, int progress) {
  final port = IsolateNameServer.lookupPortByName(_downloadEventsPortName);
  port?.send(<dynamic>[id, status, progress]);
}

class DownloadManager extends ChangeNotifier {
  DownloadManager({required YoutubeService youtubeService})
    : _youtubeService = youtubeService;

  static const _catalogKey = 'yazen.download_catalog.v1';
  static const _directoryName = 'yazen_downloads';

  final YoutubeService _youtubeService;
  final List<DownloadItem> _items = <DownloadItem>[];
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );
  final Map<String, CancelToken> _activeTokens = <String, CancelToken>{};
  final Map<String, String> _backgroundTaskIds = <String, String>{};
  final Set<String> _activeJobs = <String>{};
  final Set<String> _pausedJobs = <String>{};
  ReceivePort? _downloadEventsPort;
  Directory? _directory;
  bool _initialized = false;

  List<DownloadItem> get items => List<DownloadItem>.unmodifiable(_items);
  bool get isInitialized => _initialized;
  bool get hasActiveDownloads => _activeJobs.isNotEmpty;

  Future<List<YoutubeDownloadOption>> optionsFor(
    MediaTrack track, {
    required String videoId,
  }) {
    return _youtubeService.getDownloadOptions(
      videoId,
      duration: track.duration,
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_catalogKey);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) {
          _items
            ..clear()
            ..addAll(
              decoded.whereType<Map<String, dynamic>>().map(
                DownloadItem.fromJson,
              ),
            );
        }
      } catch (_) {
        _items.clear();
      }
    }
    _directory = Directory(
      p.join((await getApplicationSupportDirectory()).path, _directoryName),
    );
    if (!await _directory!.exists()) await _directory!.create(recursive: true);
    await _bindDownloaderEvents();
    await _removeMissingFiles();
    await _reconcileBackgroundTasks();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _bindDownloaderEvents() async {
    if (!FlutterDownloader.initialized) return;
    IsolateNameServer.removePortNameMapping(_downloadEventsPortName);
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      _downloadEventsPortName,
    );
    _downloadEventsPort = port;
    port.listen((dynamic message) {
      if (message is List && message.length >= 3) {
        unawaited(_handleBackgroundEvent(message));
      }
    });
    await FlutterDownloader.registerCallback(_yazenDownloadCallback, step: 1);
  }

  Future<void> _handleBackgroundEvent(List<dynamic> message) async {
    final taskId = message[0]?.toString();
    final statusValue = message[1];
    final progressValue = message[2];
    if (taskId == null || statusValue is! int || progressValue is! int) return;
    DownloadItem? item;
    for (final candidate in _items) {
      if (candidate.backgroundTaskId == taskId) {
        item = candidate;
        break;
      }
    }
    if (item == null) return;
    final status = DownloadTaskStatus.fromInt(statusValue);
    final mapped = switch (status) {
      DownloadTaskStatus.enqueued => DownloadStatus.queued,
      DownloadTaskStatus.running => DownloadStatus.downloading,
      DownloadTaskStatus.paused => DownloadStatus.paused,
      DownloadTaskStatus.complete => DownloadStatus.downloading,
      DownloadTaskStatus.failed => DownloadStatus.failed,
      DownloadTaskStatus.canceled => DownloadStatus.cancelled,
      DownloadTaskStatus.undefined => item.status,
    };
    final hasKnownTotal = item.totalBytes != null && item.totalBytes! > 0;
    _replace(
      item.copyWith(
        status: mapped,
        downloadedBytes:
            hasKnownTotal
                ? (item.totalBytes! * progressValue / 100).round()
                : item.downloadedBytes,
        progressPercent: progressValue.clamp(0, 100),
        errorMessage:
            status == DownloadTaskStatus.failed
                ? 'Background network download failed. Tap Retry.'
                : null,
        clearError: status != DownloadTaskStatus.failed,
      ),
      persist: status != DownloadTaskStatus.running,
    );
  }

  Future<void> _reconcileBackgroundTasks() async {
    if (!FlutterDownloader.initialized) return;
    final tasks = await FlutterDownloader.loadTasks() ?? const <DownloadTask>[];
    final byId = <String, DownloadTask>{
      for (final task in tasks) task.taskId: task,
    };
    for (final item in List<DownloadItem>.of(_items)) {
      final taskId = item.backgroundTaskId;
      if (taskId == null || item.kind != DownloadKind.classicAudio) continue;
      final task = byId[taskId];
      if (task == null) {
        if (item.isActive) {
          _replace(
            item.copyWith(
              status: DownloadStatus.failed,
              errorMessage: 'Background task was lost. Tap Retry.',
            ),
          );
        }
        continue;
      }
      if (task.status == DownloadTaskStatus.complete ||
          task.status == DownloadTaskStatus.running ||
          task.status == DownloadTaskStatus.enqueued ||
          task.status == DownloadTaskStatus.paused) {
        _backgroundTaskIds[item.id] = taskId;
        _activeJobs.add(item.id);
        _replace(
          item.copyWith(
            status:
                task.status == DownloadTaskStatus.paused
                    ? DownloadStatus.paused
                    : DownloadStatus.downloading,
            progressPercent: task.progress.clamp(0, 100),
          ),
        );
        unawaited(_recoverBackgroundItem(item, task));
      } else if (task.status == DownloadTaskStatus.failed) {
        _replace(
          item.copyWith(
            status: DownloadStatus.failed,
            errorMessage: 'Background network download failed. Tap Retry.',
          ),
        );
      } else if (task.status == DownloadTaskStatus.canceled) {
        _replace(item.copyWith(status: DownloadStatus.cancelled));
      }
    }
  }

  Future<void> _recoverBackgroundItem(
    DownloadItem item,
    DownloadTask initialTask,
  ) async {
    final output = await _fileFor(item);
    final temporary = File('${output.path}.part');
    try {
      while (_activeJobs.contains(item.id)) {
        final taskId = _backgroundTaskIds[item.id] ?? initialTask.taskId;
        final tasks =
            await FlutterDownloader.loadTasks() ?? const <DownloadTask>[];
        DownloadTask? task;
        for (final candidate in tasks) {
          if (candidate.taskId == taskId) {
            task = candidate;
            break;
          }
        }
        if (task == null) {
          _replace(
            (_find(item.id) ?? item).copyWith(
              status: DownloadStatus.failed,
              errorMessage: 'Background task was lost. Tap Retry.',
            ),
          );
          break;
        }
        final current = _find(item.id) ?? item;
        final hasKnownTotal = current.totalBytes != null;
        if (task.status == DownloadTaskStatus.complete) {
          if (!await temporary.exists() || await temporary.length() <= 0) {
            throw StateError('Background download returned an empty file.');
          }
          if (await output.exists()) await output.delete();
          await temporary.rename(output.path);
          final size = await output.length();
          _replace(
            current.copyWith(
              status: DownloadStatus.completed,
              filePath: output.path,
              totalBytes: size,
              downloadedBytes: size,
              progressPercent: 100,
              clearBackgroundTaskId: true,
              clearError: true,
            ),
          );
          break;
        }
        if (task.status == DownloadTaskStatus.failed) {
          _replace(
            current.copyWith(
              status: DownloadStatus.failed,
              errorMessage: 'Background network download failed. Tap Retry.',
            ),
          );
          break;
        }
        if (task.status == DownloadTaskStatus.canceled) {
          _replace(current.copyWith(status: DownloadStatus.cancelled));
          break;
        }
        final nextStatus =
            task.status == DownloadTaskStatus.paused
                ? DownloadStatus.paused
                : DownloadStatus.downloading;
        _replace(
          current.copyWith(
            status: nextStatus,
            downloadedBytes:
                hasKnownTotal
                    ? (current.totalBytes! * task.progress / 100).round()
                    : current.downloadedBytes,
            progressPercent: task.progress.clamp(0, 100),
          ),
          persist: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    } catch (error) {
      final current = _find(item.id) ?? item;
      _replace(
        current.copyWith(
          status: DownloadStatus.failed,
          errorMessage: _friendlyError(error),
        ),
      );
    } finally {
      _activeJobs.remove(item.id);
      _backgroundTaskIds.remove(item.id);
      await _persist();
    }
  }

  Future<void> enqueue({
    required MediaTrack track,
    required YoutubeDownloadOption option,
  }) async {
    await initialize();
    final videoId = track.youtubeId;
    if (videoId == null || videoId.isEmpty) {
      throw StateError('Only YouTube tracks can be downloaded.');
    }
    if (_activeJobs.contains(option.id)) return;

    final item = DownloadItem(
      id: option.id,
      videoId: videoId,
      title: track.title,
      artist: track.artist,
      artworkUri: track.artworkUri,
      kind: option.kind,
      qualityLabel: option.qualityLabel,
      extension: _extensionFor(option),
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
      totalBytes: option.sizeBytes,
    );
    _replace(item);
    unawaited(_run(item, option));
  }

  Future<void> _run(DownloadItem original, YoutubeDownloadOption option) async {
    _activeJobs.add(original.id);
    option = await _freshOption(original, option);
    final output = await _fileFor(original);
    final temporary = File('${output.path}.part');
    final sourceTemporary = File('${output.path}.source.part');
    final videoTemporary = File('${output.path}.video.part');
    final audioTemporary = File('${output.path}.audio.part');
    try {
      _replace(
        original.copyWith(status: DownloadStatus.downloading, clearError: true),
      );
      if (await output.exists()) await output.delete();
      if (option.kind == DownloadKind.classicAudio) {
        await _downloadFile(
          option.primaryUri,
          temporary,
          jobId: original.id,
          background: true,
          onProgress:
              (received, total) =>
                  _updateProgress(original.id, received, total),
        );
        await temporary.rename(output.path);
      } else if (option.kind == DownloadKind.mp3Audio) {
        await _downloadFile(
          option.primaryUri,
          sourceTemporary,
          jobId: original.id,
          onProgress:
              (received, total) =>
                  _updateProgress(original.id, received, total),
        );
        _replace(
          (_find(original.id) ?? original).copyWith(
            status: DownloadStatus.processing,
            clearProgressPercent: true,
          ),
        );
        final session = await FFmpegKit.executeWithArguments(<String>[
          '-y',
          '-i',
          sourceTemporary.path,
          '-vn',
          '-map_metadata',
          '0',
          '-codec:a',
          'libmp3lame',
          '-b:a',
          '320k',
          '-id3v2_version',
          '3',
          output.path,
        ]);
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode)) {
          throw StateError('MP3 conversion failed.');
        }
      } else if (option.requiresMuxing) {
        final videoUri = option.videoUri;
        final audioUri = option.audioUri;
        if (videoUri == null || audioUri == null) {
          throw StateError('This video option is incomplete.');
        }
        final videoBytes = await _downloadFile(
          videoUri,
          videoTemporary,
          jobId: original.id,
          onProgress:
              (received, total) =>
                  _updateProgress(original.id, received, total),
        );
        final audioBytes = await _downloadFile(
          audioUri,
          audioTemporary,
          jobId: original.id,
          onProgress:
              (received, total) => _updateProgress(
                original.id,
                videoBytes + received,
                _knownTotal(videoBytes, total),
              ),
        );
        _replace(
          (_find(original.id) ?? original).copyWith(
            status: DownloadStatus.processing,
            clearProgressPercent: true,
          ),
        );
        final session = await FFmpegKit.executeWithArguments(<String>[
          '-y',
          '-i',
          videoTemporary.path,
          '-i',
          audioTemporary.path,
          '-map',
          '0:v:0',
          '-map',
          '1:a:0',
          '-c:v',
          'copy',
          '-c:a',
          'aac',
          '-movflags',
          '+faststart',
          output.path,
        ]);
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode)) {
          throw StateError('Video and audio could not be combined.');
        }
        if (audioBytes <= 0 && !await output.exists()) {
          throw StateError('Video download produced no output.');
        }
      } else {
        await _downloadFile(
          option.primaryUri,
          temporary,
          jobId: original.id,
          onProgress:
              (received, total) =>
                  _updateProgress(original.id, received, total),
        );
        await temporary.rename(output.path);
      }

      if (!await output.exists() || await output.length() <= 0) {
        throw StateError('Download finished without a playable file.');
      }
      final size = await output.length();
      _replace(
        original.copyWith(
          status: DownloadStatus.completed,
          filePath: output.path,
          totalBytes: size,
          downloadedBytes: size,
          clearError: true,
        ),
      );
    } catch (error) {
      for (final file in <File>[
        temporary,
        sourceTemporary,
        videoTemporary,
        audioTemporary,
      ]) {
        if (await file.exists()) await file.delete();
      }
      if (await output.exists()) await output.delete();
      final current = _find(original.id);
      if (current?.status != DownloadStatus.cancelled) {
        _replace(
          (current ?? original).copyWith(
            status: DownloadStatus.failed,
            errorMessage: _friendlyError(error),
          ),
        );
      }
    } finally {
      _activeTokens.remove(original.id)?.cancel('Download finished');
      final taskId = _backgroundTaskIds.remove(original.id);
      if (taskId != null) {
        await FlutterDownloader.cancel(taskId: taskId);
      }
      _activeJobs.remove(original.id);
    }
  }

  Future<int> _downloadFile(
    Uri uri,
    File destination, {
    required String jobId,
    required void Function(int received, int? total) onProgress,
    bool background = false,
  }) async {
    if (background) {
      return _downloadInBackground(
        uri,
        destination,
        jobId: jobId,
        onProgress: onProgress,
      );
    }

    final cancelToken = CancelToken();
    _activeTokens[jobId] = cancelToken;
    try {
      if (await destination.exists()) await destination.delete();
      await _dio.download(
        uri.toString(),
        destination.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        options: Options(
          headers: <String, String>{'User-Agent': 'YAZEN/1.0'},
          validateStatus:
              (status) => status != null && status >= 200 && status < 300,
        ),
        onReceiveProgress:
            (received, total) => onProgress(received, total > 0 ? total : null),
      );
      final received = await destination.length();
      if (received <= 0) throw StateError('Download returned an empty file.');
      onProgress(received, received);
      return received;
    } finally {
      if (identical(_activeTokens[jobId], cancelToken)) {
        _activeTokens.remove(jobId);
      }
    }
  }

  Future<int> _downloadInBackground(
    Uri uri,
    File destination, {
    required String jobId,
    required void Function(int received, int? total) onProgress,
  }) async {
    if (await destination.exists()) await destination.delete();
    final taskId = await FlutterDownloader.enqueue(
      url: uri.toString(),
      savedDir: destination.parent.path,
      fileName: p.basename(destination.path),
      headers: const <String, String>{'User-Agent': 'YAZEN/1.0'},
      showNotification: true,
      openFileFromNotification: false,
    );
    if (taskId == null || taskId.isEmpty) {
      throw StateError('Could not start the background download.');
    }
    _backgroundTaskIds[jobId] = taskId;
    final current = _find(jobId);
    if (current != null) {
      _replace(
        current.copyWith(
          backgroundTaskId: taskId,
          status: DownloadStatus.downloading,
          clearError: true,
        ),
      );
    }
    try {
      while (_activeJobs.contains(jobId)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final activeTaskId = _backgroundTaskIds[jobId] ?? taskId;
        final tasks =
            await FlutterDownloader.loadTasks() ?? const <DownloadTask>[];
        DownloadTask? task;
        for (final candidate in tasks) {
          if (candidate.taskId == activeTaskId) {
            task = candidate;
            break;
          }
        }
        if (task == null) continue;
        if (task.status == DownloadTaskStatus.complete) {
          final received = await destination.length();
          if (received <= 0) {
            throw StateError('Background download returned an empty file.');
          }
          onProgress(received, received);
          return received;
        }
        if (task.status == DownloadTaskStatus.failed) {
          throw StateError('Background network download failed.');
        }
        if (task.status == DownloadTaskStatus.canceled) {
          throw StateError('Download cancelled.');
        }
        if (task.status == DownloadTaskStatus.paused) {
          final current = _find(jobId);
          if (current != null) {
            _replace(
              current.copyWith(
                status: DownloadStatus.paused,
                progressPercent: task.progress.clamp(0, 100),
              ),
              persist: false,
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 650));
          continue;
        }
        if (task.progress >= 0 && await destination.exists()) {
          onProgress(await destination.length(), null);
        }
      }
      throw StateError('Download cancelled.');
    } finally {
      if (identical(_backgroundTaskIds[jobId], taskId)) {
        _backgroundTaskIds.remove(jobId);
      }
    }
  }

  void _updateProgress(String id, int received, int? total) {
    final current = _find(id);
    if (current == null || current.status != DownloadStatus.downloading) return;
    _replace(
      current.copyWith(
        downloadedBytes: received,
        totalBytes: total ?? current.totalBytes,
      ),
      persist: false,
    );
  }

  Future<void> pause(String id) async {
    final current = _find(id);
    final taskId = _backgroundTaskIds[id] ?? current?.backgroundTaskId;
    if (current == null ||
        current.kind != DownloadKind.classicAudio ||
        taskId == null ||
        !current.isActive) {
      return;
    }
    _pausedJobs.add(id);
    await FlutterDownloader.pause(taskId: taskId);
    _replace(current.copyWith(status: DownloadStatus.paused));
  }

  Future<void> resume(String id) async {
    final current = _find(id);
    final taskId = _backgroundTaskIds[id] ?? current?.backgroundTaskId;
    if (current == null ||
        taskId == null ||
        current.status != DownloadStatus.paused) {
      return;
    }
    final replacementTaskId = await FlutterDownloader.resume(taskId: taskId);
    if (replacementTaskId == null || replacementTaskId.isEmpty) {
      _replace(
        current.copyWith(
          status: DownloadStatus.failed,
          errorMessage: 'Could not resume this background download. Tap Retry.',
        ),
      );
      return;
    }
    _backgroundTaskIds[id] = replacementTaskId;
    _pausedJobs.remove(id);
    _activeJobs.add(id);
    _replace(
      current.copyWith(
        status: DownloadStatus.downloading,
        backgroundTaskId: replacementTaskId,
        clearError: true,
      ),
    );
  }

  Future<void> retry(String id) async {
    await initialize();
    final current = _find(id);
    if (current == null || _activeJobs.contains(id)) return;
    final oldTaskId = _backgroundTaskIds.remove(id) ?? current.backgroundTaskId;
    if (oldTaskId != null && FlutterDownloader.initialized) {
      await FlutterDownloader.remove(taskId: oldTaskId);
    }
    try {
      final options = await _youtubeService.getDownloadOptions(current.videoId);
      YoutubeDownloadOption? selected;
      for (final candidate in options) {
        if (candidate.kind == current.kind &&
            candidate.qualityLabel == current.qualityLabel) {
          selected = candidate;
          break;
        }
      }
      if (selected == null) {
        throw StateError(
          '${current.qualityLabel} is no longer available for this video.',
        );
      }
      final next = current.copyWith(
        status: DownloadStatus.retrying,
        downloadedBytes: 0,
        progressPercent: 0,
        clearFilePath: true,
        clearError: true,
        clearBackgroundTaskId: true,
      );
      _replace(next);
      unawaited(_run(next, selected));
    } catch (error) {
      _replace(
        current.copyWith(
          status: DownloadStatus.failed,
          errorMessage: _friendlyError(error),
          clearBackgroundTaskId: true,
        ),
      );
    }
  }

  Future<void> cancel(String id) async {
    _pausedJobs.remove(id);
    _activeTokens.remove(id)?.cancel('Cancelled by user');
    final taskId = _backgroundTaskIds.remove(id);
    if (taskId != null) {
      await FlutterDownloader.cancel(taskId: taskId);
    }
    final current = _find(id);
    if (current == null || !_activeJobs.contains(id)) return;
    _replace(
      current.copyWith(
        status: DownloadStatus.cancelled,
        clearBackgroundTaskId: true,
      ),
    );
  }

  Future<YoutubeDownloadOption> _freshOption(
    DownloadItem item,
    YoutubeDownloadOption original,
  ) async {
    try {
      final options = await _youtubeService.getDownloadOptions(item.videoId);
      for (final candidate in options) {
        if (candidate.kind == original.kind &&
            candidate.qualityLabel == original.qualityLabel) {
          return candidate;
        }
      }
    } catch (_) {
      // Keep the picker option as a bounded offline/provider fallback.
    }
    return original;
  }

  Future<void> delete(String id) async {
    final current = _find(id);
    _activeTokens.remove(id)?.cancel('Deleted by user');
    final taskId = _backgroundTaskIds.remove(id);
    if (taskId != null) {
      await FlutterDownloader.cancel(taskId: taskId);
    }
    if (current?.filePath != null) {
      final file = File(current!.filePath!);
      if (await file.exists()) await file.delete();
    }
    if (taskId != null && FlutterDownloader.initialized) {
      await FlutterDownloader.remove(taskId: taskId);
    }
    _pausedJobs.remove(id);
    _activeJobs.remove(id);
    _items.removeWhere((item) => item.id == id);
    await _persist();
    notifyListeners();
  }

  Future<File?> fileForItem(DownloadItem item) async {
    final path = item.filePath;
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  Future<void> _removeMissingFiles() async {
    final existing = <DownloadItem>[];
    for (final item in _items) {
      if (!item.isCompleted || item.filePath == null) {
        existing.add(item);
        continue;
      }
      if (await File(item.filePath!).exists()) existing.add(item);
    }
    _items
      ..clear()
      ..addAll(existing);
    await _persist();
  }

  Future<File> _fileFor(DownloadItem item) async {
    final directory =
        _directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, _directoryName),
        );
    if (!await directory.exists()) await directory.create(recursive: true);
    final base = _safeFileName('${item.videoId}_${item.qualityLabel}');
    return File(p.join(directory.path, '$base.${item.extension}'));
  }

  DownloadItem? _find(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _replace(DownloadItem item, {bool persist = true}) {
    final index = _items.indexWhere((entry) => entry.id == item.id);
    if (index < 0) {
      _items.insert(0, item);
    } else {
      _items[index] = item;
    }
    if (persist) unawaited(_persist());
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _catalogKey,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }

  String _extensionFor(YoutubeDownloadOption option) => switch (option.kind) {
    DownloadKind.classicAudio => option.container == 'mp4' ? 'm4a' : 'webm',
    DownloadKind.mp3Audio => 'mp3',
    DownloadKind.video => 'mp4',
  };

  int? _knownTotal(int firstBytes, int? secondTotal) =>
      secondTotal == null ? null : firstBytes + secondTotal;

  String _safeFileName(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return normalized.length > 100 ? normalized.substring(0, 100) : normalized;
  }

  String _friendlyError(Object error) {
    if (error is HttpException) return 'Network download failed.';
    if (error is SocketException) return 'Connection unavailable.';
    return error.toString().replaceFirst('StateError: ', '');
  }

  @override
  void dispose() {
    _downloadEventsPort?.close();
    IsolateNameServer.removePortNameMapping(_downloadEventsPortName);
    _dio.close(force: true);
    super.dispose();
  }
}

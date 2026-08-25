import 'dart:async';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/download_item.dart';
import '../models/media_track.dart';

class YoutubeDownloadOption {
  const YoutubeDownloadOption({
    required this.id,
    required this.kind,
    required this.qualityLabel,
    required this.container,
    required this.primaryUri,
    required this.sizeBytes,
    this.exactSize = true,
    this.bitrateKbps,
    this.audioUri,
    this.videoUri,
  });

  final String id;
  final DownloadKind kind;
  final String qualityLabel;
  final String container;
  final Uri primaryUri;
  final int? sizeBytes;
  final bool exactSize;
  final int? bitrateKbps;
  final Uri? audioUri;
  final Uri? videoUri;

  bool get requiresMuxing => audioUri != null && videoUri != null;
}

class YoutubeVideoResult {
  const YoutubeVideoResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    this.viewCount,
    this.description = '',
    this.uploadDate,
  });

  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final Uri? thumbnailUrl;
  final int? viewCount;
  final String description;
  final DateTime? uploadDate;

  MediaTrack toMediaTrack() {
    return MediaTrack.fromYoutube(
      id: videoId,
      title: title,
      artist: author,
      duration: duration,
      artworkUri: thumbnailUrl,
      viewCount: viewCount,
      channelName: author,
    );
  }
}

/// Source-only YouTube integration. It does not require an API key or backend.
///
/// The service is intentionally kept separate from playback so search, metadata
/// mapping, and URL extraction can be tested or replaced independently.
class YoutubeSearchPage {
  const YoutubeSearchPage(this.results, this._next);

  final List<YoutubeVideoResult> results;
  final Future<YoutubeSearchPage?> Function()? _next;

  Future<YoutubeSearchPage?> nextPage() =>
      _next == null ? Future.value(null) : _next!();
}

class YoutubeService {
  YoutubeService({YoutubeExplode? client})
    : _client = client ?? YoutubeExplode();

  static const _requestTimeout = Duration(seconds: 20);
  static const _maxAttempts = 3;
  static const _fallbackInstances = <String>[
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.reallyaweso.me',
  ];

  final YoutubeExplode _client;
  bool _closed = false;

  Future<List<YoutubeVideoResult>> searchVideos(
    String query, {
    int limit = 20,
  }) async {
    _ensureOpen();
    final normalized = query.trim();
    if (normalized.isEmpty) return const <YoutubeVideoResult>[];
    if (limit <= 0) return const <YoutubeVideoResult>[];

    final directId = extractVideoId(normalized);
    if (directId != null) {
      try {
        return <YoutubeVideoResult>[await getVideo(directId)];
      } catch (_) {
        return <YoutubeVideoResult>[];
      }
    }

    try {
      final results = await _withRetry(() => _client.search.search(normalized));
      return results
          .whereType<Video>()
          .take(limit)
          .map(_mapVideo)
          .toList(growable: false);
    } catch (_) {
      return _fallbackSearch(normalized, limit: limit);
    }
  }

  Future<YoutubeSearchPage> searchVideosPage(
    String query, {
    int limit = 20,
  }) async {
    _ensureOpen();
    final page = await _withRetry(() => _client.search.search(query.trim()));
    return _mapSearchPage(page, limit: limit);
  }

  YoutubeSearchPage _mapSearchPage(VideoSearchList page, {required int limit}) {
    final results = page.take(limit).map(_mapVideo).toList(growable: false);
    return YoutubeSearchPage(results, () async {
      final next = await page.nextPage();
      if (next == null) return null;
      return _mapSearchPage(next, limit: limit);
    });
  }

  Future<Uri> getAudioStreamUrl(String videoId) async {
    _ensureOpen();
    final normalizedId = extractVideoId(videoId) ?? videoId.trim();
    if (normalizedId.isEmpty) {
      throw const FormatException('A YouTube video ID is required.');
    }

    try {
      final manifest = await _withRetry(
        () => _client.videos.streams.getManifest(normalizedId),
      );
      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        throw StateError('No audio-only stream was found.');
      }
      audioStreams.sort((a, b) {
        final aMp4 = a.container == StreamContainer.mp4;
        final bMp4 = b.container == StreamContainer.mp4;
        if (aMp4 != bMp4) return aMp4 ? -1 : 1;
        return b.bitrate.compareTo(a.bitrate);
      });
      final url = audioStreams.first.url;
      if (url.scheme != 'http' && url.scheme != 'https') {
        throw StateError('The audio stream URL is invalid.');
      }
      return url;
    } catch (primaryError) {
      final fallback = await _fallbackAudio(normalizedId);
      if (fallback != null) return fallback;
      throw StateError(
        'Audio stream unavailable after primary and fallback attempts: $primaryError',
      );
    }
  }

  String? extractVideoId(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    String? valid(String? candidate) {
      if (candidate == null) return null;
      return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate)
          ? candidate
          : null;
    }

    final uri = Uri.tryParse(value);
    if (uri != null) {
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return valid(uri.pathSegments.first);
      }
      if (uri.host.contains('youtube.com')) {
        final queryId = valid(uri.queryParameters['v']);
        if (queryId != null) return queryId;
        if (uri.pathSegments.length >= 2 &&
            (uri.pathSegments.first == 'shorts' ||
                uri.pathSegments.first == 'embed')) {
          return valid(uri.pathSegments[1]);
        }
      }
    }
    final directId = valid(value);
    if (directId != null) return directId;
    final match = RegExp(
      r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|shorts/|embed/))([A-Za-z0-9_-]{11})',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1);
  }

  Future<List<YoutubeDownloadOption>> getDownloadOptions(
    String videoId, {
    Duration? duration,
  }) async {
    _ensureOpen();
    final normalizedId = extractVideoId(videoId) ?? videoId.trim();
    if (normalizedId.isEmpty) {
      throw const FormatException('A YouTube video ID is required.');
    }

    final manifest = await _withRetry(
      () => _client.videos.streams.getManifest(normalizedId),
    );
    final audio =
        manifest.audioOnly.toList()..sort((a, b) {
          final aMp4 = a.container == StreamContainer.mp4;
          final bMp4 = b.container == StreamContainer.mp4;
          if (aMp4 != bMp4) return aMp4 ? -1 : 1;
          return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
        });
    if (audio.isEmpty) {
      throw StateError('No audio-only stream was found.');
    }

    final bestAudio = audio.first;
    final bestAudioSize = _knownBytes(bestAudio.size.totalBytes);
    final options = <YoutubeDownloadOption>[
      YoutubeDownloadOption(
        id: '$normalizedId-classic',
        kind: DownloadKind.classicAudio,
        qualityLabel: 'Original audio',
        container: bestAudio.container.name,
        primaryUri: bestAudio.url,
        sizeBytes: bestAudioSize,
        bitrateKbps: (bestAudio.bitrate.bitsPerSecond / 1000).round(),
      ),
      YoutubeDownloadOption(
        id: '$normalizedId-mp3',
        kind: DownloadKind.mp3Audio,
        qualityLabel: 'MP3 · best bitrate',
        container: 'mp3',
        primaryUri: bestAudio.url,
        sizeBytes: duration == null ? null : _estimateMp3Bytes(duration),
        exactSize: false,
        bitrateKbps: 320,
      ),
    ];

    final audioForMux = audio.firstWhere(
      (stream) => stream.container == StreamContainer.mp4,
      orElse: () => bestAudio,
    );
    final byHeight = <int, YoutubeDownloadOption>{};
    for (final stream in manifest.muxed) {
      if (stream.container != StreamContainer.mp4) continue;
      _addVideoOption(
        byHeight,
        YoutubeDownloadOption(
          id: '$normalizedId-video-${stream.videoResolution.height}-muxed',
          kind: DownloadKind.video,
          qualityLabel: '${stream.videoResolution.height}p',
          container: 'mp4',
          primaryUri: stream.url,
          sizeBytes: _knownBytes(stream.size.totalBytes),
        ),
      );
    }
    for (final stream in manifest.videoOnly) {
      if (stream.container != StreamContainer.mp4) continue;
      final videoBytes = _knownBytes(stream.size.totalBytes);
      final audioBytes = _knownBytes(audioForMux.size.totalBytes);
      _addVideoOption(
        byHeight,
        YoutubeDownloadOption(
          id: '$normalizedId-video-${stream.videoResolution.height}-adaptive',
          kind: DownloadKind.video,
          qualityLabel: '${stream.videoResolution.height}p',
          container: 'mp4',
          primaryUri: stream.url,
          videoUri: stream.url,
          audioUri: audioForMux.url,
          sizeBytes:
              videoBytes != null && audioBytes != null
                  ? videoBytes + audioBytes
                  : null,
          exactSize: false,
        ),
      );
    }
    options.addAll(
      byHeight.values.toList()..sort((a, b) {
        final aHeight = int.tryParse(a.qualityLabel.replaceAll('p', '')) ?? 0;
        final bHeight = int.tryParse(b.qualityLabel.replaceAll('p', '')) ?? 0;
        return aHeight.compareTo(bHeight);
      }),
    );
    return options;
  }

  void _addVideoOption(
    Map<int, YoutubeDownloadOption> options,
    YoutubeDownloadOption candidate,
  ) {
    final height = int.tryParse(candidate.qualityLabel.replaceAll('p', ''));
    if (height == null) return;
    final existing = options[height];
    if (existing == null ||
        (existing.requiresMuxing && !candidate.requiresMuxing)) {
      options[height] = candidate;
    }
  }

  int? _knownBytes(int bytes) => bytes > 0 ? bytes : null;

  int _estimateMp3Bytes(Duration duration) =>
      ((duration.inMilliseconds / 1000) * 320000 / 8).ceil();

  Future<Uri> getVideoStreamUrl(String videoId) async {
    _ensureOpen();
    final normalizedId = videoId.trim();
    if (normalizedId.isEmpty) {
      throw const FormatException('A YouTube video ID is required.');
    }
    final manifest = await _withRetry(
      () => _client.videos.streams.getManifest(normalizedId),
    );
    final muxedStreams = manifest.muxed;
    if (muxedStreams.isEmpty) {
      throw StateError(
        'No compatible video stream was found for YouTube video $normalizedId.',
      );
    }
    return muxedStreams.withHighestBitrate().url;
  }

  Future<YoutubeVideoResult> getVideo(String videoId) async {
    _ensureOpen();
    final normalizedId = videoId.trim();
    if (normalizedId.isEmpty)
      throw const FormatException('A YouTube video ID is required.');
    final video = await _withRetry(() => _client.videos.get(normalizedId));
    return _mapVideo(video);
  }

  YoutubeVideoResult _mapVideo(Video video) {
    return YoutubeVideoResult(
      videoId: video.id.value,
      title: video.title.trim().isEmpty ? 'Untitled video' : video.title,
      author: video.author.trim().isEmpty ? 'Unknown channel' : video.author,
      duration: video.duration,
      thumbnailUrl: Uri.tryParse(video.thumbnails.highResUrl),
      viewCount: video.engagement.viewCount,
      description: video.description,
      uploadDate: video.uploadDate ?? video.publishDate,
    );
  }

  Future<Uri?> _fallbackAudio(String videoId) async {
    for (final instance in _fallbackInstances) {
      try {
        final response = await http
            .get(
              Uri.parse('$instance/streams/$videoId'),
              headers: const <String, String>{'Accept': 'application/json'},
            )
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final json = jsonDecode(response.body);
        final rawStreams =
            json is Map<String, dynamic> ? json['audioStreams'] : null;
        if (rawStreams is! List) continue;
        final candidates =
            rawStreams.whereType<Map<String, dynamic>>().where((item) {
              final url = item['url']?.toString() ?? '';
              final mime = item['mimeType']?.toString() ?? '';
              return url.startsWith('http') &&
                  (mime.startsWith('audio/') || mime.isEmpty);
            }).toList();
        candidates.sort(
          (a, b) => ((b['bitrate'] as num?)?.toInt() ?? 0).compareTo(
            (a['bitrate'] as num?)?.toInt() ?? 0,
          ),
        );
        if (candidates.isNotEmpty)
          return Uri.tryParse(candidates.first['url'].toString());
      } catch (_) {}
    }
    return null;
  }

  Future<List<YoutubeVideoResult>> _fallbackSearch(
    String query, {
    required int limit,
  }) async {
    for (final instance in _fallbackInstances) {
      try {
        final response = await http
            .get(
              Uri.parse('$instance/search').replace(
                queryParameters: <String, String>{
                  'q': query,
                  'filter': 'videos',
                },
              ),
            )
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final json = jsonDecode(response.body);
        if (json is! List) continue;
        final results = <YoutubeVideoResult>[];
        for (final item in json.whereType<Map<String, dynamic>>()) {
          final id =
              item['url']?.toString().split('/').last ?? item['id']?.toString();
          final title = item['title']?.toString();
          if (id == null || title == null || id.isEmpty) continue;
          results.add(
            YoutubeVideoResult(
              videoId: id,
              title: title,
              author: item['uploaderName']?.toString() ?? 'Unknown channel',
              duration: Duration(
                seconds: (item['duration'] as num?)?.toInt() ?? 0,
              ),
              thumbnailUrl: Uri.tryParse(item['thumbnail']?.toString() ?? ''),
              viewCount: (item['views'] as num?)?.toInt(),
            ),
          );
          if (results.length >= limit) break;
        }
        if (results.isNotEmpty) return results;
      } catch (_) {}
    }
    return const <YoutubeVideoResult>[];
  }

  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await operation().timeout(_requestTimeout);
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        if (attempt == _maxAttempts - 1) break;
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (1 << attempt)),
        );
        _ensureOpen();
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('YouTube request failed.'),
      lastStack ?? StackTrace.current,
    );
  }

  void _ensureOpen() {
    if (_closed) throw StateError('YoutubeService has already been disposed.');
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

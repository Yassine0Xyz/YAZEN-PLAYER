import 'dart:async';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/media_track.dart';

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
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        throw StateError('No audio-only stream was found.');
      }
      final url = audioStreams.withHighestBitrate().url;
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
    final uri = Uri.tryParse(value);
    if (uri != null) {
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      if (uri.host.contains('youtube.com')) {
        final queryId = uri.queryParameters['v'];
        if (queryId != null && queryId.isNotEmpty) return queryId;
        if (uri.pathSegments.length >= 2 &&
            (uri.pathSegments.first == 'shorts' ||
                uri.pathSegments.first == 'embed')) {
          return uri.pathSegments[1];
        }
      }
    }
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value)) return value;
    final match = RegExp(
      r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|shorts/|embed/))([A-Za-z0-9_-]{11})',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1);
  }

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

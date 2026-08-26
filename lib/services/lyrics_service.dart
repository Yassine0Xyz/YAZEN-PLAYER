import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class LyricLine {
  const LyricLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;
}

class SyncedLyrics {
  const SyncedLyrics({required this.lines, this.plainText});

  final List<LyricLine> lines;
  final String? plainText;

  bool get isSynced => lines.isNotEmpty;
}

class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, Future<SyncedLyrics?>> _requests =
      <String, Future<SyncedLyrics?>>{};

  Future<SyncedLyrics?> loadFor(MediaItem item) {
    return _requests.putIfAbsent(item.id, () => _loadFor(item));
  }

  Future<SyncedLyrics?> _loadFor(MediaItem item) async {
    final localLyrics = await _loadAdjacentLrc(item.id);
    if (localLyrics != null) return localLyrics;

    final title = item.title.trim();
    final artist = (item.artist ?? '').trim();
    if (title.isEmpty || artist.isEmpty) return null;

    final query = <String, String>{
      'track_name': title,
      'artist_name': artist,
    };
    final album = (item.album ?? '').trim();
    if (album.isNotEmpty) query['album_name'] = album;
    final durationSeconds = item.duration?.inSeconds ?? 0;
    if (durationSeconds > 0 && durationSeconds <= 3600) {
      query['duration'] = durationSeconds.toString();
    }

    final uri = Uri.https('lrclib.net', '/api/get', query);
    try {
      var response = await _client.get(uri, headers: _headers);
      if (response.statusCode == 429) {
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        final wait = Duration(
          seconds: (retryAfter ?? 1).clamp(1, 8),
        );
        await Future<void>.delayed(wait);
        response = await _client.get(uri, headers: _headers);
      }
      if (response.statusCode != 200) return null;

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final synced = payload['syncedLyrics']?.toString();
      final plain = payload['plainLyrics']?.toString();
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = parseLrc(synced);
        return SyncedLyrics(lines: parsed, plainText: plain);
      }
      if (plain != null && plain.trim().isNotEmpty) {
        return SyncedLyrics(lines: const <LyricLine>[], plainText: plain);
      }
    } on FormatException {
      return null;
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    }
    return null;
  }

  static const _headers = <String, String>{
    'Accept': 'application/json',
    'User-Agent':
        'YAZEN/1.1 (https://github.com/Yassine0Xyz/YAZEN-PLAYER)',
  };

  /// Parses standard LRC timestamps and applies an optional `[offset:...]`
  /// metadata value. Positive offset moves lines later; negative offset moves
  /// them earlier. Several timestamps on one line are expanded so karaoke
  /// files with repeated timestamps remain synchronized.
  List<LyricLine> parseLrc(String source) {
    final lines = <LyricLine>[];
    final offsetMs = _parseOffsetMilliseconds(source);
    final timestampPattern = RegExp(
      r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]',
    );

    for (final rawLine in const LineSplitter().convert(source)) {
      final matches = timestampPattern
          .allMatches(rawLine)
          .toList(growable: false);
      if (matches.isEmpty) continue;
      final text = rawLine.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1)!) ?? 0;
        final seconds = int.tryParse(match.group(2)!) ?? 0;
        final fraction = match.group(3) ?? '0';
        final milliseconds = switch (fraction.length) {
          1 => (int.tryParse(fraction) ?? 0) * 100,
          2 => (int.tryParse(fraction) ?? 0) * 10,
          _ => int.tryParse(fraction.substring(0, 3)) ?? 0,
        };
        final rawTimestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );
        final shifted = rawTimestamp + Duration(milliseconds: offsetMs);
        lines.add(
          LyricLine(
            timestamp: shifted.isNegative ? Duration.zero : shifted,
            text: text,
          ),
        );
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  int _parseOffsetMilliseconds(String source) {
    final match = RegExp(
      r'^\s*\[offset\s*:\s*(-?\d+)\s*\]\s*$',
      multiLine: true,
    ).firstMatch(source);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<SyncedLyrics?> _loadAdjacentLrc(String id) async {
    if (!id.startsWith('file://')) return null;
    final audioPath = Uri.parse(id).toFilePath();
    final lrcPath = p.setExtension(audioPath, '.lrc');
    final file = File(lrcPath);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return SyncedLyrics(lines: parseLrc(content), plainText: content);
  }

  void dispose() => _client.close();
}

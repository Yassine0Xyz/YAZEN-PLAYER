import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
  bool get isPlain => !isSynced && (plainText?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lines': lines
        .map(
          (line) => <String, dynamic>{
            'timestampMs': line.timestamp.inMilliseconds,
            'text': line.text,
          },
        )
        .toList(growable: false),
    'plainText': plainText,
  };

  factory SyncedLyrics.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lines = <LyricLine>[];
    if (rawLines is List) {
      for (final raw in rawLines.whereType<Map>()) {
        final timestamp = (raw['timestampMs'] as num?)?.toInt();
        final text = raw['text']?.toString().trim() ?? '';
        if (timestamp != null && text.isNotEmpty) {
          lines.add(
            LyricLine(timestamp: Duration(milliseconds: timestamp), text: text),
          );
        }
      }
    }
    return SyncedLyrics(
      lines: List<LyricLine>.unmodifiable(lines),
      plainText: json['plainText']?.toString(),
    );
  }
}

class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  static const _cachePrefix = 'yazen.lyrics.';
  static const _requestTimeout = Duration(seconds: 5);

  final http.Client _client;

  Future<SyncedLyrics?> loadFor(MediaItem item) async {
    // Offline-first: keep the user's own LRC/TXT files ahead of network data.
    final localLyrics = await _loadAdjacentLyrics(item.id);
    if (localLyrics != null) return localLyrics;

    final cached = await _loadCached(item.id);
    if (cached != null) return cached;

    final title = item.title.trim();
    final artist = (item.artist ?? '').trim();
    if (title.isEmpty) return null;

    final queries = _queryVariants(title, artist);
    for (final query in queries) {
      final exact = await _loadLrclibExact(query.title, query.artist);
      if (exact != null) {
        await _saveCached(item.id, exact);
        return exact;
      }
    }

    // Search is deliberately validated against title/artist. This prevents
    // LRCLIB from returning the first unrelated result for generic filenames.
    for (final query in queries) {
      final searched = await _loadLrclibSearch(query.title, query.artist);
      if (searched != null) {
        await _saveCached(item.id, searched);
        return searched;
      }
    }

    // Lyrics.ovh is a plain-text fallback. Try cleaned variants as well,
    // because local filenames frequently contain tags such as "official" or
    // "remix" that are absent from the lyrics provider's catalog.
    for (final query in queries.take(3)) {
      final plain = await _loadLyricsOvh(query.title, query.artist);
      if (plain != null) {
        await _saveCached(item.id, plain);
        return plain;
      }
    }
    return null;
  }

  List<({String title, String artist})> _queryVariants(
    String title,
    String artist,
  ) {
    final coreTitle = _withoutMetadataSuffix(title);
    final cleanTitle = _normalize(title);
    final cleanCoreTitle = _normalize(coreTitle);
    final cleanArtist = _normalize(artist);
    final values = <({String title, String artist})>[
      (title: title, artist: artist),
      (title: coreTitle, artist: artist),
      (title: cleanTitle, artist: cleanArtist),
      (title: cleanCoreTitle, artist: cleanArtist),
      (title: _withoutVersionSuffix(cleanCoreTitle), artist: cleanArtist),
    ];
    final seen = <String>{};
    return values
        .where((value) {
          final key =
              '${value.title.toLowerCase()}|${value.artist.toLowerCase()}';
          return value.title.isNotEmpty && seen.add(key);
        })
        .toList(growable: false);
  }

  Future<SyncedLyrics?> _loadLrclibExact(String title, String artist) async {
    if (title.isEmpty) return null;
    final uri = Uri.https('lrclib.net', '/api/get', <String, String>{
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
    });
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      return _fromLrclibPayload(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  Future<SyncedLyrics?> _loadLrclibSearch(String title, String artist) async {
    final query = artist.isEmpty ? title : '$artist $title';
    final uri = Uri.https('lrclib.net', '/api/search', <String, String>{
      'q': query,
    });
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! List) return null;

      final candidates = payload
          .whereType<Map>()
          .map((candidate) => Map<String, dynamic>.from(candidate))
          .where(
            (candidate) => _matchesSearchCandidate(candidate, title, artist),
          )
          .toList(growable: false);
      // Prefer synchronized results, then plain lyrics.
      candidates.sort((a, b) {
        final aSynced =
            (a['syncedLyrics']?.toString().trim().isNotEmpty ?? false);
        final bSynced =
            (b['syncedLyrics']?.toString().trim().isNotEmpty ?? false);
        return (bSynced ? 1 : 0).compareTo(aSynced ? 1 : 0);
      });
      for (final candidate in candidates.take(8)) {
        final lyrics = _fromLrclibPayload(candidate);
        if (lyrics != null) return lyrics;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _matchesSearchCandidate(
    Map<String, dynamic> candidate,
    String title,
    String artist,
  ) {
    final candidateTitle = _normalize(candidate['trackName']?.toString() ?? '');
    final candidateArtist = _normalize(
      candidate['artistName']?.toString() ?? '',
    );
    final wantedTitle = _normalize(title);
    final wantedArtist = _normalize(artist);
    if (candidateTitle.isEmpty || wantedTitle.isEmpty) return false;
    final titleMatch =
        candidateTitle == wantedTitle ||
        candidateTitle.contains(wantedTitle) ||
        wantedTitle.contains(candidateTitle);
    if (!titleMatch) return false;
    if (wantedArtist.isEmpty || candidateArtist.isEmpty) return true;
    return candidateArtist == wantedArtist ||
        candidateArtist.contains(wantedArtist) ||
        wantedArtist.contains(candidateArtist);
  }

  Future<SyncedLyrics?> _loadLyricsOvh(String title, String artist) async {
    if (artist.isEmpty) return null;
    final uri = Uri.https(
      'api.lyrics.ovh',
      '/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}',
    );
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      final lyrics = payload['lyrics']?.toString().trim();
      if (lyrics == null || lyrics.isEmpty) return null;
      return SyncedLyrics(lines: const <LyricLine>[], plainText: lyrics);
    } catch (_) {
      return null;
    }
  }

  SyncedLyrics? _fromLrclibPayload(Object? payload) {
    if (payload is! Map<String, dynamic>) return null;
    final synced = payload['syncedLyrics']?.toString().trim();
    final plain = payload['plainLyrics']?.toString().trim();
    if (synced != null && synced.isNotEmpty) {
      final lines = parseLrc(synced);
      if (lines.isNotEmpty) {
        return SyncedLyrics(lines: lines, plainText: plain);
      }
    }
    if (plain != null && plain.isNotEmpty) {
      return SyncedLyrics(lines: const <LyricLine>[], plainText: plain);
    }
    return null;
  }

  /// Parses standard LRC timestamps and applies an optional `[offset:...]`
  /// metadata value. Positive offset moves lines later; negative moves them
  /// earlier. Multiple timestamps on a line are expanded and sorted.
  List<LyricLine> parseLrc(String source) {
    final lines = <LyricLine>[];
    final offsetMs = _parseOffsetMilliseconds(source);
    final timestampPattern = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

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
    return List<LyricLine>.unmodifiable(lines);
  }

  int _parseOffsetMilliseconds(String source) {
    final match = RegExp(
      r'^\s*\[offset\s*:\s*(-?\d+)\s*\]\s*$',
      multiLine: true,
    ).firstMatch(source);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<SyncedLyrics?> _loadAdjacentLyrics(String id) async {
    if (!id.startsWith('file://')) return null;
    try {
      final audioPath = Uri.parse(id).toFilePath();
      final basePath = p.withoutExtension(audioPath);
      for (final path in <String>[
        '$basePath.lrc',
        '$basePath.LRC',
        '$basePath.txt',
        '$basePath.lyrics',
      ]) {
        final file = File(path);
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        if (content.trim().isEmpty) continue;
        final parsed = parseLrc(content);
        return SyncedLyrics(
          lines: parsed,
          plainText: parsed.isEmpty ? content.trim() : null,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<SyncedLyrics?> _loadCached(String id) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString('$_cachePrefix${_cacheKey(id)}');
      if (encoded == null || encoded.isEmpty) return null;
      return SyncedLyrics.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCached(String id, SyncedLyrics lyrics) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        '$_cachePrefix${_cacheKey(id)}',
        jsonEncode(lyrics.toJson()),
      );
    } catch (_) {}
  }

  String _cacheKey(String value) => base64UrlEncode(utf8.encode(value));

  String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ')
        .replaceAll(
          RegExp(
            r'\b(official|video|audio|lyrics|visualizer|remix|slowed|reverb|nightcore|sped up|music)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _withoutMetadataSuffix(String value) {
    return value.split(RegExp(r'\s[|•]\s')).first.trim();
  }

  String _withoutVersionSuffix(String value) {
    return value
        .replaceFirst(
          RegExp(r'\b(v\d+|part\s+\d+|version\s+\d+)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const _headers = <String, String>{
    'Accept': 'application/json',
    'User-Agent': 'YAZEN/1.0',
  };

  void dispose() => _client.close();
}

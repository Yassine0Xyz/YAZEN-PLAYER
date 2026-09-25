import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_track.dart';
import 'media_track_codec.dart';

class EchoPlaylist {
  const EchoPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    this.coverTrackId,
  });

  final String id;
  final String name;
  final List<MediaTrack> tracks;
  final String? coverTrackId;

  MediaTrack? get coverTrack {
    final id = coverTrackId;
    if (id == null) return tracks.isEmpty ? null : tracks.last;
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return tracks.isEmpty ? null : tracks.last;
  }

  EchoPlaylist copyWith({
    String? name,
    List<MediaTrack>? tracks,
    String? coverTrackId,
    bool clearCoverTrackId = false,
  }) {
    return EchoPlaylist(
      id: id,
      name: name ?? this.name,
      tracks: List<MediaTrack>.unmodifiable(tracks ?? this.tracks),
      coverTrackId:
          clearCoverTrackId ? null : (coverTrackId ?? this.coverTrackId),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'tracks': tracks.map(mediaTrackToJson).toList(growable: false),
    if (coverTrackId != null) 'coverTrackId': coverTrackId,
  };

  factory EchoPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'];
    final tracks =
        rawTracks is List
            ? rawTracks
                .whereType<Map>()
                .map(
                  (item) => mediaTrackFromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
            : const <MediaTrack>[];
    return EchoPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled playlist',
      tracks: List<MediaTrack>.unmodifiable(tracks),
      coverTrackId: json['coverTrackId']?.toString(),
    );
  }
}

/// Persistent metadata for user-created playlists and favorites on this device.
class LocalPlaylistManager extends ChangeNotifier {
  static const _playlistsKey = 'yazen.custom_playlists.v1';
  static const _favoritesKey = 'yazen.favorite_tracks.v1';
  static const _historyKey = 'yazen.play_history.v1';
  static const _metadataKey = 'yazen.track_metadata.v1';
  static const _hiddenKey = 'yazen.hidden_tracks.v1';

  SharedPreferences? _preferences;
  List<EchoPlaylist> _playlists = const <EchoPlaylist>[];
  List<MediaTrack> _favorites = const <MediaTrack>[];
  Map<String, int> _playCounts = <String, int>{};
  Map<String, DateTime> _lastPlayed = <String, DateTime>{};
  Map<String, Map<String, String>> _metadata = <String, Map<String, String>>{};
  Set<String> _hiddenIds = <String>{};
  bool _isReady = false;
  Future<void> _writeChain = Future<void>.value();

  bool get isReady => _isReady;
  List<EchoPlaylist> get playlists => _playlists;
  List<MediaTrack> get favorites => _favorites;
  Set<String> get hiddenIds => Set<String>.unmodifiable(_hiddenIds);

  bool isFavorite(MediaTrack track) =>
      _favorites.any((item) => item.id == track.id);

  Future<void> initialize() async {
    if (_isReady) return;
    _preferences = await SharedPreferences.getInstance();
    try {
      final savedPlaylists = _preferences!.getString(_playlistsKey);
      final savedFavorites = _preferences!.getString(_favoritesKey);
      _playlists =
          savedPlaylists == null
              ? const <EchoPlaylist>[]
              : _decodePlaylists(savedPlaylists);
      _favorites =
          savedFavorites == null
              ? const <MediaTrack>[]
              : _decodeTracks(savedFavorites);
      _playCounts = _decodeIntMap(_preferences!.getString(_historyKey));
      _metadata = _decodeMetadata(_preferences!.getString(_metadataKey));
      _hiddenIds = _decodeStringSet(_preferences!.getString(_hiddenKey));
    } on FormatException {
      _playlists = const <EchoPlaylist>[];
      _favorites = const <MediaTrack>[];
    }
    _isReady = true;
    notifyListeners();
  }

  int playCount(String trackId) => _playCounts[trackId] ?? 0;

  DateTime? lastPlayed(String trackId) => _lastPlayed[trackId];

  List<MediaTrack> applyMetadata(Iterable<MediaTrack> tracks) => tracks
      .map((track) {
        final values = _metadata[track.id];
        return values == null
            ? track
            : track.copyWith(
              title: values['title'],
              artist: values['artist'],
              album: values['album'],
            );
      })
      .toList(growable: false);

  Future<void> recordPlayed(MediaTrack track) async {
    _ensureReady();
    _playCounts[track.id] = playCount(track.id) + 1;
    _lastPlayed[track.id] = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// Stores a safe app-local metadata override. It deliberately does not
  /// rewrite the user's media file or MediaStore entry without explicit
  /// Android write-permission support.
  Future<void> updateTrackMetadata(
    String trackId, {
    required String title,
    required String artist,
    required String album,
  }) async {
    _ensureReady();
    final values = <String, String>{
      'title': title.trim().isEmpty ? 'Unknown title' : title.trim(),
      'artist': artist.trim().isEmpty ? 'Unknown artist' : artist.trim(),
      'album': album.trim().isEmpty ? 'Unknown album' : album.trim(),
    };
    _metadata[trackId] = values;
    MediaTrack update(MediaTrack track) =>
        track.id == trackId
            ? track.copyWith(
              title: values['title'],
              artist: values['artist'],
              album: values['album'],
            )
            : track;
    _favorites = List<MediaTrack>.unmodifiable(_favorites.map(update));
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map(
            (playlist) => playlist.copyWith(
              tracks: playlist.tracks.map(update).toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setHidden(
    Iterable<String> trackIds, {
    required bool hidden,
  }) async {
    _ensureReady();
    if (hidden) {
      _hiddenIds.addAll(trackIds);
    } else {
      _hiddenIds.removeAll(trackIds);
    }
    notifyListeners();
    await _persist();
  }

  bool isHidden(String trackId) => _hiddenIds.contains(trackId);

  Future<void> toggleFavorite(MediaTrack track) async {
    _ensureReady();
    final next = List<MediaTrack>.from(_favorites);
    final existingIndex = next.indexWhere((item) => item.id == track.id);
    if (existingIndex >= 0) {
      next.removeAt(existingIndex);
    } else {
      next.add(track);
    }
    _favorites = List<MediaTrack>.unmodifiable(next);
    notifyListeners();
    await _persist();
  }

  Future<EchoPlaylist> createPlaylist(String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Playlist name cannot be empty.');
    }
    final playlist = EchoPlaylist(
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      name: normalized,
      tracks: const <MediaTrack>[],
    );
    _playlists = List<EchoPlaylist>.unmodifiable(<EchoPlaylist>[
      ..._playlists,
      playlist,
    ]);
    notifyListeners();
    await _persist();
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Playlist name cannot be empty.');
    }
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map(
            (playlist) =>
                playlist.id == playlistId
                    ? playlist.copyWith(name: normalized)
                    : playlist,
          )
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.where((playlist) => playlist.id != playlistId),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> addToFavorites(Iterable<MediaTrack> tracks) async {
    _ensureReady();
    final next = List<MediaTrack>.from(_favorites);
    for (final track in tracks) {
      if (!next.any((item) => item.id == track.id)) next.add(track);
    }
    _favorites = List<MediaTrack>.unmodifiable(next);
    notifyListeners();
    await _persist();
  }

  Future<void> addToPlaylist(String playlistId, MediaTrack track) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId ||
                playlist.tracks.any((item) => item.id == track.id)) {
              return playlist;
            }
            return playlist.copyWith(
              tracks: <MediaTrack>[...playlist.tracks, track],
              coverTrackId: track.id,
            );
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    Iterable<MediaTrack> tracks,
  ) async {
    _ensureReady();
    final additions = <MediaTrack>[];
    for (final track in tracks) {
      if (!additions.any((item) => item.id == track.id)) additions.add(track);
    }
    if (additions.isEmpty) return;
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId) return playlist;
            final next = List<MediaTrack>.from(playlist.tracks);
            MediaTrack? lastAdded;
            for (final track in additions) {
              if (!next.any((item) => item.id == track.id)) {
                next.add(track);
                lastAdded = track;
              }
            }
            return lastAdded == null
                ? playlist
                : playlist.copyWith(tracks: next, coverTrackId: lastAdded.id);
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveWithinPlaylist(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId ||
                oldIndex < 0 ||
                oldIndex >= playlist.tracks.length ||
                newIndex < 0 ||
                newIndex >= playlist.tracks.length) {
              return playlist;
            }
            final tracks = List<MediaTrack>.from(playlist.tracks);
            final track = tracks.removeAt(oldIndex);
            tracks.insert(newIndex, track);
            return playlist.copyWith(tracks: tracks);
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) =>
      removeTracksFromPlaylist(playlistId, <String>{trackId});

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    Iterable<String> trackIds,
  ) async {
    _ensureReady();
    final ids = trackIds.toSet();
    if (ids.isEmpty) return;
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId) return playlist;
            final tracks = playlist.tracks
                .where((track) => !ids.contains(track.id))
                .toList(growable: false);
            final coverId = playlist.coverTrackId;
            final nextCoverId =
                coverId != null && tracks.any((track) => track.id == coverId)
                    ? coverId
                    : (tracks.isEmpty ? null : tracks.last.id);
            return nextCoverId == null
                ? playlist.copyWith(tracks: tracks, clearCoverTrackId: true)
                : playlist.copyWith(tracks: tracks, coverTrackId: nextCoverId);
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> clearFavorites() async {
    _ensureReady();
    _favorites = const <MediaTrack>[];
    notifyListeners();
    await _persist();
  }

  void _ensureReady() {
    if (!_isReady) {
      throw StateError(
        'LocalPlaylistManager.initialize() must complete before use.',
      );
    }
  }

  Future<void> _persist() {
    _writeChain = _writeChain.then((_) async {
      final preferences = _preferences;
      if (preferences == null) return;
      await preferences.setString(
        _playlistsKey,
        jsonEncode(
          _playlists
              .map((playlist) => playlist.toJson())
              .toList(growable: false),
        ),
      );
      await preferences.setString(
        _favoritesKey,
        jsonEncode(_favorites.map(mediaTrackToJson).toList(growable: false)),
      );
      await preferences.setString(
        _historyKey,
        jsonEncode(<String, dynamic>{
          'counts': _playCounts,
          'lastPlayed': _lastPlayed.map(
            (key, value) => MapEntry(key, value.toIso8601String()),
          ),
        }),
      );
      await preferences.setString(_metadataKey, jsonEncode(_metadata));
      await preferences.setString(_hiddenKey, jsonEncode(_hiddenIds.toList()));
    });
    return _writeChain;
  }

  List<EchoPlaylist> _decodePlaylists(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid playlist data.');
    return List<EchoPlaylist>.unmodifiable(
      decoded
          .whereType<Map>()
          .map((item) => EchoPlaylist.fromJson(Map<String, dynamic>.from(item)))
          .where((playlist) => playlist.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  List<MediaTrack> _decodeTracks(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid favorite data.');
    return List<MediaTrack>.unmodifiable(
      decoded
          .whereType<Map>()
          .map((item) => mediaTrackFromJson(Map<String, dynamic>.from(item)))
          .where((track) => track.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, int> _decodeIntMap(String? value) {
    if (value == null) return <String, int>{};
    try {
      final decoded = jsonDecode(value);
      final counts = decoded is Map ? decoded['counts'] : decoded;
      final last = decoded is Map ? decoded['lastPlayed'] : null;
      if (last is Map) {
        for (final entry in last.entries) {
          final date = DateTime.tryParse(entry.value.toString());
          if (date != null) _lastPlayed[entry.key.toString()] = date;
        }
      }
      return counts is Map
          ? <String, int>{
            for (final entry in counts.entries)
              entry.key.toString():
                  entry.value is num ? (entry.value as num).toInt() : 0,
          }
          : <String, int>{};
    } catch (_) {
      return <String, int>{};
    }
  }

  Map<String, Map<String, String>> _decodeMetadata(String? value) {
    if (value == null) return <String, Map<String, String>>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return <String, Map<String, String>>{};
      return <String, Map<String, String>>{
        for (final entry in decoded.entries)
          entry.key.toString():
              entry.value is Map
                  ? <String, String>{
                    for (final field in (entry.value as Map).entries)
                      field.key.toString(): field.value.toString(),
                  }
                  : <String, String>{},
      };
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  Set<String> _decodeStringSet(String? value) {
    if (value == null) return <String>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is List
          ? decoded.map((item) => item.toString()).toSet()
          : <String>{};
    } catch (_) {
      return <String>{};
    }
  }
}

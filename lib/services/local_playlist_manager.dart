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
  }) {
    return EchoPlaylist(
      id: id,
      name: name ?? this.name,
      tracks: List<MediaTrack>.unmodifiable(tracks ?? this.tracks),
      coverTrackId: coverTrackId ?? this.coverTrackId,
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

  SharedPreferences? _preferences;
  List<EchoPlaylist> _playlists = const <EchoPlaylist>[];
  List<MediaTrack> _favorites = const <MediaTrack>[];
  bool _isReady = false;
  Future<void> _writeChain = Future<void>.value();

  bool get isReady => _isReady;
  List<EchoPlaylist> get playlists => _playlists;
  List<MediaTrack> get favorites => _favorites;

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
    } on FormatException {
      _playlists = const <EchoPlaylist>[];
      _favorites = const <MediaTrack>[];
    }
    _isReady = true;
    notifyListeners();
  }

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
            return playlist.copyWith(tracks: tracks, coverTrackId: nextCoverId);
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
}

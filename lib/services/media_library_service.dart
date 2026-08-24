import 'dart:async';

import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import '../models/media_track.dart';

class MediaLibraryService {
  MediaLibraryService({OnAudioQuery? audioQuery})
    : _audioQuery = audioQuery ?? OnAudioQuery();

  static const MethodChannel _localMediaChannel = MethodChannel(
    'yazen/local_media',
  );

  final OnAudioQuery _audioQuery;
  bool? _permissionGranted;

  bool? get permissionGranted => _permissionGranted;

  Future<bool> ensurePermission() async {
    if (await _audioQuery.permissionsStatus()) {
      _permissionGranted = true;
      return true;
    }
    _permissionGranted = await _audioQuery.permissionsRequest();
    return _permissionGranted ?? false;
  }

  Future<List<MediaTrack>> querySongs() async {
    if (!await ensurePermission()) return const <MediaTrack>[];
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
    return songs.map(MediaTrack.fromSong).toList(growable: false);
  }

  Future<List<ArtistModel>> queryArtists() async {
    if (!await ensurePermission()) return const <ArtistModel>[];
    return _audioQuery.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
  }

  Future<List<AlbumModel>> queryAlbums() async {
    if (!await ensurePermission()) return const <AlbumModel>[];
    return _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
  }

  Future<List<PlaylistModel>> queryPlaylists() async {
    if (!await ensurePermission()) return const <PlaylistModel>[];
    return _audioQuery.queryPlaylists(
      sortType: PlaylistSortType.PLAYLIST,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
  }

  Future<List<String>> queryFolders() async {
    final songs = await querySongs();
    final folders =
        songs
            .map((song) => song.folder)
            .whereType<String>()
            .where((folder) => folder.isNotEmpty)
            .map(p.basename)
            .toSet()
            .toList();
    folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return folders;
  }

  Future<List<MediaTrack>> queryVideos() async {
    bool granted = false;
    try {
      granted =
          await _localMediaChannel.invokeMethod<bool>(
            'requestVideoPermission',
          ) ??
          false;
    } on PlatformException {
      return const <MediaTrack>[];
    }

    // Android returns false while its permission dialog is still open. Poll
    // briefly so the user does not need to leave and re-enter the tab.
    for (var attempt = 0; attempt < 6 && !granted; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        final result = await _localMediaChannel.invokeMethod<bool>(
          'requestVideoPermission',
        );
        granted = result ?? false;
      } on PlatformException {
        return const <MediaTrack>[];
      }
    }
    if (!granted) return const <MediaTrack>[];

    try {
      final raw = await _localMediaChannel.invokeMethod<List<dynamic>>(
        'queryVideos',
      );
      if (raw == null) return const <MediaTrack>[];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) {
            final path = entry['path']?.toString() ?? '';
            final uri = entry['uri']?.toString();
            final title = entry['title']?.toString() ?? 'Local video';
            final durationMs =
                entry['durationMs'] is num
                    ? (entry['durationMs'] as num).toInt()
                    : 0;
            return MediaTrack.fromLocalVideo(
              path: path,
              contentUri: uri,
              title: title,
              duration:
                  durationMs > 0 ? Duration(milliseconds: durationMs) : null,
            );
          })
          .toList(growable: false);
    } on PlatformException {
      return const <MediaTrack>[];
    }
  }
}

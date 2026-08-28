import 'dart:async';

import 'dart:io';

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
  Future<bool>? _permissionRequest;

  bool? get permissionGranted => _permissionGranted;

  Future<bool> ensurePermission() {
    final cached = _permissionGranted;
    if (cached != null) return Future<bool>.value(cached);
    final activeRequest = _permissionRequest;
    if (activeRequest != null) return activeRequest;
    final request = _requestPermission();
    _permissionRequest = request;
    return request.whenComplete(() {
      if (identical(_permissionRequest, request)) {
        _permissionRequest = null;
      }
    });
  }

  Future<bool> _requestPermission() async {
    try {
      if (await _audioQuery.permissionsStatus()) {
        _permissionGranted = true;
        return true;
      }
      _permissionGranted = await _audioQuery.permissionsRequest();
      return _permissionGranted ?? false;
    } catch (_) {
      _permissionGranted = false;
      return false;
    }
  }

  Future<List<MediaTrack>> querySongs() async {
    if (!await ensurePermission()) return const <MediaTrack>[];
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
    return _toMediaTracks(songs);
  }

  Future<List<MediaTrack>> querySongsFrom(
    AudiosFromType type,
    Object where,
  ) async {
    if (!await ensurePermission()) return const <MediaTrack>[];
    final songs = await _audioQuery.queryAudiosFrom(
      type,
      where,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
    return _toMediaTracks(songs);
  }

  Future<List<MediaTrack>> querySongsInFolder(String folder) async {
    final songs = await querySongs();
    return songs
        .where((track) {
          final path = track.folder ?? '';
          return p.basename(p.normalize(path)) == folder || path == folder;
        })
        .toList(growable: false);
  }

  Future<List<MediaTrack>> _toMediaTracks(Iterable<SongModel> songs) async {
    final tracks = <MediaTrack>[];
    for (final song in songs) {
      final track = MediaTrack.fromSong(song);
      try {
        final stat = await File(song.data).stat();
        tracks.add(
          track.copyWith(sizeBytes: stat.size, modifiedAt: stat.modified),
        );
      } on FileSystemException {
        tracks.add(track);
      }
    }
    return tracks;
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

  Future<List<MediaTrack>> queryVideos({bool requestPermission = true}) async {
    bool granted = false;
    try {
      granted =
          await _localMediaChannel.invokeMethod<bool>(
            requestPermission
                ? 'requestVideoPermission'
                : 'videoPermissionStatus',
          ) ??
          false;
    } on MissingPluginException {
      return const <MediaTrack>[];
    } on PlatformException {
      return const <MediaTrack>[];
    }

    // Android returns false while its permission dialog is still open.
    // Poll briefly only when the user explicitly opened Local Videos.
    for (
      var attempt = 0;
      requestPermission && attempt < 6 && !granted;
      attempt++
    ) {
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

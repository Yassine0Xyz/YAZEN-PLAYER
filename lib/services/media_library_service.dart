import 'dart:async';

import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/media_track.dart';
import 'folder_identity.dart';

class MediaLibraryService {
  MediaLibraryService({
    OnAudioQuery? audioQuery,
    Future<bool> Function()? permissionStatus,
    Future<bool> Function()? permissionRequest,
  }) : _audioQuery = audioQuery ?? OnAudioQuery(),
       _permissionStatusReader = permissionStatus,
       _permissionRequester = permissionRequest;

  static const MethodChannel _localMediaChannel = MethodChannel(
    'yazen/local_media',
  );

  final OnAudioQuery _audioQuery;
  final Future<bool> Function()? _permissionStatusReader;
  final Future<bool> Function()? _permissionRequester;
  bool? _permissionGranted;
  Future<bool>? _permissionRequest;

  bool? get permissionGranted => _permissionGranted;

  Future<bool> ensurePermission({bool requestIfDenied = true}) {
    if (_permissionGranted == true) return Future<bool>.value(true);
    return _runPermissionOperation(() async {
      final granted = await _readPermissionStatus();
      if (granted || !requestIfDenied) return granted;
      return _requestPermissionDirect();
    });
  }

  /// Re-checks the current grant without opening a permission prompt.
  /// Denials are not cached, so grants made in system Settings are observable.
  Future<bool> recheckPermission() =>
      _runPermissionOperation(_readPermissionStatus);

  /// Requests permission only when the caller explicitly asks the user.
  Future<bool> requestPermission() {
    if (_permissionGranted == true) return Future<bool>.value(true);
    return _runPermissionOperation(() async {
      if (await _readPermissionStatus()) return true;
      return _requestPermissionDirect();
    });
  }

  Future<bool> _runPermissionOperation(Future<bool> Function() operation) {
    final activeRequest = _permissionRequest;
    if (activeRequest != null) return activeRequest;
    final request = Future<bool>.sync(operation);
    _permissionRequest = request;
    return request.whenComplete(() {
      if (identical(_permissionRequest, request)) _permissionRequest = null;
    });
  }

  Future<bool> _readPermissionStatus() async {
    try {
      final granted =
          await (_permissionStatusReader?.call() ??
              _audioQuery.permissionsStatus());
      _permissionGranted = granted ? true : null;
      return granted;
    } catch (_) {
      _permissionGranted = null;
      return false;
    }
  }

  Future<bool> _requestPermissionDirect() async {
    try {
      final granted =
          await (_permissionRequester?.call() ??
              _audioQuery.permissionsRequest());
      _permissionGranted = granted ? true : null;
      return granted;
    } catch (_) {
      _permissionGranted = null;
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _localMediaChannel.invokeMethod<bool>('openAppSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
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
    final target = normalizeFolderIdentity(folder);
    if (target.isEmpty) return const <MediaTrack>[];
    final songs = await querySongs();
    return songs
        .where((track) {
          final path = track.folder;
          return path != null && normalizeFolderIdentity(path) == target;
        })
        .toList(growable: false);
  }

  List<MediaTrack> _toMediaTracks(Iterable<SongModel> songs) =>
      List<MediaTrack>.unmodifiable(songs.map(MediaTrack.fromSong));

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
    return folderIdentities(songs);
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

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../models/media_track.dart';
import '../services/artwork_content_cropper.dart';

class YazenMediaArtwork extends StatefulWidget {
  const YazenMediaArtwork({
    this.track,
    required this.size,
    this.imageUri,
    this.placeholder,
    this.borderRadius,
    this.circular = false,
    super.key,
  });

  final MediaTrack? track;
  final double size;
  final Uri? imageUri;
  final Widget? placeholder;
  final BorderRadius? borderRadius;
  final bool circular;

  @override
  State<YazenMediaArtwork> createState() => _YazenMediaArtworkState();
}

class _YazenMediaArtworkState extends State<YazenMediaArtwork> {
  static const MethodChannel _localMediaChannel = MethodChannel(
    'yazen/local_media',
  );
  static const int _maxArtworkPixels = 2048;
  static const int _minArtworkPixels = 256;
  static const int _maxCacheBytes = 32 * 1024 * 1024;
  static const int _maxConcurrentLoads = 3;
  static final LinkedHashMap<String, _CachedArtwork> _memoryCache =
      LinkedHashMap<String, _CachedArtwork>();
  static final Map<String, Future<_CachedArtwork?>> _pendingLoads =
      <String, Future<_CachedArtwork?>>{};
  static final Queue<Completer<void>> _loadWaiters = Queue<Completer<void>>();
  static int _memoryCacheBytes = 0;
  static int _activeLoads = 0;

  final _audioQuery = OnAudioQuery();
  Future<_CachedArtwork?>? _future = Future<_CachedArtwork?>.value();
  Uint8List? _lastBytes;
  int _lastWidth = 0;
  int _lastHeight = 0;
  String? _cacheKey;
  String? _artworkSourceKey;
  int _requestedPixels = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startLoad(_pixelSize(context));
  }

  @override
  void didUpdateWidget(covariant YazenMediaArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startLoad(_pixelSize(context));
  }

  int _pixelSize(BuildContext context) =>
      (widget.size * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(_minArtworkPixels, _maxArtworkPixels)
          .toInt();

  String? _sourceKeyFor(MediaTrack? track, Uri? imageUri) {
    if (track != null) {
      if (track.isLocal) return 'local-track:${track.id}';
      final artworkUri = track.artworkUri;
      return artworkUri == null
          ? '${track.source.name}:${track.id}'
          : '${track.source.name}:$artworkUri';
    }
    return imageUri == null ? null : 'remote:$imageUri';
  }

  String? _keyFor(MediaTrack? track, Uri? imageUri, int pixels) {
    final base = _sourceKeyFor(track, imageUri);
    if (base == null) return null;
    // Local artwork is downsampled by Android's loadThumbnail. Keep separate
    // cache entries so a tiny list image never becomes the full-player cover.
    return track?.isLocal == true ? '$base:$pixels' : base;
  }

  _CachedArtwork? _readCache(String key) {
    final bytes = _memoryCache.remove(key);
    if (bytes != null) _memoryCache[key] = bytes;
    return bytes;
  }

  void _writeCache(String key, _CachedArtwork artwork) {
    final previous = _memoryCache.remove(key);
    if (previous != null) _memoryCacheBytes -= previous.bytes.length;
    if (artwork.bytes.length > _maxCacheBytes) return;
    _memoryCache[key] = artwork;
    _memoryCacheBytes += artwork.bytes.length;
    while (_memoryCacheBytes > _maxCacheBytes) {
      final oldestKey = _memoryCache.keys.first;
      final oldest = _memoryCache.remove(oldestKey);
      if (oldest != null) _memoryCacheBytes -= oldest.bytes.length;
    }
  }

  void _startLoad(int pixels) {
    final key = _keyFor(widget.track, widget.imageUri, pixels);
    if (key == _cacheKey && pixels == _requestedPixels) return;
    final sourceKey = _sourceKeyFor(widget.track, widget.imageUri);
    if (sourceKey != _artworkSourceKey) {
      _lastBytes = null;
      _lastWidth = 0;
      _lastHeight = 0;
    }
    _artworkSourceKey = sourceKey;
    _cacheKey = key;
    _requestedPixels = pixels;
    final cached = key == null ? null : _readCache(key);
    // Keep the previous frame visible until replacement art is ready; cached
    // low-resolution art is still replaced by its high-resolution variant.
    if (cached != null && cached.bytes.isNotEmpty) {
      _lastBytes = cached.bytes;
      _lastWidth = cached.width;
      _lastHeight = cached.height;
    }
    _future =
        cached == null
            ? _load(widget.track, widget.imageUri, key, pixels)
            : Future<_CachedArtwork?>.value(cached);
  }

  Future<_CachedArtwork?> _load(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
  ) async {
    if (track == null && imageUri == null) return null;
    if (key != null) {
      final cached = _readCache(key);
      if (cached != null) return cached;
      final pending = _pendingLoads[key];
      if (pending != null) return pending;
      final load = _loadUncached(track, imageUri, key, pixels);
      _pendingLoads[key] = load;
      try {
        return await load;
      } finally {
        if (identical(_pendingLoads[key], load)) _pendingLoads.remove(key);
      }
    }
    return _loadUncached(track, imageUri, key, pixels);
  }

  Future<_CachedArtwork?> _loadUncached(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
  ) async {
    if (_activeLoads >= _maxConcurrentLoads) {
      final waiter = Completer<void>();
      _loadWaiters.addLast(waiter);
      await waiter.future;
    } else {
      _activeLoads++;
    }
    try {
      return await _loadArtwork(track, imageUri, key, pixels);
    } finally {
      if (_loadWaiters.isEmpty) {
        _activeLoads--;
      } else {
        _loadWaiters.removeFirst().complete();
      }
    }
  }

  Future<_CachedArtwork?> _loadArtwork(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
  ) async {
    Uint8List? bytes;
    final localTrack = track;
    if (localTrack != null && localTrack.isLocal) {
      final id = int.tryParse(localTrack.id);
      if (id != null) {
        bytes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: pixels,
          quality: 100,
        );
      }
      if (bytes == null && !localTrack.isVideo) {
        bytes = await _readOriginalArtwork(localTrack.uri);
      }
    } else {
      final uri = track?.artworkUri ?? imageUri;
      if (uri != null) {
        try {
          final response = await http.get(uri);
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            bytes = response.bodyBytes;
          }
        } catch (error, stackTrace) {
          developer.log(
            'Remote artwork request failed',
            name: 'yazen.artwork',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    if (bytes == null || bytes.isEmpty) return null;

    final sourceKey = _sourceKeyFor(track, imageUri);
    if (sourceKey == null) return null;
    ProcessedArtwork processed;
    try {
      processed = await ArtworkContentCropper.process(
        bytes,
        cacheKey: sourceKey,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Unable to inspect artwork content; using original image: '
        '$error\n$stackTrace',
      );
      final size = await _imageSize(bytes);
      processed = ProcessedArtwork(
        bytes: bytes,
        width: size.$1,
        height: size.$2,
      );
    }
    final artwork = _CachedArtwork(
      processed.bytes,
      processed.width,
      processed.height,
    );
    if (key != null) _writeCache(key, artwork);
    return artwork;
  }

  Future<(int, int)> _imageSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        return (descriptor.width, descriptor.height);
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  Future<Uint8List?> _readOriginalArtwork(Uri? sourceUri) async {
    if (sourceUri == null) return null;
    try {
      final bytes = await _localMediaChannel.invokeMethod<Uint8List>(
        'readOriginalArtwork',
        <String, Object?>{'uri': sourceUri.toString()},
      );
      if (bytes != null && bytes.isNotEmpty && bytes.length <= _maxCacheBytes) {
        return bytes;
      }
    } on MissingPluginException {
      // Non-Android platforms use the fallback source below.
    } on PlatformException {
      // Missing file permission or embedded art falls back to MediaStore.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final radius =
        widget.circular
            ? BorderRadius.circular(widget.size / 2)
            : widget.borderRadius ?? BorderRadius.circular(widget.size * 0.18);
    return ClipRRect(
      borderRadius: radius,
      child: FutureBuilder<_CachedArtwork?>(
        key: ValueKey<String?>(_cacheKey),
        future: _future,
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          if (loaded != null && loaded.bytes.isNotEmpty) {
            _lastBytes = loaded.bytes;
            _lastWidth = loaded.width;
            _lastHeight = loaded.height;
          }
          final bytes = loaded?.bytes ?? _lastBytes;
          if (bytes != null && bytes.isNotEmpty) {
            final width = loaded?.width ?? _lastWidth;
            final height = loaded?.height ?? _lastHeight;
            final scale =
                widget.size *
                MediaQuery.devicePixelRatioOf(context) /
                math.max(width, height);
            return Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: math.max(1, (width * scale).round()),
              cacheHeight: math.max(1, (height * scale).round()),
            );
          }
          return widget.placeholder ??
              Container(
                width: widget.size,
                height: widget.size,
                color: tokens.surfaceElevated,
                alignment: Alignment.center,
                child: Icon(
                  Icons.music_note_rounded,
                  color: tokens.accent,
                  size: widget.size * 0.34,
                ),
              );
        },
      ),
    );
  }
}

class _CachedArtwork {
  const _CachedArtwork(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

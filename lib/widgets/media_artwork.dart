import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../models/media_track.dart';

class YazenMediaArtwork extends StatefulWidget {
  const YazenMediaArtwork({
    required this.track,
    required this.size,
    this.borderRadius,
    this.circular = false,
    super.key,
  });

  final MediaTrack? track;
  final double size;
  final BorderRadius? borderRadius;
  final bool circular;

  @override
  State<YazenMediaArtwork> createState() => _YazenMediaArtworkState();
}

class _YazenMediaArtworkState extends State<YazenMediaArtwork> {
  static const int _maxArtworkPixels = 2048;
  static const int _minArtworkPixels = 256;
  static const int _maxCacheBytes = 32 * 1024 * 1024;
  static final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();
  static int _memoryCacheBytes = 0;

  final _audioQuery = OnAudioQuery();
  Future<Uint8List?>? _future = Future<Uint8List?>.value();
  Uint8List? _lastBytes;
  String? _cacheKey;
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

  String? _keyFor(MediaTrack? track, int pixels) {
    if (track == null) return null;
    final base = '${track.source.name}:${track.id}:${track.artworkUri}';
    // Local artwork is downsampled by Android's loadThumbnail. Keep separate
    // cache entries so a tiny list image never becomes the full-player cover.
    return track.isLocal ? '$base:$pixels' : base;
  }

  Uint8List? _readCache(String key) {
    final bytes = _memoryCache.remove(key);
    if (bytes != null) _memoryCache[key] = bytes;
    return bytes;
  }

  void _writeCache(String key, Uint8List bytes) {
    final previous = _memoryCache.remove(key);
    if (previous != null) _memoryCacheBytes -= previous.length;
    if (bytes.length > _maxCacheBytes) return;
    _memoryCache[key] = bytes;
    _memoryCacheBytes += bytes.length;
    while (_memoryCacheBytes > _maxCacheBytes) {
      final oldestKey = _memoryCache.keys.first;
      final oldestBytes = _memoryCache.remove(oldestKey);
      if (oldestBytes != null) _memoryCacheBytes -= oldestBytes.length;
    }
  }

  void _startLoad(int pixels) {
    final key = _keyFor(widget.track, pixels);
    if (key == _cacheKey && pixels == _requestedPixels) return;
    _cacheKey = key;
    _requestedPixels = pixels;
    final cached = key == null ? null : _readCache(key);
    // Keep the previous frame visible until replacement art is ready; cached
    // low-resolution art is still replaced by its high-resolution variant.
    if (cached != null && cached.isNotEmpty) _lastBytes = cached;
    _future =
        cached == null
            ? _load(widget.track, key, pixels)
            : Future<Uint8List?>.value(cached);
  }

  Future<Uint8List?> _load(MediaTrack? track, String? key, int pixels) async {
    if (track == null) return null;
    if (key != null) {
      final cached = _readCache(key);
      if (cached != null) return cached;
    }

    Uint8List? bytes;
    if (track.isLocal) {
      final id = int.tryParse(track.id);
      if (id != null) {
        bytes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: pixels,
          quality: 100,
        );
      }
    } else {
      final uri = track.artworkUri;
      if (uri != null) {
        try {
          final response = await http.get(uri);
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            bytes = response.bodyBytes;
          }
        } catch (_) {}
      }
    }
    if (bytes != null && bytes.isNotEmpty && key != null) {
      _writeCache(key, bytes);
    }
    return bytes;
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
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          if (loaded != null && loaded.isNotEmpty) _lastBytes = loaded;
          final bytes = loaded ?? _lastBytes;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: _requestedPixels,
              cacheHeight: _requestedPixels,
            );
          }
          return Container(
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

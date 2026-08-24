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
  static final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  final _audioQuery = OnAudioQuery();
  Future<Uint8List?>? _future;
  Uint8List? _lastBytes;
  String? _cacheKey;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant YazenMediaArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _keyFor(widget.track);
    if (nextKey != _cacheKey) _startLoad();
  }

  String? _keyFor(MediaTrack? track) {
    if (track == null) return null;
    return '${track.source.name}:${track.id}:${track.artworkUri}';
  }

  void _startLoad() {
    _cacheKey = _keyFor(widget.track);
    final cached = _cacheKey == null ? null : _memoryCache[_cacheKey!];
    _lastBytes = cached;
    _future = _load(widget.track, _cacheKey);
  }

  Future<Uint8List?> _load(MediaTrack? track, String? key) async {
    if (track == null) return null;
    if (key != null && _memoryCache.containsKey(key)) return _memoryCache[key];

    Uint8List? bytes;
    if (track.isLocal) {
      final id = int.tryParse(track.id);
      if (id != null) {
        bytes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: widget.size.round().clamp(120, 1200),
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
      _memoryCache[key] = bytes;
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

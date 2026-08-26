import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../models/media_track.dart';

class VideoThumbnailWidget extends StatefulWidget {
  const VideoThumbnailWidget({
    required this.track,
    required this.size,
    super.key,
  });

  final MediaTrack track;
  final double size;

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  static const MethodChannel _channel = MethodChannel('yazen/local_media');
  Future<Uint8List?>? _future;
  Uint8List? _lastThumbnail;

  @override
  void initState() {
    super.initState();
    _future = _load(widget.track);
  }

  @override
  void didUpdateWidget(covariant VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.uri != widget.track.uri) {
      _future = _load(widget.track);
    }
  }

  Future<Uint8List?> _load(MediaTrack track) async {
    final uri = track.uri;
    if (uri == null) return null;
    if (uri.scheme == 'content') {
      try {
        return await _channel.invokeMethod<Uint8List>(
          'videoThumbnail',
          <String, Object?>{
            'uri': uri.toString(),
            'width': (widget.size * 3).round().clamp(240, 1200),
          },
        );
      } on PlatformException {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded != null && loaded.isNotEmpty) _lastThumbnail = loaded;
        final visible = loaded ?? _lastThumbnail;
        if (visible != null && visible.isNotEmpty) {
          return Image.memory(
            visible,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[tokens.surfaceElevated, tokens.accentStrong],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.movie_creation_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: widget.size * 0.3,
          ),
        );
      },
    );
  }
}

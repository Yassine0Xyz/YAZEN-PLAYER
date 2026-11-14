import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/media_track.dart';
import 'yazen_video_player.dart';

@visibleForTesting
int? videoQueueNeighborIndex(int currentIndex, int length, int delta) {
  if (length <= 0 ||
      currentIndex < 0 ||
      currentIndex >= length ||
      (delta != -1 && delta != 1)) {
    return null;
  }
  final next = currentIndex + delta;
  return next >= 0 && next < length ? next : null;
}

class YazenVideoPlayerScreen extends StatefulWidget {
  const YazenVideoPlayerScreen({
    required this.track,
    this.streamUri,
    this.videoTracks = const <MediaTrack>[],
    this.initialIndex = 0,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final MediaTrack track;
  final Uri? streamUri;
  final List<MediaTrack> videoTracks;
  final int initialIndex;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;

  static Route<void> route(
    MediaTrack track, {
    Uri? streamUri,
    List<MediaTrack> videoTracks = const <MediaTrack>[],
    int initialIndex = 0,
    Future<void> Function()? onPrevious,
    Future<void> Function()? onNext,
  }) {
    return MaterialPageRoute<void>(
      builder:
          (_) => YazenVideoPlayerScreen(
            track: track,
            streamUri: streamUri,
            videoTracks: videoTracks,
            initialIndex: initialIndex,
            onPrevious: onPrevious,
            onNext: onNext,
          ),
    );
  }

  @override
  State<YazenVideoPlayerScreen> createState() => _YazenVideoPlayerScreenState();
}

class _YazenVideoPlayerScreenState extends State<YazenVideoPlayerScreen> {
  late List<MediaTrack> _videoTracks;
  late int _currentIndex;
  VideoPlayerController? _controller;
  Future<void>? _initialization;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _videoTracks =
        widget.videoTracks.isEmpty
            ? <MediaTrack>[widget.track]
            : List<MediaTrack>.unmodifiable(widget.videoTracks);
    _currentIndex = widget.initialIndex.clamp(0, _videoTracks.length - 1);
    _initializeVideo(
      _videoTracks[_currentIndex],
      uriOverride: widget.streamUri,
    );
  }

  VideoPlayerController? _createController(Uri? uri) {
    if (uri == null) {
      _error = StateError('This video is missing its media URI.');
      return null;
    }
    return uri.scheme == 'content'
        ? VideoPlayerController.contentUri(uri)
        : uri.scheme == 'file'
        ? VideoPlayerController.file(File(uri.toFilePath()))
        : VideoPlayerController.networkUrl(uri);
  }

  void _initializeVideo(MediaTrack track, {Uri? uriOverride}) {
    final generation = ++_loadGeneration;
    final uri = uriOverride ?? track.uri;
    final nextController = _createController(uri);
    if (nextController == null) {
      if (mounted) setState(() {});
      return;
    }
    final previousController = _controller;
    _error = null;
    _controller = nextController;
    _initialization = nextController
        .initialize()
        .then((_) async {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {});
          await nextController.play();
        })
        .catchError((Object error) {
          if (generation != _loadGeneration) return;
          _error = error;
          if (mounted) setState(() {});
        });
    if (previousController != null) {
      unawaited(previousController.dispose());
    }
  }

  Future<void> _selectRelativeVideo(int delta) async {
    final nextIndex = videoQueueNeighborIndex(
      _currentIndex,
      _videoTracks.length,
      delta,
    );
    if (nextIndex == null) return;
    setState(() {
      _currentIndex = nextIndex;
      _error = null;
    });
    _initializeVideo(_videoTracks[nextIndex]);
  }

  Future<void> _skipPrevious() => _selectRelativeVideo(-1);

  Future<void> _skipNext() => _selectRelativeVideo(1);

  void _close() {
    final controller = _controller;
    if (controller != null) unawaited(controller.pause());
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child:
            error != null || controller == null || _initialization == null
                ? _ErrorState(error: error)
                : FutureBuilder<void>(
                  future: _initialization,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done ||
                        !controller.value.isInitialized) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    return YazenVideoPlayer(
                      controller: controller,
                      title: _videoTracks[_currentIndex].title,
                      onPrevious:
                          _currentIndex > 0 ? _skipPrevious : widget.onPrevious,
                      onNext:
                          _currentIndex < _videoTracks.length - 1
                              ? _skipNext
                              : widget.onNext,
                      onClose: _close,
                    );
                  },
                ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              error == null
                  ? 'This video is missing its media URI.'
                  : 'Could not open this video.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

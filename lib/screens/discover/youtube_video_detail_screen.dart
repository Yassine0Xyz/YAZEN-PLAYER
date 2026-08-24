import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/youtube_service.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../player/yazen_video_player.dart';

class YoutubeVideoDetailScreen extends StatefulWidget {
  const YoutubeVideoDetailScreen({required this.initialVideo, super.key});

  final YoutubeVideoResult initialVideo;

  static Route<void> route(YoutubeVideoResult video) {
    return MaterialPageRoute<void>(
      builder: (_) => YoutubeVideoDetailScreen(initialVideo: video),
    );
  }

  @override
  State<YoutubeVideoDetailScreen> createState() =>
      _YoutubeVideoDetailScreenState();
}

class _YoutubeVideoDetailScreenState extends State<YoutubeVideoDetailScreen> {
  late YoutubeVideoResult _current;
  late MediaTrack _track;
  Future<YoutubeVideoResult>? _detailsFuture;
  Future<Uri>? _streamFuture;
  Future<YoutubeSearchPage>? _relatedFuture;
  YoutubeSearchPage? _relatedPage;
  final List<YoutubeVideoResult> _relatedItems = <YoutubeVideoResult>[];
  bool _relatedHasMore = true;
  bool _descriptionExpanded = false;
  bool _loadingRelated = false;
  bool _loadingMore = false;
  bool _stickyPlayer = false;
  VideoPlayerController? _activeVideoController;
  final List<YoutubeVideoResult> _videoHistory = <YoutubeVideoResult>[];
  int _historyIndex = -1;
  int _relatedGeneration = 0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _setCurrent(widget.initialVideo, notify: false);
    _videoHistory
      ..clear()
      ..add(widget.initialVideo);
    _historyIndex = 0;
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldStick =
        _scrollController.hasClients && _scrollController.offset > 210;
    if (shouldStick != _stickyPlayer && mounted) {
      setState(() => _stickyPlayer = shouldStick);
    }
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent - _scrollController.offset <
            600) {
      _loadMoreRelated();
    }
  }

  void _setCurrent(YoutubeVideoResult video, {bool notify = true}) {
    _current = video;
    _track = video.toMediaTrack();
    final service = context.read<HybridMusicController>().youtubeService;
    final generation = ++_relatedGeneration;
    _activeVideoController = null;
    _detailsFuture = service.getVideo(video.videoId);
    _streamFuture = service.getVideoStreamUrl(video.videoId);
    _relatedPage = null;
    _relatedItems.clear();
    _relatedHasMore = true;
    _relatedFuture = _loadRelated(video, generation);
    _descriptionExpanded = false;
    if (notify && mounted) setState(() {});
  }

  Future<YoutubeSearchPage> _loadRelated(
    YoutubeVideoResult video,
    int generation,
  ) async {
    final service = context.read<HybridMusicController>().youtubeService;
    final page = await service.searchVideosPage(
      '${video.title} ${video.author}',
      limit: 42,
    );
    if (!mounted || generation != _relatedGeneration) return page;
    _relatedPage = page;
    _relatedItems
      ..clear()
      ..addAll(page.results.where((item) => item.videoId != _current.videoId));
    return page;
  }

  void _openVideo(YoutubeVideoResult video) {
    if (video.videoId == _current.videoId) return;
    if (_historyIndex < _videoHistory.length - 1) {
      _videoHistory.removeRange(_historyIndex + 1, _videoHistory.length);
    }
    _videoHistory.add(video);
    _historyIndex = _videoHistory.length - 1;
    _setCurrent(video);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _playPreviousVideo() async {
    if (_historyIndex <= 0) {
      _showNavigationHint('No previous video');
      return;
    }
    _historyIndex -= 1;
    _setCurrent(_videoHistory[_historyIndex]);
    await _scrollToTop();
  }

  Future<void> _playNextVideo() async {
    if (_historyIndex + 1 < _videoHistory.length) {
      _historyIndex += 1;
      _setCurrent(_videoHistory[_historyIndex]);
      await _scrollToTop();
      return;
    }

    final currentIndex = _relatedItems.indexWhere(
      (item) => item.videoId == _current.videoId,
    );
    final nextIndex = currentIndex < 0 ? 0 : currentIndex + 1;
    if (nextIndex >= _relatedItems.length && _relatedHasMore) {
      await _loadMoreRelated();
    }
    if (!mounted) return;
    final refreshedIndex = _relatedItems.indexWhere(
      (item) => item.videoId == _current.videoId,
    );
    final targetIndex = refreshedIndex < 0 ? nextIndex : refreshedIndex + 1;
    if (targetIndex < _relatedItems.length) {
      _openVideo(_relatedItems[targetIndex]);
    } else {
      _showNavigationHint('No next video loaded yet');
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _showNavigationHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retryRelated() async {
    final generation = ++_relatedGeneration;
    setState(() {
      _loadingRelated = true;
      _relatedPage = null;
      _relatedItems.clear();
      _relatedHasMore = true;
      _relatedFuture = _loadRelated(_current, generation);
    });
    try {
      await _relatedFuture;
      if (mounted && generation == _relatedGeneration) {
        setState(() => _loadingRelated = false);
      }
    } catch (_) {
      if (mounted && generation == _relatedGeneration) {
        setState(() => _loadingRelated = false);
      }
    }
  }

  Future<void> _loadMoreRelated() async {
    if (_loadingMore || !_relatedHasMore || _relatedPage == null) return;
    final generation = _relatedGeneration;
    setState(() => _loadingMore = true);
    try {
      final next = await _relatedPage!.nextPage();
      if (!mounted || generation != _relatedGeneration) return;
      if (next == null) {
        setState(() {
          _relatedHasMore = false;
          _loadingMore = false;
        });
        return;
      }
      final known =
          _relatedItems.map((item) => item.videoId).toSet()
            ..add(_current.videoId);
      final additions = next.results.where((item) => known.add(item.videoId));
      setState(() {
        _relatedPage = next;
        _relatedItems.addAll(additions);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      ClipboardData(
        text: 'https://www.youtube.com/watch?v=${_current.videoId}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('YouTube link copied')));
  }

  Future<void> _downloadAudio() async {
    final controller = context.read<HybridMusicController>();
    try {
      await controller.cacheYouTubeTrack(_track);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio saved for offline listening')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not cache this audio right now')),
      );
    }
  }

  String _views(int? count) {
    if (count == null) return 'Views unavailable';
    if (count >= 1000000)
      return '${(count / 1000000).toStringAsFixed(1)}M views';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K views';
    return '$count views';
  }

  String _date(DateTime? date) {
    if (date == null) return 'Upload date unavailable';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    final controller = context.read<HybridMusicController>();
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        title: const Text(
          'Video detail',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _copyLink,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
            children: <Widget>[
              _OnlinePlayerHeader(
                streamFuture: _streamFuture!,
                title: _current.title,
                thumbnail: _current.thumbnailUrl,
                showVideo: !_stickyPlayer,
                onPrevious: _playPreviousVideo,
                onNext: _playNextVideo,
                onControllerReady: (videoController) {
                  if (mounted) {
                    setState(() => _activeVideoController = videoController);
                  }
                },
                onRetry:
                    () => setState(() {
                      _activeVideoController = null;
                      _streamFuture = controller.youtubeService
                          .getVideoStreamUrl(_current.videoId);
                    }),
              ),
              const SizedBox(height: 18),
              FutureBuilder<YoutubeVideoResult>(
                future: _detailsFuture,
                builder: (context, snapshot) {
                  final detail = snapshot.data ?? _current;
                  return _InfoSection(
                    video: detail,
                    expanded: _descriptionExpanded,
                    onToggleDescription:
                        () => setState(
                          () => _descriptionExpanded = !_descriptionExpanded,
                        ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ActionBar(
                track: _track,
                favorite: controller.isFavorite(_track),
                onFavorite: () => controller.toggleFavorite(_track),
                onPlaylist: () => showAddToPlaylistSheet(context, _track),
                onDownload: _downloadAudio,
                onShare: _copyLink,
              ),
              const SizedBox(height: 26),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Up next',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_loadingRelated)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      onPressed: _retryRelated,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
              FutureBuilder<YoutubeSearchPage>(
                future: _relatedFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _RelatedSkeleton();
                  }
                  if (snapshot.hasError) {
                    return _RetryBanner(onRetry: _retryRelated);
                  }
                  if (snapshot.hasData && _relatedPage == null) {
                    _relatedPage = snapshot.data;
                    _relatedItems.addAll(snapshot.data!.results);
                  }
                  final related = _relatedItems
                      .where((video) => video.videoId != _current.videoId)
                      .toList(growable: false);

                  if (related.isEmpty)
                    return const _RetryBanner(
                      message: 'No related videos found yet.',
                    );
                  return Column(
                    children: <Widget>[
                      ...related.map(
                        (video) => _RelatedTile(
                          video: video,
                          onTap: () => _setCurrent(video),
                        ),
                      ),
                      if (_loadingMore)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      if (_relatedHasMore && !_loadingMore)
                        Center(
                          child: TextButton.icon(
                            onPressed: _loadMoreRelated,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Show more'),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          if (_stickyPlayer && _activeVideoController != null)
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: SizedBox(
                height: 82,
                child: YazenVideoPlayer(
                  controller: _activeVideoController!,
                  title: _current.title,
                  compact: true,
                  onPrevious: _playPreviousVideo,
                  onNext: _playNextVideo,
                  onExpand: _scrollToTop,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OnlinePlayerHeader extends StatelessWidget {
  const _OnlinePlayerHeader({
    required this.streamFuture,
    required this.title,
    required this.thumbnail,
    required this.showVideo,
    required this.onPrevious,
    required this.onNext,
    required this.onControllerReady,
    required this.onRetry,
  });

  final Future<Uri> streamFuture;
  final String title;
  final Uri? thumbnail;
  final bool showVideo;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;
  final ValueChanged<VideoPlayerController?> onControllerReady;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uri>(
      future: streamFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _RetryBanner(
            message: 'Video stream unavailable. Audio can still play.',
            onRetry: onRetry,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _InlineOnlinePlayer(
              key: ValueKey(snapshot.data.toString()),
              streamUri: snapshot.data!,
              title: title,
              showVideo: showVideo,
              onPrevious: onPrevious,
              onNext: onNext,
              onControllerReady: onControllerReady,
            ),
          ),
        );
      },
    );
  }
}

class _InlineOnlinePlayer extends StatefulWidget {
  const _InlineOnlinePlayer({
    required this.streamUri,
    required this.title,
    required this.showVideo,
    required this.onPrevious,
    required this.onNext,
    required this.onControllerReady,
    super.key,
  });

  final Uri streamUri;
  final String title;
  final bool showVideo;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;
  final ValueChanged<VideoPlayerController?> onControllerReady;

  @override
  State<_InlineOnlinePlayer> createState() => _InlineOnlinePlayerState();
}

class _InlineOnlinePlayerState extends State<_InlineOnlinePlayer>
    with AutomaticKeepAliveClientMixin<_InlineOnlinePlayer> {
  late final VideoPlayerController _controller;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(widget.streamUri);
    widget.onControllerReady(_controller);
    _initialization = _controller.initialize().then((_) => _controller.play());
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    widget.onControllerReady(null);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Video could not be opened',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!widget.showVideo) {
          return const ColoredBox(color: Colors.black);
        }
        return YazenVideoPlayer(
          controller: _controller,
          title: widget.title,
          onPrevious: widget.onPrevious,
          onNext: widget.onNext,
        );
      },
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.video,
    required this.expanded,
    required this.onToggleDescription,
  });

  final YoutubeVideoResult video;
  final bool expanded;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final description = video.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          video.title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_views(video.viewCount)}  •  ${_date(video.uploadDate)}',
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 22,
              backgroundColor: tokens.accent.withValues(alpha: 0.25),
              child: Text(
                video.author.isEmpty
                    ? '?'
                    : video.author.characters.first.toUpperCase(),
                style: TextStyle(
                  color: tokens.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                video.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          AnimatedCrossFade(
            firstChild: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, height: 1.35),
            ),
            secondChild: Text(
              description,
              style: TextStyle(color: tokens.textSecondary, height: 1.35),
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
          TextButton(
            onPressed: onToggleDescription,
            child: Text(expanded ? 'Show less' : 'Show more'),
          ),
        ],
      ],
    );
  }

  String _views(int? count) {
    if (count == null) return 'Views unavailable';
    if (count >= 1000000)
      return '${(count / 1000000).toStringAsFixed(1)}M views';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K views';
    return '$count views';
  }

  String _date(DateTime? date) =>
      date == null
          ? 'Upload date unavailable'
          : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.track,
    required this.favorite,
    required this.onFavorite,
    required this.onPlaylist,
    required this.onDownload,
    required this.onShare,
  });

  final MediaTrack track;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlaylist;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _Action(
          icon:
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: 'Favorite',
          color: favorite ? Colors.redAccent : null,
          onTap: onFavorite,
        ),
        _Action(
          icon: Icons.playlist_add_rounded,
          label: 'Playlist',
          onTap: onPlaylist,
        ),
        _Action(
          icon: Icons.download_for_offline_rounded,
          label: 'Cache audio',
          onTap: onDownload,
        ),
        _Action(icon: Icons.link_rounded, label: 'Copy link', onTap: onShare),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 17, color: color),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _RelatedTile extends StatelessWidget {
  const _RelatedTile({required this.video, required this.onTap});

  final YoutubeVideoResult video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return EchoPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 150,
                height: 86,
                child:
                    video.thumbnailUrl == null
                        ? ColoredBox(
                          color: tokens.surfaceElevated,
                          child: const Icon(Icons.movie_rounded),
                        )
                        : Image.network(
                          video.thumbnailUrl.toString(),
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => ColoredBox(
                                color: tokens.surfaceElevated,
                                child: const Icon(Icons.movie_rounded),
                              ),
                        ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    video.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    video.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    video.duration == null
                        ? 'LIVE'
                        : '${video.duration!.inMinutes}:${video.duration!.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelatedSkeleton extends StatelessWidget {
  const _RelatedSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Column(
      children: List<Widget>.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Row(
            children: <Widget>[
              Container(
                width: 150,
                height: 86,
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Container(height: 14, color: tokens.surfaceElevated),
                    const SizedBox(height: 8),
                    Container(height: 12, color: tokens.surfaceElevated),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryBanner extends StatelessWidget {
  const _RetryBanner({
    this.message = 'Could not load suggested videos.',
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

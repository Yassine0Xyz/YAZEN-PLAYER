import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/youtube_service.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/shimmer_skeleton.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../player/yazen_video_player_screen.dart';
import 'youtube_video_detail_screen.dart';

class YoutubeSearchScreen extends StatefulWidget {
  const YoutubeSearchScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, animation, __) => const YoutubeSearchScreen(),
      transitionsBuilder:
          (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
      transitionDuration: const Duration(milliseconds: 280),
    );
  }

  @override
  State<YoutubeSearchScreen> createState() => _YoutubeSearchScreenState();
}

class _YoutubeSearchScreenState extends State<YoutubeSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _downloadProgress = <String, double>{};
  final _cachedIds = <String>{};
  final _queuedIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text(
          'Discover',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Close discover',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _SearchHeader(
                  controller: controller,
                  searchController: _searchController,
                  focusNode: _focusNode,
                  onSearch: _search,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _TrendingChips(onSelected: _search)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              sliver: SliverToBoxAdapter(
                child: _ResultHeader(controller: controller),
              ),
            ),
            if (controller.isSearching)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(child: _DiscoverLoadingState()),
              )
            else if (controller.youtubeResults.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _DiscoverEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.builder(
                  itemCount: controller.youtubeResults.length,
                  itemBuilder: (context, index) {
                    final track = controller.youtubeResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: EchoReveal(
                        delay: Duration(milliseconds: (index.clamp(0, 8) * 55)),
                        child: _YoutubeResultCard(
                          track: track,
                          cached: _cachedIds.contains(track.id),
                          progress: _downloadProgress[track.id],
                          queued: _queuedIds.contains(track.id),
                          favorite: controller.isFavorite(track),
                          onFavorite: () => controller.toggleFavorite(track),
                          onAddToPlaylist:
                              () => showAddToPlaylistSheet(context, track),
                          onDetails:
                              () => Navigator.of(context).push(
                                YoutubeVideoDetailScreen.route(
                                  controller.youtubeResults[index].youtubeId ==
                                          null
                                      ? YoutubeVideoResult(
                                        videoId: track.youtubeId ?? '',
                                        title: track.title,
                                        author: track.artist,
                                        duration: track.duration,
                                        thumbnailUrl: track.artworkUri,
                                      )
                                      : YoutubeVideoResult(
                                        videoId: track.youtubeId!,
                                        title: track.title,
                                        author: track.artist,
                                        duration: track.duration,
                                        thumbnailUrl: track.artworkUri,
                                        viewCount: track.viewCount,
                                      ),
                                ),
                              ),
                          onStream: () => _playSearchQueue(index),
                          onQueue: () => _queueTrack(track),
                          onCancelCache: () => _cancelCache(track),
                          onCache: () => _cacheTrack(track),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _focusNode.unfocus();
    await context.read<HybridMusicController>().searchYouTube(normalized);
  }

  Future<void> _playSearchQueue(int index) async {
    final controller = context.read<HybridMusicController>();
    await controller.playTrackQueue(
      controller.youtubeResults,
      initialIndex: index,
    );
    if (!mounted) return;
    final error = controller.errorMessage;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _queueTrack(MediaTrack track) async {
    try {
      await context.read<HybridMusicController>().addToQueue(track);
      if (!mounted) return;
      setState(() => _queuedIds.add(track.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${track.title} added to queue')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not queue ${track.title}: $error')),
      );
    }
  }

  Future<void> _cancelCache(MediaTrack track) async {
    final youtubeId = track.youtubeId;
    if (youtubeId == null || youtubeId.isEmpty) return;
    await context.read<HybridMusicController>().cancelYouTubeDownload(
      youtubeId,
    );
    if (!mounted) return;
    setState(() => _downloadProgress.remove(track.id));
  }

  Future<void> _cacheTrack(MediaTrack track) async {
    if (_downloadProgress.containsKey(track.id) ||
        _cachedIds.contains(track.id))
      return;
    setState(() => _downloadProgress[track.id] = 0);
    try {
      await context.read<HybridMusicController>().cacheYouTubeTrack(
        track,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress[track.id] = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(track.id);
        _cachedIds.add(track.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${track.title} is available offline')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(track.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cache ${track.title}: $error')),
      );
    }
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.searchController,
    required this.focusNode,
    required this.onSearch,
  });

  final HybridMusicController controller;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Find your next favorite',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Stream instantly or keep it close for offline listening.',
          style: TextStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: searchController,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: onSearch,
          style: TextStyle(color: tokens.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            hintText: 'Search YouTube',

            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon:
                controller.isSearching
                    ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                    : IconButton(
                      onPressed: () => onSearch(searchController.text),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendingChips extends StatelessWidget {
  const _TrendingChips({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _queries = <String>[
    'Chill electronic mix',
    'Lo-fi beats',
    'Deep focus music',
    'Acoustic covers',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _queries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder:
            (_, index) => ActionChip(
              onPressed: () => onSelected(_queries[index]),
              avatar: Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: tokens.accent,
              ),
              label: Text(_queries[index]),
              backgroundColor: tokens.surface,
              side: BorderSide(color: tokens.divider),
              labelStyle: TextStyle(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.controller});

  final HybridMusicController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.youtubeResults.length;
    return Row(
      children: <Widget>[
        Text(
          count == 0 ? 'Trending for you' : 'Search results',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 8),
        if (count > 0)
          Text(
            '$count',
            style: TextStyle(
              color: context.read<ThemeProvider>().tokens.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _YoutubeResultCard extends StatelessWidget {
  const _YoutubeResultCard({
    required this.track,
    required this.cached,
    required this.progress,
    required this.queued,
    required this.favorite,
    required this.onFavorite,
    required this.onAddToPlaylist,
    required this.onDetails,
    required this.onStream,
    required this.onQueue,
    required this.onCancelCache,
    required this.onCache,
  });

  final MediaTrack track;
  final bool cached;
  final double? progress;
  final bool queued;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDetails;
  final VoidCallback onStream;
  final VoidCallback onQueue;
  final VoidCallback onCancelCache;
  final VoidCallback onCache;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Hero(
            tag: 'track-art-${track.id}',
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _Thumbnail(uri: track.artworkUri),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _DurationBadge(duration: track.duration),
                  ),
                  Positioned(left: 12, bottom: 12, child: _YouTubeBadge()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Open video details',
                      onPressed: onDetails,
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip:
                          favorite
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                      onPressed: onFavorite,
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color:
                            favorite ? Colors.redAccent : tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.account_circle_outlined,
                      size: 17,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        track.channelName ?? track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (track.viewCount != null)
                      Text(
                        _formatViews(track.viewCount!),
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _chooseStream(context),
                        icon: const Icon(
                          Icons.play_circle_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Stream'),
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accentStrong,
                          foregroundColor:
                              tokens.isLight ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    if (MediaQuery.sizeOf(context).width < 500)
                      _ResultMoreMenu(
                        queued: queued,
                        cached: cached,
                        progress: progress,
                        onAddToPlaylist: onAddToPlaylist,
                        onQueue: onQueue,
                        onCancelCache: onCancelCache,
                        onCache: onCache,
                      )
                    else ...<Widget>[
                      IconButton.filledTonal(
                        tooltip: 'Add to playlist',
                        onPressed: onAddToPlaylist,
                        icon: const Icon(Icons.playlist_add_rounded, size: 19),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 9),
                      IconButton.filledTonal(
                        tooltip: queued ? 'Already queued' : 'Add to queue',
                        onPressed: queued ? null : onQueue,
                        icon: Icon(
                          queued
                              ? Icons.playlist_add_check_rounded
                              : Icons.playlist_add_rounded,
                          size: 19,
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor:
                              queued ? Colors.greenAccent : tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              progress != null
                                  ? onCancelCache
                                  : cached
                                  ? null
                                  : onCache,
                          icon:
                              progress != null
                                  ? SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      value: progress == 0 ? null : progress,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : Icon(
                                    cached
                                        ? Icons.check_rounded
                                        : Icons.download_for_offline_rounded,
                                    size: 18,
                                  ),
                          label: Text(
                            cached
                                ? 'Offline ready'
                                : progress != null
                                ? 'Cancel'
                                : 'Download',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                cached
                                    ? Colors.greenAccent
                                    : tokens.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseStream(BuildContext context) async {
    final mode = await showModalBottomSheet<_StreamMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DiscoverStreamSheet(track: track),
    );
    if (!context.mounted || mode == null) return;
    if (mode == _StreamMode.voice) {
      onStream();
      return;
    }
    final youtubeId = track.youtubeId;
    if (youtubeId == null || youtubeId.isEmpty) return;
    try {
      final controller = context.read<HybridMusicController>();
      final streamUri = await controller.youtubeService.getVideoStreamUrl(
        youtubeId,
      );
      if (!context.mounted) return;
      await Navigator.of(
        context,
      ).push(YazenVideoPlayerScreen.route(track, streamUri: streamUri));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video stream is unavailable right now. Try Voice only.',
          ),
        ),
      );
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000)
      return '${(views / 1000000).toStringAsFixed(1)}M views';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K views';
    return '$views views';
  }
}

enum _StreamMode { voice, video }

class _DiscoverStreamSheet extends StatelessWidget {
  const _DiscoverStreamSheet({required this.track});

  final MediaTrack track;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: tokens.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Choose stream mode',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              tileColor: tokens.surface,
              leading: Icon(Icons.headphones_rounded, color: tokens.accent),
              title: const Text(
                'Voice only',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Play audio in the background'),
              onTap: () => Navigator.pop(context, _StreamMode.voice),
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              tileColor: tokens.surface,
              leading: Icon(
                Icons.ondemand_video_rounded,
                color: tokens.accentStrong,
              ),
              title: const Text(
                'Video',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Open in the YAZEN video player'),
              onTap: () => Navigator.pop(context, _StreamMode.video),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MoreAction { playlist, queue, cache }

class _ResultMoreMenu extends StatelessWidget {
  const _ResultMoreMenu({
    required this.queued,
    required this.cached,
    required this.progress,
    required this.onAddToPlaylist,
    required this.onQueue,
    required this.onCancelCache,
    required this.onCache,
  });

  final bool queued;
  final bool cached;
  final double? progress;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onQueue;
  final VoidCallback onCancelCache;
  final VoidCallback onCache;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return PopupMenuButton<_MoreAction>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_horiz_rounded, color: tokens.textPrimary),
      color: tokens.surfaceElevated,
      onSelected: (action) {
        switch (action) {
          case _MoreAction.playlist:
            onAddToPlaylist();
          case _MoreAction.queue:
            if (!queued) onQueue();
          case _MoreAction.cache:
            if (progress != null) {
              onCancelCache();
            } else if (!cached) {
              onCache();
            }
        }
      },
      itemBuilder:
          (context) => <PopupMenuEntry<_MoreAction>>[
            const PopupMenuItem(
              value: _MoreAction.playlist,
              child: Text('Add to playlist'),
            ),
            PopupMenuItem(
              value: _MoreAction.queue,
              enabled: !queued,
              child: Text(queued ? 'Already in queue' : 'Add to queue'),
            ),
            PopupMenuItem(
              value: _MoreAction.cache,
              enabled: progress != null || !cached,
              child: Text(
                progress != null
                    ? 'Cancel download'
                    : cached
                    ? 'Offline ready'
                    : 'Download offline',
              ),
            ),
          ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    if (uri == null) return const _ThumbnailFallback();
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      cacheWidth: 720,
      cacheHeight: 405,
      errorBuilder: (_, __, ___) => const _ThumbnailFallback(),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[tokens.surfaceMuted, tokens.accentStrong],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.ondemand_video_rounded,
          color: tokens.accent,
          size: 42,
        ),
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final value =
        duration == null
            ? 'LIVE'
            : '${duration!.inMinutes}:${duration!.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _YouTubeBadge extends StatelessWidget {
  const _YouTubeBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'YOUTUBE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}

class _DiscoverLoadingState extends StatelessWidget {
  const _DiscoverLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: ShimmerSkeleton(
            width: double.infinity,
            height: 280,
            radius: 24,
          ),
        ),
      ),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.explore_outlined, size: 58, color: tokens.textSecondary),
            SizedBox(height: 18),
            Text(
              'Search for a mood',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Try one of the curated topics above or search for an artist, album, or mix.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/youtube_service.dart';
import '../player/yazen_video_player_screen.dart';

class TubeModeScreen extends StatefulWidget {
  const TubeModeScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const TubeModeScreen());

  @override
  State<TubeModeScreen> createState() => _TubeModeScreenState();
}

class _TubeModeScreenState extends State<TubeModeScreen> {
  final _searchController = TextEditingController();
  final Map<String, Future<List<YoutubeVideoResult>>> _sections = {};
  bool _searching = false;
  String? _error;

  static const _topics = <String>[
    'Chill electronic mix',
    'Lo-fi beats',
    'Late night coding',
    'Ambient focus',
  ];

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadHome() {
    final service = context.read<HybridMusicController>().youtubeService;
    _sections
      ..clear()
      ..addAll(<String, Future<List<YoutubeVideoResult>>>{
        'Recommended for you': service.searchVideos(
          'chill electronic mix',
          limit: 8,
        ),
        'Fresh discoveries': service.searchVideos(
          'new music discoveries 2026',
          limit: 8,
        ),
        'Late-night sessions': service.searchVideos(
          'late night lofi ambient',
          limit: 8,
        ),
      });
    setState(() {});
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      _loadHome();
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final service = context.read<HybridMusicController>().youtubeService;
      final results = await service.searchVideos(query, limit: 18);
      if (!mounted) return;
      setState(() {
        _sections
          ..clear()
          ..['Search results'] = Future<List<YoutubeVideoResult>>.value(
            results,
          );
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error =
            'Tube search failed. Try another topic or check your connection.';
      });
    }
  }

  Future<void> _openVideo(YoutubeVideoResult result) async {
    final track = result.toMediaTrack();
    final mode = await showModalBottomSheet<_TubePlaybackMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlaybackChoiceSheet(track: track),
    );
    if (!mounted || mode == null) return;
    if (mode == _TubePlaybackMode.voice) {
      await context.read<HybridMusicController>().playTrack(track);
      return;
    }
    try {
      final service = context.read<HybridMusicController>().youtubeService;
      final streamUri = await service.getVideoStreamUrl(result.videoId);
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(YazenVideoPlayerScreen.route(track, streamUri: streamUri));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video stream is unavailable right now. Try Voice only.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        titleSpacing: 20,
        title: Row(
          children: <Widget>[
            Icon(Icons.ondemand_video_rounded, color: tokens.accent),
            const SizedBox(width: 9),
            const Text(
              'Tube Mode',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh Tube Mode',
            onPressed: _loadHome,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: tokens.accent,
        onRefresh: () async => _loadHome(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: <Widget>[
            TextField(
              controller: _searchController,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                hintText: 'Search Tube Mode',
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                suffixIcon:
                    _searching
                        ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : IconButton(
                          onPressed: () => _search(_searchController.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
              ),
            ),
            const SizedBox(height: 11),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _topics.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder:
                    (context, index) => ActionChip(
                      avatar: Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: tokens.accent,
                      ),
                      label: Text(_topics[index]),
                      onPressed: () {
                        _searchController.text = _topics[index];
                        _search(_topics[index]);
                      },
                    ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 22),
            for (final entry in _sections.entries) ...<Widget>[
              _Section(
                title: entry.key,
                future: entry.value,
                onOpen: _openVideo,
              ),
              const SizedBox(height: 26),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.future,
    required this.onOpen,
  });

  final String title;
  final Future<List<YoutubeVideoResult>> future;
  final ValueChanged<YoutubeVideoResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<YoutubeVideoResult>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final results = snapshot.data ?? const <YoutubeVideoResult>[];
            if (results.isEmpty) {
              return Text(
                'No videos available for this section.',
                style: TextStyle(color: tokens.textSecondary),
              );
            }
            return Column(
              children: <Widget>[
                for (
                  var index = 0;
                  index < results.length;
                  index++
                ) ...<Widget>[
                  _TubeCard(
                    result: results[index],
                    onTap: () => onOpen(results[index]),
                  ),
                  if (index != results.length - 1) const SizedBox(height: 22),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TubeCard extends StatelessWidget {
  const _TubeCard({required this.result, required this.onTap});

  final YoutubeVideoResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child:
                  result.thumbnailUrl == null
                      ? ColoredBox(
                        color: tokens.surfaceElevated,
                        child: const Icon(Icons.movie_rounded, size: 42),
                      )
                      : Image.network(
                        result.thumbnailUrl.toString(),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => ColoredBox(
                              color: tokens.surfaceElevated,
                              child: const Icon(Icons.movie_rounded, size: 42),
                            ),
                      ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      result.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.more_vert_rounded, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

enum _TubePlaybackMode { voice, video }

class _PlaybackChoiceSheet extends StatelessWidget {
  const _PlaybackChoiceSheet({required this.track});

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
              'How do you want to open it?',
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
              onTap: () => Navigator.pop(context, _TubePlaybackMode.voice),
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
              onTap: () => Navigator.pop(context, _TubePlaybackMode.video),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../models/media_track.dart';
import '../../core/theme/theme_provider.dart';
import '../../screens/effects/equalizer_screen.dart';
import '../../screens/library/local_media_screen.dart';
import '../../screens/queue/queue_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../player/full_player_screen.dart';
import '../player/yazen_video_player_screen.dart';
import 'widgets/library_tabs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _libraryPageController;

  @override
  void initState() {
    super.initState();
    final initialTab = context.read<HybridMusicController>().selectedTab;
    _libraryPageController = PageController(
      initialPage: LibraryTab.values.indexOf(initialTab),
    );
  }

  @override
  void dispose() {
    _libraryPageController.dispose();
    super.dispose();
  }

  void _selectLibraryTab(LibraryTab tab) {
    final controller = context.read<HybridMusicController>();
    controller.selectTab(tab);
    if (!_libraryPageController.hasClients) return;
    final target = LibraryTab.values.indexOf(tab);
    if ((_libraryPageController.page ?? target) == target) return;
    _libraryPageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = context.select<HybridMusicController, LibraryTab>(
      (controller) => controller.selectedTab,
    );
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
                  child: _buildHeader(context),
                ),
                LibraryTabs(
                  selected: selectedTab,
                  onSelected: _selectLibraryTab,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: PageView.builder(
                    controller: _libraryPageController,
                    itemCount: LibraryTab.values.length,
                    onPageChanged:
                        (index) => context
                            .read<HybridMusicController>()
                            .selectTab(LibraryTab.values[index]),
                    itemBuilder: (context, index) {
                      final tab = LibraryTab.values[index];
                      return LocalMediaScreen(
                        selectedTab: tab,
                        onTabSelected: _selectLibraryTab,
                        showTabs: false,
                      );
                    },
                  ),
                ),
              ],
            ),
            const Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _MiniPlayerHost(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                EchoBreathingGlow(
                  color: tokens.accentStrong,
                  radius: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/yazen_app_icon_master.png',
                      width: compact ? 43 : 48,
                      height: compact ? 43 : 48,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => Container(
                            width: compact ? 43 : 48,
                            height: compact ? 43 : 48,
                            color: tokens.accent,
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              color:
                                  tokens.isLight ? Colors.white : Colors.black,
                              size: compact ? 23 : 26,
                            ),
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'YAZEN',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
                _HeaderAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Search local audio and video',
                  onPressed: () => _showLocalSearch(context),
                ),
                _HeaderAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'Filter and sort library',
                  onPressed: () => _showLibrarySort(context),
                ),
                _HeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh library',
                  onPressed: controller.loadLibrary,
                ),
                if (!compact)
                  _HeaderAction(
                    icon: Icons.equalizer_rounded,
                    tooltip: 'Equalizer',
                    onPressed:
                        () =>
                            Navigator.of(context).push(EqualizerScreen.route()),
                  ),
                _HeaderAction(
                  icon: Icons.palette_outlined,
                  tooltip: 'Appearance',
                  color: tokens.accent,
                  onPressed: () => showThemePicker(context),
                ),
                _HeaderAction(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onPressed:
                      () => Navigator.of(context).push(SettingsScreen.route()),
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
        );
      },
    );
  }

  Future<void> _showLocalSearch(BuildContext context) async {
    final parentContext = context;
    final controller = context.read<HybridMusicController>();
    final searchController = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final tokens = sheetContext.read<ThemeProvider>().tokens;
          return StatefulBuilder(
            builder: (context, setState) {
              final query = searchController.text.trim().toLowerCase();
              final allTracks = <MediaTrack>[
                ...controller.localSongs,
                ...controller.localVideos,
              ];
              final seen = <String>{};
              final results = allTracks
                  .where((track) {
                    if (!seen.add(track.id)) return false;
                    if (query.isEmpty) return true;
                    final haystack =
                        '${track.title} ${track.artist} ${track.album}'
                            .toLowerCase();
                    return haystack.contains(query);
                  })
                  .toList(growable: false);
              final audioResults = results
                  .where((track) => !track.isVideo)
                  .toList(growable: false);
              return SafeArea(
                child: Container(
                  height: MediaQuery.sizeOf(context).height * 0.78,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  decoration: BoxDecoration(
                    color: tokens.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    border: Border.all(color: tokens.divider),
                  ),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.textSecondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search local media',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            results.isEmpty
                                ? Center(
                                  child: Text(
                                    query.isEmpty
                                        ? 'No local media found.'
                                        : 'No local matches for “$query”.',
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                )
                                : ListView.separated(
                                  itemCount: results.length,
                                  separatorBuilder:
                                      (_, _) => const SizedBox(height: 2),
                                  itemBuilder: (context, index) {
                                    final track = results[index];
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                      leading: Icon(
                                        track.isVideo
                                            ? Icons.ondemand_video_rounded
                                            : Icons.music_note_rounded,
                                        color: tokens.accent,
                                      ),
                                      title: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () {
                                        Navigator.pop(sheetContext);
                                        if (track.isVideo) {
                                          Navigator.of(parentContext).push(
                                            YazenVideoPlayerScreen.route(track),
                                          );
                                        } else {
                                          final audioIndex = audioResults
                                              .indexWhere(
                                                (candidate) =>
                                                    candidate.id == track.id,
                                              );
                                          if (audioIndex >= 0) {
                                            controller.playTrackQueue(
                                              audioResults,
                                              initialIndex: audioIndex,
                                            );
                                          }
                                        }
                                      },
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _showLibrarySort(BuildContext context) async {
    final controller = context.read<HybridMusicController>();
    final selected = await showModalBottomSheet<LibrarySort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final tokens = context.read<ThemeProvider>().tokens;
        return Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Sort library',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                RadioGroup<LibrarySort>(
                  groupValue: controller.librarySort,
                  onChanged: (value) {
                    if (value != null) Navigator.of(context).pop(value);
                  },
                  child: Column(
                    children: <Widget>[
                      ...LibrarySort.values.map(
                        (sort) => RadioListTile<LibrarySort>(
                          value: sort,
                          title: Text(_sortLabel(sort)),
                          activeColor: tokens.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) controller.setLibrarySort(selected);
  }

  String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.newestFirst => 'Newest first',
    LibrarySort.oldestFirst => 'Oldest first',
    LibrarySort.sizeLowToHigh => 'Size: low to high',
    LibrarySort.sizeHighToLow => 'Size: high to low',
    LibrarySort.durationShortToLong => 'Duration: shortest first',
    LibrarySort.durationLongToShort => 'Duration: longest first',
    LibrarySort.nameAZ => 'Name: A–Z',
    LibrarySort.nameZA => 'Name: Z–A',
  };
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: EchoIconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        color: color ?? tokens.textSecondary,
        selected: color != null,
        selectedColor: color ?? tokens.accent,
        backgroundColor: tokens.surface.withValues(alpha: 0.52),
        selectedBackgroundColor: (color ?? tokens.accent).withValues(
          alpha: 0.14,
        ),
        size: 34,
      ),
    );
  }
}

class _MiniPlayerHost extends StatefulWidget {
  const _MiniPlayerHost();

  @override
  State<_MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<_MiniPlayerHost> {
  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, playbackSnapshot) {
            return MiniPlayer(
              item: item,
              isPlaying: playbackSnapshot.data?.playing ?? false,
              duration: item.duration,
              positionStream: handler.player.positionStream,
              onPlayPause: controller.togglePlayback,
              onPrevious: handler.skipToPrevious,
              onNext: handler.skipToNext,
              onDismiss: () => unawaited(handler.stop()),
              onRepeat: controller.toggleRepeat,
              onQueue: () => Navigator.of(context).push(QueueScreen.route()),
              repeatOne: controller.repeatOne,
              onStop: handler.stop,
              onTap: () => Navigator.of(context).push(FullPlayerScreen.route()),
            );
          },
        );
      },
    );
  }
}

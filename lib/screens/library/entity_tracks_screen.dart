import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../home/widgets/track_list_tile.dart';

class LocalEntityTracksScreen extends StatefulWidget {
  const LocalEntityTracksScreen({
    required this.title,
    required this.loadTracks,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Future<List<MediaTrack>> Function() loadTracks;

  static Route<void> route({
    required String title,
    required Future<List<MediaTrack>> Function() loadTracks,
    String? subtitle,
  }) {
    return MaterialPageRoute<void>(
      builder:
          (_) => LocalEntityTracksScreen(
            title: title,
            loadTracks: loadTracks,
            subtitle: subtitle,
          ),
    );
  }

  @override
  State<LocalEntityTracksScreen> createState() =>
      _LocalEntityTracksScreenState();
}

class _LocalEntityTracksScreenState extends State<LocalEntityTracksScreen> {
  late Future<List<MediaTrack>> _tracksFuture;

  @override
  void initState() {
    super.initState();
    _tracksFuture = widget.loadTracks();
  }

  void _retry() {
    setState(() => _tracksFuture = widget.loadTracks());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final controller = context.read<HybridMusicController>();
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Retry',
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<MediaTrack>>(
        future: _tracksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _EntityMessage(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load tracks',
              subtitle: 'Check media permission and try again.',
              action: _retry,
            );
          }
          final tracks = controller.orderedTracks(snapshot.data ?? const []);
          if (tracks.isEmpty) {
            return _EntityMessage(
              icon: Icons.music_off_rounded,
              title: 'No playable tracks',
              subtitle:
                  widget.subtitle ??
                  'No local audio files were found in this collection.',
              action: _retry,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            itemCount: tracks.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                  child: Text(
                    '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              final trackIndex = index - 1;
              final track = tracks[trackIndex];
              return TrackListTile(
                key: ValueKey<String>('entity-${track.id}'),
                track: track,
                onTap:
                    () => unawaited(
                      controller.playTrackQueue(
                        tracks,
                        initialIndex: trackIndex,
                      ),
                    ),
                isFavorite: controller.isFavorite(track),
                onFavorite: () => controller.toggleFavorite(track),
                onAddToPlaylist: () => showAddToPlaylistSheet(context, track),
              );
            },
          );
        },
      ),
    );
  }
}

class _EntityMessage extends StatelessWidget {
  const _EntityMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: tokens.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: action,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

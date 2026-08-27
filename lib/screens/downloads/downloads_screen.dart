import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_provider.dart';
import '../../controllers/hybrid_music_controller.dart';
import '../../models/download_item.dart';
import '../../models/media_track.dart';
import '../../services/download_manager.dart';
import '../player/yazen_video_player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const DownloadsScreen());

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    final tokens = context.read<ThemeProvider>().tokens;
    final items = manager.items;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text(
          'Downloads',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: tokens.background,
        actions: <Widget>[
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Clear completed downloads',
              onPressed: () => _confirmClearCompleted(context, manager),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body:
          !manager.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? const _EmptyDownloads()
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder:
                    (context, index) => _DownloadTile(item: items[index]),
              ),
    );
  }

  Future<void> _confirmClearCompleted(
    BuildContext context,
    DownloadManager manager,
  ) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear completed downloads?'),
            content: const Text(
              'This removes downloaded files from this device.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
    if (shouldClear != true || !context.mounted) return;
    for (final item
        in manager.items.where((item) => item.isCompleted).toList()) {
      await manager.delete(item.id);
    }
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.item});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final manager = context.read<DownloadManager>();
    final tokens = context.read<ThemeProvider>().tokens;
    final isActive = item.isActive;
    final canPauseOrResume =
        item.kind == DownloadKind.classicAudio &&
        item.backgroundTaskId != null &&
        (item.status == DownloadStatus.downloading ||
            item.status == DownloadStatus.queued ||
            item.status == DownloadStatus.paused);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            _DownloadArtwork(item: item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.typeLabel}  •  ${item.qualityLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 7),
                  _DownloadStatus(item: item),
                  if (isActive &&
                      (item.progress != null ||
                          item.progressPercent != null)) ...<Widget>[
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value:
                          item.progress ??
                          (item.progressPercent == null
                              ? null
                              : item.progressPercent! / 100),
                      minHeight: 3,
                      color: tokens.accent,
                      backgroundColor: tokens.surfaceMuted,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<_DownloadAction>(
              tooltip: 'Download actions',
              icon: Icon(Icons.more_vert_rounded, color: tokens.textSecondary),
              onSelected: (action) async {
                switch (action) {
                  case _DownloadAction.open:
                    await _open(context, item);
                  case _DownloadAction.pause:
                    await manager.pause(item.id);
                  case _DownloadAction.resume:
                    await manager.resume(item.id);
                  case _DownloadAction.retry:
                    await manager.retry(item.id);
                  case _DownloadAction.cancel:
                    await manager.cancel(item.id);
                  case _DownloadAction.delete:
                    await manager.delete(item.id);
                }
              },
              itemBuilder:
                  (context) => <PopupMenuEntry<_DownloadAction>>[
                    if (item.isCompleted)
                      const PopupMenuItem(
                        value: _DownloadAction.open,
                        child: Text('Open'),
                      ),
                    if (canPauseOrResume &&
                        item.status != DownloadStatus.paused)
                      const PopupMenuItem(
                        value: _DownloadAction.pause,
                        child: Text('Pause'),
                      ),
                    if (canPauseOrResume &&
                        item.status == DownloadStatus.paused)
                      const PopupMenuItem(
                        value: _DownloadAction.resume,
                        child: Text('Resume'),
                      ),
                    if (isActive && !canPauseOrResume)
                      const PopupMenuItem(
                        value: _DownloadAction.cancel,
                        child: Text('Cancel'),
                      ),
                    if (item.status == DownloadStatus.failed ||
                        item.status == DownloadStatus.cancelled)
                      const PopupMenuItem(
                        value: _DownloadAction.retry,
                        child: Text('Retry'),
                      ),
                    const PopupMenuItem(
                      value: _DownloadAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, DownloadItem item) async {
    final file = await context.read<DownloadManager>().fileForItem(item);
    if (!context.mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloaded file is missing.')),
      );
      return;
    }
    final track = MediaTrack(
      id: 'download:${item.id}',
      title: item.title,
      artist: item.artist,
      album: 'Downloads',
      source: TrackSource.local,
      kind: item.kind == DownloadKind.video ? MediaKind.video : MediaKind.audio,
      uri: Uri.file(file.path),
      artworkUri: item.artworkUri,
    );
    if (track.isVideo) {
      await Navigator.of(context).push(YazenVideoPlayerScreen.route(track));
    } else {
      await context.read<HybridMusicController>().playTrack(track);
    }
  }
}

enum _DownloadAction { open, pause, resume, retry, cancel, delete }

class _DownloadStatus extends StatelessWidget {
  const _DownloadStatus({required this.item});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final label = switch (item.status) {
      DownloadStatus.queued => 'Queued',
      DownloadStatus.downloading => _progressLabel(item, 'Downloading'),
      DownloadStatus.processing => 'Processing final media…',
      DownloadStatus.paused => _progressLabel(item, 'Paused'),
      DownloadStatus.retrying => 'Retrying with a fresh stream…',
      DownloadStatus.completed => _sizeLabel(item),
      DownloadStatus.failed => item.errorMessage ?? 'Download failed',
      DownloadStatus.cancelled => 'Cancelled',
    };
    final color = switch (item.status) {
      DownloadStatus.completed => Colors.greenAccent,
      DownloadStatus.failed => Colors.redAccent,
      DownloadStatus.paused => Colors.amberAccent,
      DownloadStatus.retrying => tokens.accent,
      _ => tokens.textSecondary,
    };
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    );
  }

  String _progressLabel(DownloadItem item, String label) {
    final percent = item.progressPercent;
    return percent == null ? label : '$label · $percent%';
  }

  String _sizeLabel(DownloadItem item) {
    final bytes = item.totalBytes;
    if (bytes == null) return 'Ready offline';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB · Ready offline';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB · Ready offline';
  }
}

class _DownloadArtwork extends StatelessWidget {
  const _DownloadArtwork({required this.item});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 64,
        height: 64,
        child:
            item.artworkUri == null
                ? ColoredBox(
                  color: tokens.surfaceElevated,
                  child: Icon(
                    item.kind == DownloadKind.video
                        ? Icons.ondemand_video_rounded
                        : Icons.music_note_rounded,
                    color: tokens.accent,
                  ),
                )
                : Image.network(
                  item.artworkUri.toString(),
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => ColoredBox(
                        color: tokens.surfaceElevated,
                        child: Icon(
                          item.kind == DownloadKind.video
                              ? Icons.ondemand_video_rounded
                              : Icons.music_note_rounded,
                          color: tokens.accent,
                        ),
                      ),
                ),
      ),
    );
  }
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.download_done_rounded, size: 54, color: tokens.accent),
            const SizedBox(height: 14),
            const Text(
              'No downloads yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloaded audio and video will appear here when they are ready offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

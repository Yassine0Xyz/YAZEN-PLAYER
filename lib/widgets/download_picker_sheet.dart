import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../models/download_item.dart';
import '../models/media_track.dart';
import '../services/download_manager.dart';
import '../services/youtube_service.dart';

Future<void> showDownloadPicker(BuildContext context, MediaTrack track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DownloadPickerSheet(track: track),
  );
}

class _DownloadPickerSheet extends StatefulWidget {
  const _DownloadPickerSheet({required this.track});

  final MediaTrack track;

  @override
  State<_DownloadPickerSheet> createState() => _DownloadPickerSheetState();
}

class _DownloadPickerSheetState extends State<_DownloadPickerSheet> {
  late final Future<List<YoutubeDownloadOption>> _optionsFuture;
  String? _selectedId;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    final videoId = widget.track.youtubeId;
    _optionsFuture =
        videoId == null || videoId.isEmpty
            ? Future<List<YoutubeDownloadOption>>.error(
              StateError('This item has no YouTube ID.'),
            )
            : context.read<DownloadManager>().optionsFor(
              widget.track,
              videoId: videoId,
            );
  }

  Future<void> _start(YoutubeDownloadOption option) async {
    setState(() {
      _starting = true;
      _selectedId = option.id;
    });
    try {
      await context.read<DownloadManager>().enqueue(
        track: widget.track,
        option: option,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.track.title} added to Downloads')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start download: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxHeight: 650),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: tokens.divider),
        ),
        child: FutureBuilder<List<YoutubeDownloadOption>>(
          future: _optionsFuture,
          builder: (context, snapshot) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
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
                    'Download options',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError)
                    _ErrorState(message: snapshot.error.toString())
                  else if ((snapshot.data ?? const <YoutubeDownloadOption>[])
                      .isEmpty)
                    const _ErrorState(message: 'No compatible download found.')
                  else
                    ...snapshot.data!.map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OptionTile(
                          option: option,
                          selected: _selectedId == option.id,
                          enabled: !_starting,
                          onTap: () => _start(option),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final YoutubeDownloadOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final size =
        option.sizeBytes == null
            ? 'Size unavailable'
            : '${option.exactSize ? '' : '~'}${_formatBytes(option.sizeBytes!)}';
    final detail = <String>[
      option.kind == DownloadKind.video ? 'Video' : 'Audio only',
      if (option.bitrateKbps != null) '${option.bitrateKbps} kbps',
      size,
      if (option.requiresMuxing) 'will combine streams',
    ].join('  •  ');
    return Material(
      color: selected ? tokens.accent.withValues(alpha: 0.14) : tokens.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                option.kind == DownloadKind.video
                    ? Icons.ondemand_video_rounded
                    : option.kind == DownloadKind.mp3Audio
                    ? Icons.music_note_rounded
                    : Icons.high_quality_rounded,
                color: selected ? tokens.accent : tokens.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      option.qualityLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              selected
                  ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                  : Icon(Icons.download_rounded, color: tokens.accent),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(message, style: const TextStyle(color: Colors.redAccent)),
    );
  }
}

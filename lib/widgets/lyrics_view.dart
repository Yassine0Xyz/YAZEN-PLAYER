import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../services/lyrics_service.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({
    required this.lyricsFuture,
    required this.positionStream,
    this.height = 280,
    this.onLineTap,
    super.key,
  });

  final Future<SyncedLyrics?> lyricsFuture;
  final Stream<Duration> positionStream;
  final double height;
  final ValueChanged<Duration>? onLineTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return FutureBuilder<SyncedLyrics?>(
      future: lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: height,
            child: Center(
              child: CircularProgressIndicator(
                color: tokens.accent,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final lyrics = snapshot.data;
        if (lyrics == null) {
          return _LyricsMessage(
            message: 'No lyrics found for this track.',
            height: height,
          );
        }
        if (!lyrics.isSynced) {
          return _LyricsMessage(
            message:
                lyrics.plainText ?? 'Lyrics are available without timestamps.',
            height: height,
          );
        }

        return StreamBuilder<Duration>(
          stream: positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return _SyncedLyricsPanel(
              lines: lyrics.lines,
              position: position,
              height: height,
              onLineTap: onLineTap,
            );
          },
        );
      },
    );
  }

  static Future<void> showBottomSheet({
    required BuildContext context,
    required Future<SyncedLyrics?> lyricsFuture,
    required Stream<Duration> positionStream,
    ValueChanged<Duration>? onLineTap,
    String title = 'Lyrics',
  }) {
    final tokens = context.read<ThemeProvider>().tokens;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.background,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LyricsView(
                        lyricsFuture: lyricsFuture,
                        positionStream: positionStream,
                        height: double.infinity,
                        onLineTap: onLineTap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _SyncedLyricsPanel extends StatefulWidget {
  const _SyncedLyricsPanel({
    required this.lines,
    required this.position,
    required this.height,
    this.onLineTap,
  });

  final List<LyricLine> lines;
  final Duration position;
  final double height;
  final ValueChanged<Duration>? onLineTap;

  @override
  State<_SyncedLyricsPanel> createState() => _SyncedLyricsPanelState();
}

class _SyncedLyricsPanelState extends State<_SyncedLyricsPanel> {
  static const _syncLead = Duration(milliseconds: 120);

  final _scrollController = ScrollController();
  int? _lastScrolledIndex;

  int get _activeIndex {
    // A short lead compensates for audio-position and frame-rendering latency.
    // Do not mark line zero active before its timestamp has actually arrived.
    final effectivePosition = widget.position + _syncLead;
    var active = -1;
    for (var index = 0; index < widget.lines.length; index++) {
      if (widget.lines[index].timestamp <= effectivePosition) {
        active = index;
      } else {
        break;
      }
    }
    return active;
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position ||
        oldWidget.lines != widget.lines) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    if (!mounted || !_scrollController.hasClients) return;
    final index = _activeIndex;
    if (_lastScrolledIndex == index) return;
    _lastScrolledIndex = index;
    final target =
        (index.clamp(0, widget.lines.length) * 52.0)
            .clamp(0.0, _scrollController.position.maxScrollExtent)
            .toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final activeIndex = _activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    return Container(
      width: double.infinity,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.divider),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 72),
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              color: active ? tokens.accent : tokens.textSecondary,
              fontSize: active ? 18 : 14,
              height: 1.45,
              fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: InkWell(
                onTap:
                    widget.onLineTap == null
                        ? null
                        : () =>
                            widget.onLineTap!(widget.lines[index].timestamp),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    widget.lines[index].text,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage({required this.message, required this.height});

  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.divider),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: tokens.textSecondary, height: 1.5),
      ),
    );
  }
}

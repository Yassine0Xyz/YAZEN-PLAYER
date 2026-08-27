import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/app_theme.dart';
import '../../models/stem_models.dart';

class AiMixerScreen extends StatefulWidget {
  const AiMixerScreen({required this.stems, super.key});

  final Map<StemType, Uri> stems;

  static Route<void> route({required Map<StemType, Uri> stems}) {
    return MaterialPageRoute<void>(builder: (_) => AiMixerScreen(stems: stems));
  }

  @override
  State<AiMixerScreen> createState() => _AiMixerScreenState();
}

class _AiMixerScreenState extends State<AiMixerScreen> {
  late final StemMixerController _mixer;
  final _volumes = <StemType, double>{
    for (final stem in StemType.values) stem: 1,
  };
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _mixer = StemMixerController(widget.stems);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _mixer.initialize();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _mixer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'AI Mixer',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reset levels',
            onPressed: _resetVolumes,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _mixer.initialization,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _MixerEmptyState(
                message: 'Could not load separated stems. ${snapshot.error}',
              );
            }
            if (widget.stems.isEmpty) {
              return const _MixerEmptyState(
                message: 'Separate a local track first to open the DJ mixer.',
              );
            }
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              children: <Widget>[
                const _MixerHeader(),
                const SizedBox(height: 22),
                _StemBoard(
                  volumes: _volumes,
                  enabledStems: widget.stems.keys,
                  onVolumeChanged: (stem, value) {
                    setState(() => _volumes[stem] = value);
                    unawaited(_mixer.setVolume(stem, value));
                  },
                ),
                const SizedBox(height: 20),
                _MasterTransport(
                  isPlaying: _playing,
                  onPlayPause: _togglePlayback,
                  onStop: () async {
                    await _mixer.pause();
                    await _mixer.seek(Duration.zero);
                    if (mounted) setState(() => _playing = false);
                  },
                ),
                const SizedBox(height: 14),
                const Text(
                  'Stem separation runs locally on your configured open-source service. Small timing corrections keep each layer phase-aligned during playback.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _mixer.pause();
    } else {
      await _mixer.play();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  void _resetVolumes() {
    setState(() {
      for (final stem in StemType.values) {
        _volumes[stem] = 1;
      }
    });
    unawaited(_mixer.resetVolumes());
  }
}

class StemMixerController {
  StemMixerController(Map<StemType, Uri> sources)
    : _players = {
        for (final entry in sources.entries) entry.key: AudioPlayer(),
      },
      _sources = sources;

  final Map<StemType, AudioPlayer> _players;
  final Map<StemType, Uri> _sources;
  late final Future<void> initialization = _load();
  Timer? _syncTimer;
  bool _playing = false;

  Future<void> initialize() => initialization;

  Future<void> _load() async {
    await Future.wait(
      _sources.entries.map(
        (entry) =>
            _players[entry.key]!.setAudioSource(AudioSource.uri(entry.value)),
      ),
    );
  }

  Future<void> play() async {
    _playing = true;
    await Future.wait(_players.values.map((player) => player.play()));
    _syncTimer ??= Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_correctDrift()),
    );
  }

  Future<void> pause() async {
    _playing = false;
    await Future.wait(_players.values.map((player) => player.pause()));
  }

  Future<void> seek(Duration position) async {
    await Future.wait(_players.values.map((player) => player.seek(position)));
  }

  Future<void> setVolume(StemType stem, double volume) async {
    await _players[stem]?.setVolume(volume);
  }

  Future<void> resetVolumes() async {
    await Future.wait(_players.values.map((player) => player.setVolume(1)));
  }

  Future<void> _correctDrift() async {
    if (!_playing || _players.isEmpty) return;
    final master = _players.values.first.position;
    for (final player in _players.values.skip(1)) {
      final driftMs =
          (player.position.inMilliseconds - master.inMilliseconds).abs();
      if (driftMs > 90) {
        await player.seek(master);
      }
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    for (final player in _players.values) {
      unawaited(player.dispose());
    }
  }
}

class _MixerHeader extends StatelessWidget {
  const _MixerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF322656), Color(0xFF1B1B20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: const Row(
        children: <Widget>[
          _PulseIcon(),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'STEM LAB',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Make the mix yours',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 5),
                Text(
                  'Dial in vocals, drums, bass, and instruments independently.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  const _PulseIcon();

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (_, _) => Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(
                alpha: 0.11 + (_controller.value * 0.08),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  blurRadius: 20 + (_controller.value * 10),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.multitrack_audio_rounded,
              color: AppColors.accent,
              size: 29,
            ),
          ),
    );
  }
}

class _StemBoard extends StatelessWidget {
  const _StemBoard({
    required this.volumes,
    required this.enabledStems,
    required this.onVolumeChanged,
  });

  final Map<StemType, double> volumes;
  final Iterable<StemType> enabledStems;
  final void Function(StemType stem, double value) onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 365,
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children:
            StemType.values.map((stem) {
              final active = enabledStems.contains(stem);
              return Expanded(
                child: _StemChannel(
                  stem: stem,
                  value: volumes[stem] ?? 1,
                  active: active,
                  onChanged:
                      active ? (value) => onVolumeChanged(stem, value) : null,
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _StemChannel extends StatelessWidget {
  const _StemChannel({
    required this.stem,
    required this.value,
    required this.active,
    this.onChanged,
  });

  final StemType stem;
  final double value;
  final bool active;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor:
                    active ? AppColors.accent : AppColors.surfaceMuted,
                inactiveTrackColor: AppColors.surfaceMuted,
                thumbColor:
                    active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
            ),
          ),
        ),
        Text(
          '${(value * 100).round()}%',
          style: TextStyle(
            color: active ? AppColors.accent : AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 9),
        Icon(
          _iconFor(stem),
          color: active ? AppColors.textPrimary : AppColors.textSecondary,
          size: 20,
        ),
        const SizedBox(height: 7),
        Text(
          stem.shortLabel,
          style: TextStyle(
            color: active ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  IconData _iconFor(StemType type) => switch (type) {
    StemType.vocals => Icons.mic_rounded,
    StemType.bass => Icons.graphic_eq_rounded,
    StemType.drums => Icons.circle_rounded,
    StemType.other => Icons.piano_rounded,
  };
}

class _MasterTransport extends StatelessWidget {
  const _MasterTransport({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onStop,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded),
          tooltip: 'Stop',
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          onPressed: onPlayPause,
          style: IconButton.styleFrom(
            minimumSize: const Size(68, 68),
            backgroundColor: AppColors.textPrimary,
            foregroundColor: Colors.black,
          ),
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _MixerEmptyState extends StatelessWidget {
  const _MixerEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
      ),
    );
  }
}

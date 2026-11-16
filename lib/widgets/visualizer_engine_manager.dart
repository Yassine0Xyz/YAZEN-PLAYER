import 'dart:async';

import 'package:flutter/material.dart';

import '../services/visualizer_settings.dart';
import 'advanced_visualizer_engine.dart';
import 'audio_visualizer.dart';

/// Routes to exactly one renderer. The inactive engine is not kept in the tree.
class VisualizerEngineManager extends StatefulWidget {
  const VisualizerEngineManager({
    required this.playing,
    this.audioSessionId,
    this.sourceUri,
    this.height = 34,
    this.barCount = 28,
    this.color,
    this.seed,
    this.position,
    this.positionStream,
    this.speedStream,
    this.initialSpeed = 1,
    this.duration,
    this.onSeek,
    this.profile = AudioVisualizerProfile.compact,
    super.key,
  });

  final bool playing;
  final int? audioSessionId;
  final String? sourceUri;
  final double height;
  final int barCount;
  final Color? color;
  final String? seed;
  final Duration? position;
  final Stream<Duration>? positionStream;
  final Stream<double>? speedStream;
  final double initialSpeed;
  final Duration? duration;
  final ValueChanged<Duration>? onSeek;
  final AudioVisualizerProfile profile;

  @override
  State<VisualizerEngineManager> createState() =>
      _VisualizerEngineManagerState();
}

class _VisualizerEngineManagerState extends State<VisualizerEngineManager> {
  final VisualizerSettings _settings = VisualizerSettings.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        if (_settings.loaded && !_settings.enabled) {
          return const SizedBox.shrink();
        }
        if (_settings.loaded &&
            _settings.engine == VisualizerEngineKind.advanced) {
          return AdvancedVisualizerEngine(
            key: const ValueKey<String>('advanced-visualizer-engine'),
            playing: widget.playing,
            sourceUri: widget.sourceUri,
            position: widget.position,
            positionStream: widget.positionStream,
            speedStream: widget.speedStream,
            initialSpeed: widget.initialSpeed,
            height: widget.height,
            barCount: widget.barCount,
            duration: widget.duration,
            style: _settings.advancedStyle,
            color: widget.color,
            onSeek: widget.onSeek,
          );
        }
        return AudioVisualizer(
          key: const ValueKey<String>('legacy-visualizer-engine'),
          playing: widget.playing,
          audioSessionId: widget.audioSessionId,
          sourceUri: widget.sourceUri,
          height: widget.height,
          barCount: widget.barCount,
          color: widget.color,
          seed: widget.seed,
          position: widget.position,
          positionStream: widget.positionStream,
          speedStream: widget.speedStream,
          initialSpeed: widget.initialSpeed,
          duration: widget.duration,
          onSeek: widget.onSeek,
          profile: widget.profile,
        );
      },
    );
  }
}

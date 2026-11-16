import 'package:flutter/foundation.dart';

import 'playback_energy_service.dart';

enum VisualizerFrameStatus { idle, live, preparing, suspended, unavailable }

@immutable
class VisualizerFrame {
  const VisualizerFrame({
    required this.status,
    required this.sourceId,
    required this.epoch,
    required this.timestamp,
    required this.positionMs,
    required this.bands,
    required this.retainedBands,
  });

  const VisualizerFrame.idle()
    : status = VisualizerFrameStatus.idle,
      sourceId = null,
      epoch = 0,
      timestamp = null,
      positionMs = null,
      bands = const <double>[],
      retainedBands = const <double>[];

  final VisualizerFrameStatus status;
  final String? sourceId;
  final int epoch;
  final DateTime? timestamp;
  final int? positionMs;

  /// Only current, valid audio samples. Empty during preparing/suspension.
  final List<double> bands;

  /// Last valid frame, retained strictly as a visual transition snapshot.
  final List<double> retainedBands;

  bool get hasLiveSignal =>
      status == VisualizerFrameStatus.live && bands.isNotEmpty;
}

/// Shared PCM/data lifecycle boundary used by every visualizer engine.
/// Rendering consumers can be replaced without creating a second PCM source.
class VisualizerDataHub {
  VisualizerDataHub._({PlaybackEnergyService? service})
    : _service = service ?? PlaybackEnergyService.instance {
    _service.energy.addListener(_onEnergyChanged);
    _onEnergyChanged();
  }

  @visibleForTesting
  VisualizerDataHub.forTesting({required PlaybackEnergyService service})
    : this._(service: service);

  static final VisualizerDataHub instance = VisualizerDataHub._();

  final PlaybackEnergyService _service;
  final ValueNotifier<VisualizerFrame> _frame = ValueNotifier<VisualizerFrame>(
    const VisualizerFrame.idle(),
  );
  List<double> _retainedBands = const <double>[];
  String? _retainedSourceId;

  ValueListenable<VisualizerFrame> get frame => _frame;

  PlaybackEnergyConsumer attachConsumer({
    String? sourceUri,
    int positionMs = 0,
    bool playing = false,
    bool visible = false,
    double speed = 1,
  }) => _service.attachConsumer(
    sourceUri: sourceUri,
    positionMs: positionMs,
    playing: playing,
    visible: visible,
    speed: speed,
  );

  void invalidateForSeek(Duration target) => _service.invalidateForSeek(target);

  void _onEnergyChanged() {
    final energy = _service.energy.value;
    if (energy.status == AudioEnergyStatus.live && energy.bands.isNotEmpty) {
      _retainedBands = List<double>.unmodifiable(energy.bands);
      _retainedSourceId = energy.sourceId;
      _frame.value = VisualizerFrame(
        status: VisualizerFrameStatus.live,
        sourceId: energy.sourceId,
        epoch: energy.epoch,
        timestamp: energy.timestamp,
        positionMs: energy.positionMs,
        bands: List<double>.unmodifiable(energy.bands),
        retainedBands: _retainedBands,
      );
      return;
    }

    final status = switch (energy.status) {
      AudioEnergyStatus.idle => VisualizerFrameStatus.idle,
      AudioEnergyStatus.preparing => VisualizerFrameStatus.preparing,
      AudioEnergyStatus.suspended => VisualizerFrameStatus.suspended,
      AudioEnergyStatus.unavailable => VisualizerFrameStatus.unavailable,
      AudioEnergyStatus.live => VisualizerFrameStatus.unavailable,
    };
    if (status == VisualizerFrameStatus.idle ||
        status == VisualizerFrameStatus.unavailable) {
      _retainedBands = const <double>[];
      _retainedSourceId = null;
    } else if (energy.sourceId != null &&
        _retainedSourceId != null &&
        energy.sourceId != _retainedSourceId) {
      _retainedBands = const <double>[];
      _retainedSourceId = null;
    }

    _frame.value = VisualizerFrame(
      status: status,
      sourceId: energy.sourceId ?? _retainedSourceId,
      epoch: energy.epoch,
      timestamp: energy.timestamp,
      positionMs: energy.positionMs,
      bands: const <double>[],
      retainedBands: _retainedBands,
    );
  }

  @visibleForTesting
  void disposeForTesting() {
    _service.energy.removeListener(_onEnergyChanged);
    _frame.dispose();
  }
}

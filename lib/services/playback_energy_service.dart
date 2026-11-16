import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'audio_beat_detector.dart';
import 'linux_pcm_spectrum_service.dart';

@visibleForTesting
int estimatePlaybackPositionMs({
  required int positionMs,
  required Duration elapsed,
  required double speed,
}) {
  final advancedMs =
      (elapsed.inMicroseconds / 1000 * speed.clamp(0.25, 3.0)).round();
  return math.max(0, positionMs + advancedMs);
}

enum AudioEnergyStatus { idle, live, preparing, suspended, unavailable }

@immutable
class AudioEnergy {
  const AudioEnergy({
    required this.level,
    required this.bass,
    required this.mid,
    required this.treble,
    required this.available,
    this.beat = 0,
    this.bands = const <double>[],
    this.status = AudioEnergyStatus.live,
    this.sourceId,
    this.epoch = 0,
    this.positionMs,
    this.timestamp,
  });

  const AudioEnergy.idle()
    : level = 0,
      bass = 0,
      mid = 0,
      treble = 0,
      available = false,
      beat = 0,
      bands = const <double>[],
      status = AudioEnergyStatus.idle,
      sourceId = null,
      epoch = 0,
      positionMs = null,
      timestamp = null;

  final double level;
  final double bass;
  final double mid;
  final double treble;
  final bool available;
  final double beat;
  final List<double> bands;
  final AudioEnergyStatus status;
  final String? sourceId;
  final int epoch;
  final int? positionMs;
  final DateTime? timestamp;
}

abstract interface class PcmSpectrumSource {
  Future<bool> start(String sourceUri);
  Future<PcmSpectrumReadResult> read(int positionMs);
  Future<void> stop();
}

enum PcmSpectrumReadState { live, preparing, unavailable }

@immutable
class PcmSpectrumReadResult {
  const PcmSpectrumReadResult.live(this.bands)
    : state = PcmSpectrumReadState.live;

  const PcmSpectrumReadResult.preparing()
    : state = PcmSpectrumReadState.preparing,
      bands = const <double>[];

  const PcmSpectrumReadResult.unavailable()
    : state = PcmSpectrumReadState.unavailable,
      bands = const <double>[];

  final PcmSpectrumReadState state;
  final List<double> bands;
}

class PlatformPcmSpectrumSource implements PcmSpectrumSource {
  static const MethodChannel _channel = MethodChannel('yazen/audio_visualizer');

  @override
  Future<bool> start(String sourceUri) async {
    if (Platform.isLinux) {
      return LinuxPcmSpectrumService.instance.start(sourceUri);
    }
    if (!Platform.isAndroid) return false;
    final response = await _channel.invokeMethod<dynamic>(
      'startPcm',
      <String, Object?>{'uri': sourceUri},
    );
    return response is Map<dynamic, dynamic> && response['started'] == true;
  }

  @override
  Future<PcmSpectrumReadResult> read(int positionMs) async {
    final response =
        Platform.isLinux
            ? LinuxPcmSpectrumService.instance.read(positionMs)
            : await _channel.invokeMethod<dynamic>('readPcm', <String, Object?>{
              'positionMs': positionMs,
            });
    if (response is! Map<dynamic, dynamic>) {
      return const PcmSpectrumReadResult.unavailable();
    }
    if (response['state'] == 'preparing') {
      return const PcmSpectrumReadResult.preparing();
    }
    if (response['state'] != 'live') {
      return const PcmSpectrumReadResult.unavailable();
    }
    final rawBands = response['bands'];
    if (rawBands is! List<dynamic>) {
      return const PcmSpectrumReadResult.unavailable();
    }
    final bands = rawBands
        .whereType<num>()
        .map((value) => value.toDouble().clamp(0.0, 1.0))
        .toList(growable: false);
    return bands.isEmpty
        ? const PcmSpectrumReadResult.unavailable()
        : PcmSpectrumReadResult.live(bands);
  }

  @override
  Future<void> stop() async {
    if (Platform.isLinux) {
      await LinuxPcmSpectrumService.instance.stop();
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopPcm');
    } on MissingPluginException {
      // There is no PCM bridge on this platform.
    } on PlatformException {
      // An inactive source is already stopped.
    }
  }
}

class PlaybackEnergyConsumer {
  PlaybackEnergyConsumer._(this._service, this._id);

  final PlaybackEnergyService _service;
  final int _id;
  bool _released = false;

  void update({
    String? sourceUri,
    int? positionMs,
    bool? playing,
    bool? visible,
    double? speed,
  }) {
    if (_released) return;
    _service._updateConsumer(
      _id,
      sourceUri: sourceUri,
      positionMs: positionMs,
      playing: playing,
      visible: visible,
      speed: speed,
    );
  }

  void dispose() {
    if (_released) return;
    _released = true;
    _service._detachConsumer(_id);
  }
}

class PlaybackEnergyService extends WidgetsBindingObserver {
  PlaybackEnergyService({
    PcmSpectrumSource? source,
    bool observeLifecycle = true,
  }) : _source = source ?? PlatformPcmSpectrumSource() {
    if (observeLifecycle) {
      final binding = WidgetsBinding.instance;
      _appResumed =
          binding.lifecycleState == null ||
          binding.lifecycleState == AppLifecycleState.resumed;
      binding.addObserver(this);
    }
  }

  static final PlaybackEnergyService instance = PlaybackEnergyService();
  static const Duration _pollInterval = Duration(milliseconds: 40);
  static const Duration _preparingGrace = Duration(milliseconds: 80);
  static const int _positionDiscontinuityToleranceMs = 120;
  static const Duration _attack = Duration(milliseconds: 80);
  static const Duration _release = Duration(milliseconds: 600);

  final PcmSpectrumSource _source;
  final AudioBeatDetector _beatDetector = AudioBeatDetector();
  final ValueNotifier<AudioEnergy> _energy = ValueNotifier<AudioEnergy>(
    const AudioEnergy.idle(),
  );
  final Map<int, _EnergyConsumerState> _consumers =
      <int, _EnergyConsumerState>{};

  Timer? _pollTimer;
  Future<void> _lifecycleTail = Future<void>.value();
  String? _activeUri;
  int? _activeConsumerId;
  int _sourceEpoch = 0;
  int? _readInFlightEpoch;
  int _nextConsumerId = 0;
  int _revision = 0;
  bool _appResumed = true;
  bool _retainSnapshotWhenNoConsumer = false;
  DateTime? _lastFrameAt;
  DateTime? _lastLiveAt;
  String? _lastLiveUri;
  int? _lastLiveConsumerId;
  int? _lastLivePositionMs;
  double _lastLiveSpeed = 1.0;

  ValueListenable<AudioEnergy> get energy => _energy;
  @visibleForTesting
  int get consumerCount => _consumers.length;

  PlaybackEnergyConsumer attachConsumer({
    String? sourceUri,
    int positionMs = 0,
    bool playing = false,
    bool visible = false,
    double speed = 1.0,
  }) {
    final id = ++_nextConsumerId;
    _consumers[id] = _EnergyConsumerState(
      sourceUri: sourceUri,
      positionMs: math.max(0, positionMs),
      playing: playing,
      visible: visible,
      speed: speed.clamp(0.25, 3.0).toDouble(),
      positionAnchorAt: playing ? DateTime.now() : null,
    );
    _scheduleSync();
    return PlaybackEnergyConsumer._(this, id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (!_appResumed) {
      _retainSnapshotWhenNoConsumer = true;
      _invalidateActiveSignal(status: AudioEnergyStatus.suspended);
    }
    _scheduleSync();
  }

  void _updateConsumer(
    int id, {
    String? sourceUri,
    int? positionMs,
    bool? playing,
    bool? visible,
    double? speed,
  }) {
    final consumer = _consumers[id];
    if (consumer == null) return;
    final previousEffectivePosition = consumer.effectivePositionMs;
    AudioEnergyStatus? invalidationStatus;
    if (sourceUri != null && sourceUri != consumer.sourceUri) {
      if (id == _activeConsumerId) invalidationStatus = AudioEnergyStatus.idle;
      _retainSnapshotWhenNoConsumer = false;
      consumer.sourceUri = sourceUri;
    }
    if (positionMs != null) {
      final safePositionMs = math.max(0, positionMs);
      final positionError = (safePositionMs - previousEffectivePosition).abs();
      if (id == _activeConsumerId &&
          consumer.playing &&
          positionError > _positionDiscontinuityToleranceMs) {
        invalidationStatus ??= AudioEnergyStatus.preparing;
      }
      consumer.positionMs = safePositionMs;
      consumer.positionAnchorAt = consumer.playing ? DateTime.now() : null;
    }
    if (speed != null && speed != consumer.speed) {
      final now = DateTime.now();
      consumer.positionMs = consumer.effectivePositionMsAt(now);
      consumer.positionAnchorAt = consumer.playing ? now : null;
      consumer.speed = speed.clamp(0.25, 3.0).toDouble();
    }
    if (playing != null && playing != consumer.playing) {
      if (!playing && id == _activeConsumerId) {
        invalidationStatus = AudioEnergyStatus.idle;
        _retainSnapshotWhenNoConsumer = false;
      }
      consumer.positionAnchorAt = playing ? DateTime.now() : null;
      consumer.playing = playing;
    }
    if (visible != null) {
      if (!visible && id == _activeConsumerId) {
        invalidationStatus ??= AudioEnergyStatus.suspended;
        _retainSnapshotWhenNoConsumer = true;
      }
      consumer.visible = visible;
    }
    if (invalidationStatus != null) {
      _invalidateActiveSignal(status: invalidationStatus);
    }
    _scheduleSync();
  }

  /// Invalidates the current spectrum frame before an explicit player seek.
  /// The PCM source remains active and the next read is requested at [target].
  void invalidateForSeek(Duration target) {
    final consumer =
        _activeConsumerId == null ? null : _consumers[_activeConsumerId];
    if (consumer != null) {
      consumer.positionMs = math.max(0, target.inMilliseconds);
      consumer.positionAnchorAt = consumer.playing ? DateTime.now() : null;
    }
    _invalidateActiveSignal(status: AudioEnergyStatus.preparing);
  }

  void _invalidateActiveSignal({
    AudioEnergyStatus status = AudioEnergyStatus.unavailable,
  }) {
    _sourceEpoch++;
    _clearLastLiveFrame();
    _publishUnavailable(status: status);
  }

  void _clearLastLiveFrame() {
    _lastFrameAt = null;
    _lastLiveAt = null;
    _lastLiveUri = null;
    _lastLiveConsumerId = null;
    _lastLivePositionMs = null;
    _lastLiveSpeed = 1.0;
  }

  void _detachConsumer(int id) {
    final removed = _consumers.remove(id);
    if (removed == null) return;
    if (id == _activeConsumerId && removed.playing) {
      _retainSnapshotWhenNoConsumer = true;
      _invalidateActiveSignal(status: AudioEnergyStatus.suspended);
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    ++_revision;
    _lifecycleTail = _lifecycleTail
        .then((_) => _synchronizeSource())
        .catchError((Object _) {
          _publishUnavailable();
        });
  }

  Future<void> _synchronizeSource() async {
    final desired = _desiredConsumer();
    if (desired == null) {
      final hasPlayingHiddenConsumer = _consumers.values.any(
        (consumer) => consumer.playing && consumer.sourceUri == _activeUri,
      );
      final status =
          !_appResumed ||
                  _retainSnapshotWhenNoConsumer ||
                  hasPlayingHiddenConsumer
              ? AudioEnergyStatus.suspended
              : AudioEnergyStatus.idle;
      await _deactivateSource(status: status);
      _retainSnapshotWhenNoConsumer = false;
      return;
    }

    final uri = desired.value.sourceUri!;
    if (_activeUri == uri) {
      if (_activeConsumerId != null && _activeConsumerId != desired.key) {
        _invalidateActiveSignal(status: AudioEnergyStatus.preparing);
      }
      _activeConsumerId = desired.key;
      return;
    }

    final revision = _revision;
    if (_activeUri != null) await _deactivateSource();
    final started = await _source.start(uri);
    if (!started) {
      _publishUnavailable();
      return;
    }
    if (revision != _revision || _desiredConsumer()?.value.sourceUri != uri) {
      await _source.stop();
      return;
    }

    _activeUri = uri;
    _activeConsumerId = desired.key;
    _clearLastLiveFrame();
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_readFrame()));
    unawaited(_readFrame());
  }

  MapEntry<int, _EnergyConsumerState>? _desiredConsumer() {
    if (!_appResumed) return null;
    for (final entry in _consumers.entries) {
      final consumer = entry.value;
      if (consumer.visible &&
          consumer.playing &&
          consumer.sourceUri != null &&
          consumer.sourceUri!.isNotEmpty) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _deactivateSource({
    AudioEnergyStatus status = AudioEnergyStatus.idle,
  }) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final wasActive = _activeUri != null;
    _activeUri = null;
    _activeConsumerId = null;
    _invalidateActiveSignal(status: status);
    if (wasActive) await _source.stop();
  }

  Future<void> _readFrame() async {
    final uri = _activeUri;
    final consumerId = _activeConsumerId;
    if (uri == null || consumerId == null) return;
    final readEpoch = _sourceEpoch;
    if (_readInFlightEpoch == readEpoch) return;
    final consumer = _consumers[consumerId];
    if (consumer == null) return;
    final requestedPositionMs = consumer.effectivePositionMs;
    final readSpeed = consumer.speed;
    _readInFlightEpoch = readEpoch;
    try {
      final result = await _source.read(requestedPositionMs);
      if (!_readIsCurrent(readEpoch, uri, consumerId)) return;
      switch (result.state) {
        case PcmSpectrumReadState.live:
          if (result.bands.isEmpty) {
            _clearLastLiveFrame();
            _publishUnavailable(status: AudioEnergyStatus.unavailable);
          } else {
            _lastLiveAt = DateTime.now();
            _lastLiveUri = uri;
            _lastLiveConsumerId = consumerId;
            _lastLivePositionMs = requestedPositionMs;
            _lastLiveSpeed = readSpeed;
            _publishBands(
              result.bands,
              sourceUri: uri,
              epoch: readEpoch,
              positionMs: requestedPositionMs,
            );
          }
        case PcmSpectrumReadState.preparing:
          if (!_canRetainPreparingFrame(
            uri: uri,
            consumerId: consumerId,
            requestedPositionMs: requestedPositionMs,
          )) {
            _clearLastLiveFrame();
            _publishUnavailable(status: AudioEnergyStatus.preparing);
          }
        case PcmSpectrumReadState.unavailable:
          _clearLastLiveFrame();
          _publishUnavailable(status: AudioEnergyStatus.unavailable);
      }
    } on MissingPluginException {
      _clearLastLiveFrame();
      _publishUnavailable(status: AudioEnergyStatus.unavailable);
      _scheduleSync();
    } on PlatformException {
      _clearLastLiveFrame();
      _publishUnavailable(status: AudioEnergyStatus.unavailable);
    } finally {
      if (_readInFlightEpoch == readEpoch) _readInFlightEpoch = null;
    }
  }

  bool _readIsCurrent(int epoch, String uri, int consumerId) {
    if (epoch != _sourceEpoch ||
        uri != _activeUri ||
        consumerId != _activeConsumerId) {
      return false;
    }
    final desired = _desiredConsumer();
    return desired?.key == consumerId && desired?.value.sourceUri == uri;
  }

  bool _canRetainPreparingFrame({
    required String uri,
    required int consumerId,
    required int requestedPositionMs,
  }) {
    final lastLiveAt = _lastLiveAt;
    final lastPositionMs = _lastLivePositionMs;
    if (!_energy.value.available ||
        lastLiveAt == null ||
        lastPositionMs == null ||
        _lastLiveUri != uri ||
        _lastLiveConsumerId != consumerId) {
      return false;
    }
    final elapsed = DateTime.now().difference(lastLiveAt);
    if (elapsed > _preparingGrace) return false;
    final expectedPositionMs =
        lastPositionMs + elapsed.inMilliseconds * _lastLiveSpeed;
    return (requestedPositionMs - expectedPositionMs).abs() <=
        _positionDiscontinuityToleranceMs;
  }

  void _publishBands(
    List<double> bands, {
    required String sourceUri,
    required int epoch,
    required int positionMs,
  }) {
    final targets = _summarize(bands);
    final now = DateTime.now();
    final elapsed =
        _lastFrameAt == null ? _pollInterval : now.difference(_lastFrameAt!);
    _lastFrameAt = now;
    final previous = _energy.value;
    final level = _smooth(previous.level, targets.$1, elapsed);
    final bass = _smooth(previous.bass, targets.$2, elapsed);
    final mid = _smooth(previous.mid, targets.$3, elapsed);
    final treble = _smooth(previous.treble, targets.$4, elapsed);
    final beat = _beatDetector.process(bands, timestamp: now);
    _energy.value = AudioEnergy(
      level: level,
      bass: bass,
      mid: mid,
      treble: treble,
      available: true,
      beat: beat,
      bands: List<double>.unmodifiable(bands),
      status: AudioEnergyStatus.live,
      sourceId: sourceUri,
      epoch: epoch,
      positionMs: positionMs,
      timestamp: now,
    );
  }

  (double, double, double, double) _summarize(List<double> bands) {
    double average(int start, int end) {
      final safeStart = start.clamp(0, bands.length);
      final safeEnd = end.clamp(safeStart, bands.length);
      if (safeEnd <= safeStart) return 0;
      var sum = 0.0;
      for (var index = safeStart; index < safeEnd; index++) {
        sum += bands[index].clamp(0.0, 1.0);
      }
      return sum / (safeEnd - safeStart);
    }

    final count = bands.length;
    final bass = average(0, math.max(1, (count * 0.25).round()));
    final midStart = (count * 0.25).round();
    final midEnd = (count * 0.7).round();
    final mid = average(midStart, math.max(midStart + 1, midEnd));
    final treble = average(midEnd, count);
    return ((bass + mid + treble) / 3, bass, mid, treble);
  }

  double _smooth(double current, double target, Duration elapsed) {
    final timeConstant = target >= current ? _attack : _release;
    final seconds =
        math.max(0.0, elapsed.inMicroseconds) / Duration.microsecondsPerSecond;
    final alpha =
        1.0 -
        math.exp(
          -seconds /
              (timeConstant.inMicroseconds / Duration.microsecondsPerSecond),
        );
    return (current + (target - current) * alpha).clamp(0.0, 1.0);
  }

  void _publishUnavailable({
    AudioEnergyStatus status = AudioEnergyStatus.unavailable,
  }) {
    _clearLastLiveFrame();
    _beatDetector.reset();
    _lastFrameAt = null;
    final current = _energy.value;
    if (!current.available &&
        current.status == status &&
        current.level == 0 &&
        current.bass == 0 &&
        current.mid == 0 &&
        current.treble == 0 &&
        current.bands.isEmpty) {
      return;
    }
    _energy.value = AudioEnergy(
      level: 0,
      bass: 0,
      mid: 0,
      treble: 0,
      available: false,
      status: status,
      sourceId: _activeUri,
      epoch: _sourceEpoch,
    );
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    _consumers.clear();
    await _deactivateSource();
    WidgetsBinding.instance.removeObserver(this);
    _energy.dispose();
  }
}

class _EnergyConsumerState {
  _EnergyConsumerState({
    required this.sourceUri,
    required this.positionMs,
    required this.playing,
    required this.visible,
    required this.positionAnchorAt,
    required this.speed,
  });

  String? sourceUri;
  int positionMs;
  bool playing;
  bool visible;
  DateTime? positionAnchorAt;
  double speed;

  int get effectivePositionMs {
    return effectivePositionMsAt(DateTime.now());
  }

  int effectivePositionMsAt(DateTime now) {
    final anchor = positionAnchorAt;
    final elapsed =
        playing && anchor != null ? now.difference(anchor) : Duration.zero;
    return estimatePlaybackPositionMs(
      positionMs: positionMs,
      elapsed: elapsed,
      speed: speed,
    );
  }
}

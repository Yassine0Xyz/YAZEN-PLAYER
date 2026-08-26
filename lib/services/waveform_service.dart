import 'dart:io';

import 'package:just_waveform/just_waveform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_track.dart';

/// Extracts a compact waveform once and reuses it on later player opens.
///
/// YouTube streams do not expose a seekable local file until they are cached, so
/// the visualizer uses a lightweight fallback for those tracks.
class WaveformService {
  WaveformService({Directory? cacheDirectory})
      : _cacheDirectory = cacheDirectory;

  final Directory? _cacheDirectory;

  Future<Waveform?> load(MediaTrack track) async {
    final uri = track.uri;
    if (!track.isLocal || uri == null || uri.scheme != 'file') return null;

    final audioFile = File(uri.toFilePath());
    if (!await audioFile.exists()) return null;

    final directory = _cacheDirectory ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'waveforms',
          ),
        );
    if (!await directory.exists()) await directory.create(recursive: true);

    final waveFile = File(p.join(directory.path, '${_cacheKey(track)}.wave'));
    if (await waveFile.exists()) {
      try {
        return await JustWaveform.parse(waveFile);
      } catch (_) {
        try {
          await waveFile.delete();
        } catch (_) {}
      }
    }

    try {
      Waveform? waveform;
      await for (final progress in JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: waveFile,
        zoom: const WaveformZoom.pixelsPerSecond(90),
      )) {
        waveform = progress.waveform ?? waveform;
      }
      return waveform;
    } catch (_) {
      return null;
    }
  }

  String _cacheKey(MediaTrack track) {
    var hash = 17;
    for (final codeUnit in track.id.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + codeUnit);
    }
    return '${hash.abs()}-${track.id.length}';
  }
}

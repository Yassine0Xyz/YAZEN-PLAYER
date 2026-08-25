import 'package:flutter_test/flutter_test.dart';

import 'package:yazen/models/download_item.dart';

void main() {
  test('round-trips a completed download record', () {
    final original = DownloadItem(
      id: 'abc-classic',
      videoId: 'abc',
      title: 'A title',
      artist: 'An artist',
      kind: DownloadKind.classicAudio,
      qualityLabel: 'Original audio',
      extension: 'm4a',
      status: DownloadStatus.completed,
      createdAt: DateTime.utc(2026, 8, 25, 12),
      filePath: '/tmp/a.m4a',
      totalBytes: 2048,
      downloadedBytes: 2048,
      progressPercent: 100,
      backgroundTaskId: 'task-123',
    );

    final decoded = DownloadItem.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.kind, DownloadKind.classicAudio);
    expect(decoded.status, DownloadStatus.completed);
    expect(decoded.progress, 1);
    expect(decoded.filePath, '/tmp/a.m4a');
    expect(decoded.progressPercent, 100);
    expect(decoded.backgroundTaskId, 'task-123');
  });

  test('reports unknown progress when the source has no content length', () {
    final item = DownloadItem(
      id: 'abc-mp3',
      videoId: 'abc',
      title: 'A title',
      artist: 'An artist',
      kind: DownloadKind.mp3Audio,
      qualityLabel: 'MP3 · best bitrate',
      extension: 'mp3',
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );

    expect(item.progress, isNull);
    expect(item.progressPercent, isNull);
  });

  test('keeps downloader percentage separate from byte progress', () {
    final item = DownloadItem(
      id: 'abc-classic',
      videoId: 'abc',
      title: 'A title',
      artist: 'An artist',
      kind: DownloadKind.classicAudio,
      qualityLabel: 'Original audio',
      extension: 'm4a',
      status: DownloadStatus.paused,
      createdAt: DateTime.now(),
      progressPercent: 42,
      backgroundTaskId: 'task-456',
    );

    expect(item.progress, isNull);
    expect(item.progressPercent, 42);
    expect(DownloadItem.fromJson(item.toJson()).backgroundTaskId, 'task-456');
  });
}

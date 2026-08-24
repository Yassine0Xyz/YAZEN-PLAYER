import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/youtube_service.dart';

void main() {
  final service = YoutubeService();

  tearDown(() async {
    await service.dispose();
  });

  test('extracts IDs from supported YouTube URL forms', () {
    const expected = 'dQw4w9WgXcQ';
    expect(
      service.extractVideoId('https://www.youtube.com/watch?v=$expected'),
      expected,
    );
    expect(service.extractVideoId('https://youtu.be/$expected?t=12'), expected);
    expect(
      service.extractVideoId('https://www.youtube.com/shorts/$expected'),
      expected,
    );
    expect(
      service.extractVideoId('https://www.youtube.com/embed/$expected'),
      expected,
    );
    expect(service.extractVideoId(expected), expected);
  });

  test('rejects empty, malformed, and incomplete inputs', () {
    expect(service.extractVideoId(''), isNull);
    expect(service.extractVideoId('not a YouTube link'), isNull);
    expect(
      service.extractVideoId('https://www.youtube.com/watch?v=too-short'),
      isNull,
    );
  });
}

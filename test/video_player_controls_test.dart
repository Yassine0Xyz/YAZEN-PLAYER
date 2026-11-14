import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/screens/player/yazen_video_player_screen.dart';

void main() {
  group('video queue navigation', () {
    test('previous and next stay inside the selected video list', () {
      expect(videoQueueNeighborIndex(1, 3, -1), 0);
      expect(videoQueueNeighborIndex(1, 3, 1), 2);
      expect(videoQueueNeighborIndex(0, 3, -1), isNull);
      expect(videoQueueNeighborIndex(2, 3, 1), isNull);
    });

    test('invalid direction and empty lists do not navigate', () {
      expect(videoQueueNeighborIndex(0, 0, 1), isNull);
      expect(videoQueueNeighborIndex(0, 2, 0), isNull);
      expect(videoQueueNeighborIndex(-1, 2, 1), isNull);
    });
  });
}

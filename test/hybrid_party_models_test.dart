import 'package:flutter_test/flutter_test.dart';

import 'package:yazen/models/hybrid_party_models.dart';

void main() {
  test('round-trips action-only party events', () {
    final timestamp = DateTime.now().subtract(const Duration(seconds: 2));
    final event = PartyActionEvent(
      action: PartyAction.seek,
      roomCode: '123456',
      hostId: 'host',
      senderId: 'sender',
      trackId: 'youtube:abc123',
      title: 'Song',
      position: const Duration(seconds: 10),
      playing: true,
      timestamp: timestamp,
      reason: 'resync',
    );

    final decoded = PartyActionEvent.fromJson(event.toJson());
    expect(decoded.action, PartyAction.seek);
    expect(decoded.roomCode, '123456');
    expect(decoded.position, const Duration(seconds: 10));
    expect(decoded.estimatedPosition, greaterThan(const Duration(seconds: 10)));
  });

  test('rejects unknown party actions', () {
    expect(
      () => PartyActionEvent.fromJson(<String, dynamic>{'action': 'TICK'}),
      throwsA(isA<FormatException>()),
    );
  });
}

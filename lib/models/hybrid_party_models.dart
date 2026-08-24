import 'dart:convert';

enum PartyAction {
  play('PLAY'),
  pause('PAUSE'),
  seek('SEEK'),
  nextTrack('NEXT_TRACK'),
  previousTrack('PREVIOUS_TRACK'),
  trackChange('TRACK_CHANGE');

  const PartyAction(this.wireName);

  final String wireName;

  static PartyAction? fromWireName(String? value) {
    for (final action in values) {
      if (action.wireName == value?.toUpperCase()) return action;
    }
    return null;
  }
}

class PartyActionEvent {
  const PartyActionEvent({
    required this.action,
    required this.roomCode,
    required this.hostId,
    required this.senderId,
    required this.trackId,
    required this.title,
    required this.position,
    required this.playing,
    required this.timestamp,
    this.reason = 'user',
  });

  final PartyAction action;
  final String roomCode;
  final String hostId;
  final String senderId;
  final String? trackId;
  final String? title;
  final Duration position;
  final bool playing;
  final DateTime timestamp;
  final String reason;

  Duration get estimatedPosition {
    if (!playing) return position;
    final elapsed = DateTime.now().difference(timestamp);
    return position + (elapsed.isNegative ? Duration.zero : elapsed);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'party_action',
    'action': action.wireName,
    'room_code': roomCode,
    'host_id': hostId,
    'sender_id': senderId,
    'track_id': trackId,
    'title': title,
    'position_ms': position.inMilliseconds,
    'playing': playing,
    'timestamp_ms': timestamp.millisecondsSinceEpoch,
    'reason': reason,
  };

  String encode() => jsonEncode(toJson());

  factory PartyActionEvent.fromJson(Map<String, dynamic> json) {
    final action = PartyAction.fromWireName(json['action']?.toString());
    if (action == null) {
      throw const FormatException('Unknown party action.');
    }
    return PartyActionEvent(
      action: action,
      roomCode: json['room_code']?.toString() ?? '',
      hostId: json['host_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      trackId: json['track_id']?.toString(),
      title: json['title']?.toString(),
      position: Duration(
        milliseconds: int.tryParse(json['position_ms']?.toString() ?? '') ?? 0,
      ),
      playing: json['playing'] == true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(json['timestamp_ms']?.toString() ?? '') ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      reason: json['reason']?.toString() ?? 'user',
    );
  }
}

class LocalPlaybackAction {
  const LocalPlaybackAction({
    required this.action,
    required this.trackId,
    required this.title,
    required this.position,
    required this.playing,
  });

  final PartyAction action;
  final String? trackId;
  final String? title;
  final Duration position;
  final bool playing;
}

class PartyPlaybackState {
  const PartyPlaybackState({
    required this.roomCode,
    required this.hostId,
    required this.senderId,
    required this.trackId,
    required this.title,
    required this.position,
    required this.playing,
    required this.sentAt,
  });

  final String roomCode;
  final String hostId;
  final String senderId;
  final String? trackId;
  final String? title;
  final Duration position;
  final bool playing;
  final DateTime sentAt;

  Duration get estimatedPosition {
    if (!playing) return position;
    final elapsed = DateTime.now().difference(sentAt);
    return position + (elapsed.isNegative ? Duration.zero : elapsed);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'playback_state',
    'room_code': roomCode,
    'host_id': hostId,
    'sender_id': senderId,
    'track_id': trackId,
    'title': title,
    'position_ms': position.inMilliseconds,
    'playing': playing,
    'sent_at_ms': sentAt.millisecondsSinceEpoch,
  };

  String encode() => jsonEncode(toJson());

  factory PartyPlaybackState.fromJson(Map<String, dynamic> json) {
    return PartyPlaybackState(
      roomCode: json['room_code']?.toString() ?? '',
      hostId: json['host_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      trackId: json['track_id']?.toString(),
      title: json['title']?.toString(),
      position: Duration(
        milliseconds: int.tryParse(json['position_ms']?.toString() ?? '') ?? 0,
      ),
      playing: json['playing'] == true,
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(json['sent_at_ms']?.toString() ?? '') ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class NearbyParty {
  const NearbyParty({
    required this.name,
    required this.code,
    required this.host,
    required this.port,
    this.listenerCount = 0,
  });

  final String name;
  final String code;
  final String host;
  final int port;
  final int listenerCount;

  String get address => '$host:$port';
}

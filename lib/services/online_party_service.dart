import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../models/hybrid_party_models.dart';

class OnlinePartyService {
  OnlinePartyService({
    this.cluster = 'eu',
    this.authEndpoint,
    List<Map<String, String>>? configs,
  }) : pusherConfigs = List<Map<String, String>>.unmodifiable(
         configs ?? defaultPusherConfigs,
       );

  /// Configuration slots are for authorized redundancy only.
  ///
  /// Public keys are injected at build time. Pusher secrets must stay behind
  /// the presence-channel auth endpoint and must never ship in this binary.
  static const List<Map<String, String>> defaultPusherConfigs =
      <Map<String, String>>[
        <String, String>{
          'app_id': 'PUSHER_APP_ID_01',
          'key': String.fromEnvironment('PUSHER_KEY_01'),
          'cluster': 'eu',
        },
        <String, String>{
          'app_id': 'PUSHER_APP_ID_02',
          'key': String.fromEnvironment('PUSHER_KEY_02'),
          'cluster': 'eu',
        },
        <String, String>{
          'app_id': 'PUSHER_APP_ID_03',
          'key': String.fromEnvironment('PUSHER_KEY_03'),
          'cluster': 'eu',
        },
        <String, String>{
          'app_id': 'PUSHER_APP_ID_04',
          'key': String.fromEnvironment('PUSHER_KEY_04'),
          'cluster': 'eu',
        },
      ];

  final String cluster;
  final String? authEndpoint;
  final List<Map<String, String>> pusherConfigs;
  final _events = StreamController<PartyActionEvent>.broadcast();
  final _listeners = StreamController<List<String>>.broadcast();
  final _reconnects = StreamController<void>.broadcast();
  final _random = Random.secure();

  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();
  PusherChannel? _channel;
  String? _channelName;
  String? _roomCode;
  String? _clientId;
  String? _hostId;
  Map<String, String>? _selectedConfig;
  bool _isHost = false;
  final Map<String, String> _members = <String, String>{};

  Stream<PartyActionEvent> get stateStream => _events.stream;
  Stream<List<String>> get listenerStream => _listeners.stream;
  Stream<void> get reconnectStream => _reconnects.stream;
  String? get roomCode => _roomCode;
  String? get clientId => _clientId;
  Map<String, String>? get selectedConfig => _selectedConfig;
  bool get isHost => _isHost;
  bool get isConnected => _channel != null;

  Future<String> createOnlineParty({String displayName = 'Host'}) async {
    final code = _sixDigitCode();
    final clientId = _newClientId();
    await _connect(
      code: code,
      clientId: clientId,
      displayName: displayName,
      hostId: clientId,
    );
    return code;
  }

  Future<void> joinOnlineParty(
    String code, {
    String displayName = 'Listener',
  }) async {
    final normalized = code.replaceAll(RegExp(r'\D'), '');
    if (normalized.length != 6) {
      throw const FormatException(
        'Online party codes must contain six digits.',
      );
    }
    await _connect(
      code: normalized,
      clientId: _newClientId(),
      displayName: displayName,
      hostId: null,
    );
  }

  Future<void> _connect({
    required String code,
    required String clientId,
    required String displayName,
    required String? hostId,
  }) async {
    await leave();
    if (authEndpoint == null || authEndpoint!.trim().isEmpty) {
      throw StateError(
        'Pusher presence channels require a server-side auth endpoint. Configure PUSHER_AUTH_ENDPOINT.',
      );
    }
    if (pusherConfigs.isEmpty)
      throw StateError('No Pusher configurations are available.');

    final config = pusherConfigs[_random.nextInt(pusherConfigs.length)];
    final apiKey = config['key']?.trim() ?? '';
    if (apiKey.isEmpty ||
        apiKey.startsWith('PUSHER_') ||
        apiKey.startsWith('ECHO_')) {
      throw StateError(
        'Configure the selected public Pusher key through --dart-define=PUSHER_KEY_01=... .',
      );
    }

    _selectedConfig = config;
    _roomCode = code;
    _clientId = clientId;
    _hostId = hostId;
    _isHost = hostId != null;
    _channelName = 'presence-echo-party-$code';
    _members.clear();

    await _pusher.init(
      apiKey: apiKey,
      cluster: config['cluster'] ?? cluster,
      useTLS: true,
      authEndpoint: authEndpoint,
      onConnectionStateChange: (current, previous) {
        _emitMembers();
        final now = current.toString().toUpperCase();
        final before = previous.toString().toUpperCase();
        final isConnected = now == 'CONNECTED' || now.endsWith('.CONNECTED');
        final wasDisconnected =
            before == 'DISCONNECTED' || before.endsWith('.DISCONNECTED');
        final wasReconnecting =
            before == 'RECONNECTING' || before.endsWith('.RECONNECTING');
        if (isConnected && (wasDisconnected || wasReconnecting)) {
          _reconnects.add(null);
        }
      },
      onError:
          (message, errorCode, error) => _events.addError(
            StateError('Pusher error $errorCode: $message $error'),
          ),
      onSubscriptionError:
          (message, error) => _events.addError(
            StateError('Pusher subscription error: $message $error'),
          ),
      onEvent: _handleEvent,
      onMemberAdded: _handleMemberAdded,
      onMemberRemoved: _handleMemberRemoved,
    );
    _channel = await _pusher.subscribe(
      channelName: _channelName!,
      onSubscriptionSucceeded: (_, __) => _readMembersFromPresence(),
    );
    await _pusher.connect();
    _emitMembers();
  }

  void sendAction({
    required PartyAction action,
    required String? trackId,
    required String? title,
    required Duration position,
    required bool playing,
    String reason = 'user',
  }) {
    if (!_isHost ||
        _channelName == null ||
        _clientId == null ||
        _hostId == null)
      return;
    final event = PartyActionEvent(
      action: action,
      roomCode: _roomCode!,
      hostId: _hostId!,
      senderId: _clientId!,
      trackId: trackId,
      title: title,
      position: position,
      playing: playing,
      timestamp: DateTime.now(),
      reason: reason,
    );
    unawaited(
      _pusher.trigger(
        PusherEvent(
          channelName: _channelName!,
          eventName: 'client-party-action',
          data: event.encode(),
        ),
      ),
    );
  }

  void _handleEvent(PusherEvent event) {
    if (event.eventName != 'client-party-action') return;
    try {
      final payload =
          event.data is String ? jsonDecode(event.data as String) : event.data;
      if (payload is! Map<String, dynamic>) return;
      final action = PartyActionEvent.fromJson(payload);
      if (action.senderId == _clientId) return;
      if (_hostId == null && !_isHost) _hostId = action.hostId;
      if (action.hostId != _hostId) return;
      _events.add(action);
    } catch (error, stackTrace) {
      _events.addError(
        StateError('Invalid Pusher party action: $error'),
        stackTrace,
      );
    }
  }

  void _handleMemberAdded(String _, PusherMember member) {
    _members[member.userId] = member.userInfo.toString();
    _emitMembers();
  }

  void _handleMemberRemoved(String _, PusherMember member) {
    _members.remove(member.userId);
    _emitMembers();
  }

  void _readMembersFromPresence() {
    final channel = _channel;
    if (channel == null) return;
    _members
      ..clear()
      ..addAll({
        for (final entry in channel.members.entries)
          entry.key: entry.value.userInfo.toString(),
      });
    _emitMembers();
  }

  void _emitMembers() =>
      _listeners.add(List<String>.unmodifiable(_members.keys));

  String _sixDigitCode() => (100000 + _random.nextInt(900000)).toString();
  String _newClientId() =>
      'echo-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(9999)}';

  Future<void> leave() async {
    final channelName = _channelName;
    _channel = null;
    _channelName = null;
    if (channelName != null)
      await _pusher.unsubscribe(channelName: channelName);
    await _pusher.disconnect();
    _roomCode = null;
    _clientId = null;
    _hostId = null;
    _selectedConfig = null;
    _isHost = false;
    _members.clear();
    _emitMembers();
  }

  void dispose() {
    unawaited(leave());
    unawaited(_events.close());
    unawaited(_listeners.close());
    unawaited(_reconnects.close());
  }
}

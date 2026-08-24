import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../models/hybrid_party_models.dart';

class LanPartyService {
  LanPartyService({this.serviceType = '_echo-party._tcp'});

  final String serviceType;
  final _events = StreamController<PartyActionEvent>.broadcast();
  final _nearbyParties = StreamController<List<NearbyParty>>.broadcast();
  final _reconnects = StreamController<void>.broadcast();
  final _random = Random.secure();
  final Map<String, NearbyParty> _parties = <String, NearbyParty>{};
  final Set<Socket> _clients = <Socket>{};
  final Map<Socket, StringBuffer> _buffers = <Socket, StringBuffer>{};
  final _guestBuffer = StringBuffer();

  ServerSocket? _server;
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  Socket? _guestSocket;
  String? _roomCode;
  String? _clientId;
  String? _hostId;
  bool _isHost = false;
  PartyActionEvent? _lastHostEvent;

  Stream<PartyActionEvent> get stateStream => _events.stream;
  Stream<List<NearbyParty>> get nearbyPartiesStream => _nearbyParties.stream;
  Stream<void> get reconnectStream => _reconnects.stream;
  String? get roomCode => _roomCode;
  String? get clientId => _clientId;
  bool get isHost => _isHost;
  bool get isConnected => _server != null || _guestSocket != null;

  Future<String> createNearbyParty({String displayName = 'Echo Host'}) async {
    await leave();
    final code = _sixDigitCode();
    final clientId = _newClientId();
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    _server = server;
    _roomCode = code;
    _clientId = clientId;
    _hostId = clientId;
    _isHost = true;
    server.listen(_acceptClient, onError: _events.addError);

    _registration = await nsd.register(
      nsd.Service(
        name: 'Echo$code',
        type: serviceType,
        port: server.port,
        txt: <String, Uint8List?>{
          'code': Uint8List.fromList(utf8.encode(code)),
          'name': Uint8List.fromList(utf8.encode(displayName)),
        },
      ),
    );
    return code;
  }

  Future<void> startDiscovery() async {
    await stopDiscovery();
    final discovery = await nsd.startDiscovery(
      serviceType,
      ipLookupType: nsd.IpLookupType.any,
    );
    _discovery = discovery;
    discovery.addListener(() => _readDiscoveredServices(discovery));
    _readDiscoveredServices(discovery);
  }

  void _readDiscoveredServices(nsd.Discovery discovery) {
    final next = <String, NearbyParty>{};
    for (final service in discovery.services) {
      final match = RegExp(r'^Echo(\d{6})$').firstMatch(service.name ?? '');
      if (match == null || service.host == null || service.port == null)
        continue;
      final code = match.group(1)!;
      next[code] = NearbyParty(
        name: service.name ?? 'Echo Party',
        code: code,
        host: service.host!,
        port: service.port!,
      );
    }
    _parties
      ..clear()
      ..addAll(next);
    _nearbyParties.add(List<NearbyParty>.unmodifiable(_parties.values));
  }

  Future<void> joinNearbyParty(
    NearbyParty party, {
    String displayName = 'Listener',
  }) async {
    await leave();
    final socket = await Socket.connect(
      party.host,
      party.port,
      timeout: const Duration(seconds: 5),
    );
    _guestSocket = socket;
    _roomCode = party.code;
    _clientId = _newClientId();
    _hostId = null;
    _isHost = false;
    socket.write(
      '${jsonEncode(<String, dynamic>{'type': 'hello', 'client_id': _clientId, 'display_name': displayName})}\n',
    );
    socket.listen(
      _handleSocketBytes,
      onError: _events.addError,
      onDone: () {
        _guestSocket = null;
        _reconnects.add(null);
      },
    );
  }

  void _acceptClient(Socket socket) {
    _clients.add(socket);
    socket.listen(
      (bytes) => _handleHostBytes(socket, bytes),
      onError: (_, __) => _removeClient(socket),
      onDone: () => _removeClient(socket),
    );
  }

  void _handleHostBytes(Socket socket, List<int> bytes) {
    final buffer = _buffers.putIfAbsent(socket, StringBuffer.new)
      ..write(utf8.decode(bytes, allowMalformed: true));
    final lines = buffer.toString().split('\n');
    buffer
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines.where((line) => line.trim().isNotEmpty)) {
      _handleMessage(jsonDecode(line) as Map<String, dynamic>, sender: socket);
    }
  }

  void _handleSocketBytes(List<int> bytes) {
    _guestBuffer.write(utf8.decode(bytes, allowMalformed: true));
    final lines = _guestBuffer.toString().split('\n');
    _guestBuffer
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines.where((line) => line.trim().isNotEmpty)) {
      _handleMessage(jsonDecode(line) as Map<String, dynamic>);
    }
  }

  void _handleMessage(Map<String, dynamic> message, {Socket? sender}) {
    if (message['type'] == 'hello' && sender != null) {
      final anchor = _lastHostEvent;
      if (anchor != null) sender.write('${anchor.encode()}\n');
      return;
    }
    if (message['type'] != 'party_action') return;
    try {
      final event = PartyActionEvent.fromJson(message);
      if (sender != null) {
        _broadcast(event, except: sender);
      } else {
        _events.add(event);
      }
    } catch (error, stackTrace) {
      _events.addError(
        StateError('Invalid LAN party action: $error'),
        stackTrace,
      );
    }
  }

  void sendAction({
    required PartyAction action,
    required String? trackId,
    required String? title,
    required Duration position,
    required bool playing,
    String reason = 'user',
  }) {
    if (!_isHost || _roomCode == null || _clientId == null || _hostId == null)
      return;
    _broadcast(
      PartyActionEvent(
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
      ),
    );
  }

  void _broadcast(PartyActionEvent event, {Socket? except}) {
    _lastHostEvent = event;
    final payload = '${event.encode()}\n';
    for (final socket in _clients.toList()) {
      if (socket == except) continue;
      try {
        socket.write(payload);
      } catch (_) {
        _removeClient(socket);
      }
    }
  }

  void _removeClient(Socket socket) {
    _clients.remove(socket);
    _buffers.remove(socket);
    socket.destroy();
  }

  Future<void> stopDiscovery() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) await nsd.stopDiscovery(discovery);
  }

  Future<void> leave() async {
    final registration = _registration;
    if (registration != null) await nsd.unregister(registration);
    _registration = null;
    await _server?.close();
    _server = null;
    for (final socket in _clients.toList()) {
      _removeClient(socket);
    }
    await _guestSocket?.close();
    _guestSocket = null;
    _guestBuffer.clear();
    _roomCode = null;
    _clientId = null;
    _hostId = null;
    _isHost = false;
    _lastHostEvent = null;
  }

  String _sixDigitCode() => (100000 + _random.nextInt(900000)).toString();
  String _newClientId() =>
      'lan-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(9999)}';

  Future<void> dispose() async {
    await stopDiscovery();
    await leave();
    await _events.close();
    await _nearbyParties.close();
    await _reconnects.close();
  }
}

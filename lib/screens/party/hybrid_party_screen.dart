import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/hybrid_party_models.dart';
import '../../services/lan_party_service.dart';
import '../../services/online_party_service.dart';
import '../../widgets/alive_effects.dart';
import '../../widgets/echo_motion.dart';

class HybridPartyScreen extends StatefulWidget {
  const HybridPartyScreen({
    this.pusherCluster = const String.fromEnvironment(
      'PUSHER_CLUSTER',
      defaultValue: 'eu',
    ),
    this.pusherAuthEndpoint = const String.fromEnvironment(
      'PUSHER_AUTH_ENDPOINT',
    ),
    super.key,
  });

  final String pusherCluster;
  final String pusherAuthEndpoint;

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const HybridPartyScreen());

  @override
  State<HybridPartyScreen> createState() => _HybridPartyScreenState();
}

enum _PartyTransport { online, nearby }

class _HybridPartyScreenState extends State<HybridPartyScreen> {
  final _onlineCodeController = TextEditingController();
  final _nameController = TextEditingController(text: 'Listener');
  late final OnlinePartyService _online;
  late final LanPartyService _lan;
  StreamSubscription<PartyActionEvent>? _stateSubscription;
  StreamSubscription<List<String>>? _listenerSubscription;
  StreamSubscription<List<NearbyParty>>? _nearbySubscription;
  StreamSubscription<LocalPlaybackAction>? _hostPlaybackSubscription;
  StreamSubscription<Duration>? _guestPositionSubscription;
  StreamSubscription<void>? _reconnectSubscription;
  Timer? _hostPublishTimer;
  Timer? _guestResyncTimer;
  PartyActionEvent? _remoteState;
  List<String> _listeners = const <String>[];
  List<NearbyParty> _nearbyParties = const <NearbyParty>[];
  _PartyTransport? _transport;
  String? _roomCode;
  String? _error;
  bool _busy = false;
  bool _isHost = false;
  DateTime? _lastSyncAt;
  int? _syncLagMs;

  @override
  void initState() {
    super.initState();
    _online = OnlinePartyService(
      cluster: widget.pusherCluster,
      authEndpoint: widget.pusherAuthEndpoint,
    );
    _lan = LanPartyService();
    _nearbySubscription = _lan.nearbyPartiesStream.listen((parties) {
      if (mounted) setState(() => _nearbyParties = parties);
    });
    unawaited(_lan.startDiscovery());
  }

  @override
  void dispose() {
    _leave();
    _onlineCodeController.dispose();
    _nameController.dispose();
    _nearbySubscription?.cancel();
    _online.dispose();
    unawaited(_lan.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Party Mode',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: <Widget>[
          if (_transport != null)
            IconButton(
              tooltip: 'Leave party',
              onPressed: _leave,
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: _transport == null ? _buildLobby() : _buildActiveParty(),
      ),
    );
  }

  Widget _buildLobby() {
    final tokens = context.read<ThemeProvider>().tokens;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        const EchoReveal(child: _PartyHero()),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Your display name',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: EchoReveal(
                delay: const Duration(milliseconds: 90),
                child: _ModeCard(
                  icon: Icons.public_rounded,
                  eyebrow: 'ONLINE',
                  title: 'Create Online Party',
                  subtitle: 'Invite friends anywhere',
                  color: const Color(0xFF6D5CE7),
                  onTap: _busy ? null : _createOnline,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EchoReveal(
                delay: const Duration(milliseconds: 150),
                child: _ModeCard(
                  icon: Icons.wifi_tethering_rounded,
                  eyebrow: 'NEARBY',
                  title: 'Create Nearby Party',
                  subtitle: 'No internet required',
                  color: const Color(0xFF2DAA91),
                  onTap: _busy ? null : _createNearby,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionLabel(label: 'Join online'),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _onlineCodeController,
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Enter 6-digit code',
                  prefixIcon: Icon(
                    Icons.password_rounded,
                    color: tokens.textSecondary,
                  ),
                  filled: true,
                  fillColor: tokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _busy ? null : _joinOnline,
              style: IconButton.styleFrom(
                minimumSize: const Size(54, 54),
                backgroundColor: AppColors.accentStrong,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            const _SectionLabel(label: 'Discovered nearby parties'),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh nearby parties',
              onPressed: () => unawaited(_lan.startDiscovery()),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_nearbyParties.isEmpty)
          const _NearbyEmptyState()
        else
          ..._nearbyParties.map(
            (party) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NearbyPartyTile(
                party: party,
                onTap: _busy ? null : () => _joinNearby(party),
              ),
            ),
          ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActiveParty() {
    final state = _remoteState;
    final tokens = context.read<ThemeProvider>().tokens;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors:
                  _transport == _PartyTransport.online
                      ? const <Color>[Color(0xFF362B67), Color(0xFF1B1B21)]
                      : const <Color>[Color(0xFF163E3B), Color(0xFF1B1B21)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _TransportBadge(transport: _transport),
                  _SyncBadge(lastSyncAt: _lastSyncAt, lagMs: _syncLagMs),
                ],
              ),
              const SizedBox(height: 18),
              Icon(
                _transport == _PartyTransport.online
                    ? Icons.public_rounded
                    : Icons.wifi_tethering_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
              const SizedBox(height: 17),
              const Text(
                'PARTY CODE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _roomCode ?? '------',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 35,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isHost
                    ? 'You are the host'
                    : 'Following the host in real time',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ActiveTrackCard(state: state, isHost: _isHost, onResync: _resync),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.people_alt_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Text(
                '${_listeners.length} listening',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              _LivePill(active: _transport != null),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Guests should have the same track loaded locally or from the same YouTube result for timeline following to engage.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Future<void> _createOnline() async {
    await _runBusy(() async {
      final code = await _online.createOnlineParty(
        displayName: _displayName('Host'),
      );
      _transport = _PartyTransport.online;
      _roomCode = code;
      _isHost = true;
      _bindOnline();
    });
  }

  Future<void> _joinOnline() async {
    await _runBusy(() async {
      await _online.joinOnlineParty(
        _onlineCodeController.text,
        displayName: _displayName('Listener'),
      );
      _transport = _PartyTransport.online;
      _roomCode = _online.roomCode;
      _isHost = false;
      _bindOnline();
    });
  }

  Future<void> _createNearby() async {
    await _runBusy(() async {
      final code = await _lan.createNearbyParty(
        displayName: _displayName('Echo Host'),
      );
      _transport = _PartyTransport.nearby;
      _roomCode = code;
      _isHost = true;
      _bindLan();
    });
  }

  Future<void> _joinNearby(NearbyParty party) async {
    await _runBusy(() async {
      await _lan.joinNearbyParty(party, displayName: _displayName('Listener'));
      _transport = _PartyTransport.nearby;
      _roomCode = party.code;
      _isHost = false;
      _bindLan();
    });
  }

  void _bindOnline() {
    _cancelBindings();
    _stateSubscription = _online.stateStream.listen(_handleRemoteState);
    _reconnectSubscription = _online.reconnectStream.listen(
      (_) => _checkDrift(force: true),
    );
    _listenerSubscription = _online.listenerStream.listen((listeners) {
      if (mounted) setState(() => _listeners = listeners);
    });
    _startHostPublishing();
  }

  void _bindLan() {
    _cancelBindings();
    _stateSubscription = _lan.stateStream.listen(_handleRemoteState);
    _reconnectSubscription = _lan.reconnectStream.listen(
      (_) => _checkDrift(force: true),
    );
    _startHostPublishing();
  }

  void _startHostPublishing() {
    final handler = context.read<HybridMusicController>().audioHandler;
    if (_isHost) {
      _hostPlaybackSubscription = handler.partyActions.listen(
        _publishPartyAction,
      );
      _hostPublishTimer = Timer.periodic(
        const Duration(seconds: 28),
        (_) => _publishResync(),
      );
    } else {
      _guestPositionSubscription = handler.player.positionStream.listen(
        (_) => _checkDrift(),
      );
      _guestResyncTimer = Timer.periodic(
        const Duration(seconds: 28),
        (_) => _checkDrift(force: true),
      );
    }
  }

  void _publishPartyAction(LocalPlaybackAction action) {
    if (!_isHost) return;
    final send =
        _transport == _PartyTransport.online
            ? _online.sendAction
            : _lan.sendAction;
    send(
      action: action.action,
      trackId: action.trackId,
      title: action.title,
      position: action.position,
      playing: action.playing,
    );
  }

  void _publishResync() {
    if (!_isHost) return;
    final handler = context.read<HybridMusicController>().audioHandler;
    final item = handler.mediaItem.value;
    if (item == null) return;
    final send =
        _transport == _PartyTransport.online
            ? _online.sendAction
            : _lan.sendAction;
    send(
      action: PartyAction.seek,
      trackId: item.id,
      title: item.title,
      position: handler.player.position,
      playing: handler.player.playing,
      reason: 'resync',
    );
  }

  void _handleRemoteState(PartyActionEvent event) {
    if (!mounted || event.roomCode != _roomCode) return;
    setState(() {
      _remoteState = event;
      _lastSyncAt = DateTime.now();
      _syncLagMs =
          DateTime.now().difference(event.timestamp).inMilliseconds.abs();
    });
    if (_isHost) return;
    unawaited(_applyRemoteAction(event));
  }

  Future<void> _applyRemoteAction(PartyActionEvent event) async {
    final handler = context.read<HybridMusicController>().audioHandler;
    final currentId = handler.mediaItem.value?.id;
    final actionTargetsCurrentTrack =
        event.action != PartyAction.nextTrack &&
        event.action != PartyAction.previousTrack;
    if (actionTargetsCurrentTrack &&
        (event.trackId == null || event.trackId != currentId))
      return;

    switch (event.action) {
      case PartyAction.play:
        await handler.seek(event.estimatedPosition);
        await handler.play();
        break;
      case PartyAction.pause:
        await handler.seek(event.position);
        await handler.pause();
        break;
      case PartyAction.seek:
        await handler.seek(event.estimatedPosition);
        if (event.playing) {
          await handler.play();
        } else {
          await handler.pause();
        }
        break;
      case PartyAction.nextTrack:
        await handler.skipToNext();
        if (event.playing) await handler.play();
        break;
      case PartyAction.previousTrack:
        await handler.skipToPrevious();
        if (event.playing) await handler.play();
        break;
      case PartyAction.trackChange:
        await handler.seek(event.estimatedPosition);
        if (event.playing) {
          await handler.play();
        } else {
          await handler.pause();
        }
        break;
    }
  }

  DateTime? _lastDriftCorrection;

  void _checkDrift({bool force = false}) {
    if (_isHost || _remoteState == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastDriftCorrection != null &&
        now.difference(_lastDriftCorrection!) < const Duration(seconds: 3))
      return;
    final event = _remoteState!;
    final handler = context.read<HybridMusicController>().audioHandler;
    if (event.trackId == null || event.trackId != handler.mediaItem.value?.id)
      return;
    final target = event.estimatedPosition;
    final driftMs =
        (handler.player.position.inMilliseconds - target.inMilliseconds).abs();
    if (!force && driftMs <= 1500) return;
    _lastDriftCorrection = now;
    unawaited(handler.seek(target));
    if (event.playing && !handler.player.playing) {
      unawaited(handler.play());
    } else if (!event.playing && handler.player.playing) {
      unawaited(handler.pause());
    }
  }

  void _resync() {
    if (_isHost) {
      _publishResync();
    } else {
      _checkDrift(force: true);
    }
  }

  Future<void> _leave() async {
    _cancelBindings();
    await _online.leave();
    await _lan.leave();
    if (!mounted) return;
    setState(() {
      _transport = null;
      _roomCode = null;
      _remoteState = null;
      _listeners = const <String>[];
      _isHost = false;
      _lastSyncAt = null;
      _syncLagMs = null;
    });
  }

  void _cancelBindings() {
    _stateSubscription?.cancel();
    _listenerSubscription?.cancel();
    _reconnectSubscription?.cancel();
    _hostPlaybackSubscription?.cancel();
    _guestPositionSubscription?.cancel();
    _hostPublishTimer?.cancel();
    _guestResyncTimer?.cancel();
    _stateSubscription = null;
    _listenerSubscription = null;
    _reconnectSubscription = null;
    _hostPlaybackSubscription = null;
    _guestPositionSubscription = null;
    _hostPublishTimer = null;
    _guestResyncTimer = null;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayName(String fallback) =>
      _nameController.text.trim().isEmpty
          ? fallback
          : _nameController.text.trim();
}

class _PartyHero extends StatelessWidget {
  const _PartyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF2E2753), Color(0xFF1D1D22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.headphones_rounded, color: AppColors.accent, size: 34),
          SizedBox(height: 20),
          Text(
            'Same song.\nSame moment.',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.08,
              letterSpacing: -0.8,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Choose internet-wide listening or discover friends on the same Wi-Fi.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 178,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 27),
            const Spacer(),
            Text(
              eyebrow,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
  );
}

class _NearbyPartyTile extends StatelessWidget {
  const _NearbyPartyTile({required this.party, this.onTap});

  final NearbyParty party;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: AppColors.divider),
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.tealAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.wifi_tethering_rounded,
          color: Colors.tealAccent,
        ),
      ),
      title: Text(
        'Nearby Party ${party.code}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${party.host}:${party.port}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.wifi_find_rounded, color: AppColors.textSecondary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No nearby parties yet. Ask a friend to create one on this Wi-Fi.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveTrackCard extends StatelessWidget {
  const _ActiveTrackCard({
    required this.state,
    required this.isHost,
    required this.onResync,
  });

  final PartyActionEvent? state;
  final bool isHost;
  final VoidCallback onResync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Now synced',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  state?.title ??
                      (isHost
                          ? 'Start playback to broadcast'
                          : 'Waiting for host playback'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onResync,
            tooltip: 'Resync timeline',
            icon: const Icon(Icons.sync_rounded, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color =
        active
            ? Colors.greenAccent
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PulseDot(active: active, color: color, size: 6),
          const SizedBox(width: 6),
          Text(
            active ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.transport});

  final _PartyTransport? transport;

  @override
  Widget build(BuildContext context) {
    final online = transport == _PartyTransport.online;
    final color = online ? const Color(0xFFB8A7FF) : Colors.tealAccent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              online ? Icons.public_rounded : Icons.wifi_tethering_rounded,
              color: color,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              online ? 'ONLINE' : 'NEARBY LAN',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.lastSyncAt, required this.lagMs});

  final DateTime? lastSyncAt;
  final int? lagMs;

  @override
  Widget build(BuildContext context) {
    final label = lagMs == null ? 'SYNC READY' : 'SYNC ${lagMs}ms';
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PulseDot(active: lastSyncAt != null, color: color, size: 6),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

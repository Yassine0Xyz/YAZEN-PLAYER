# Echo final polish — copy-ready codeboxes

The following codeboxes are generated from the completed project sources.


## `lib/screens/settings/settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/theme/theme_tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const SettingsScreen());
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersion = '0.1.0+1';
  static const _wifiCacheKey = 'echo.settings.cache_wifi_only';
  static const _gaplessKey = 'echo.settings.gapless_playback';
  static const _notificationsKey = 'echo.settings.playback_notifications';
  static const _equalizerKey = 'echo.settings.equalizer_enabled';
  static const _surroundKey = 'echo.settings.surround_enabled';

  bool _cacheOnWifiOnly = true;
  bool _gaplessPlayback = true;
  bool _playbackNotifications = true;
  bool _equalizerEnabled = true;
  bool _surroundEnabled = false;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    final controller = context.read<HybridMusicController>();

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        children: <Widget>[
          _SectionLabel(label: 'Appearance', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: EchoThemePreset.values
                  .map(
                    (preset) => _ThemeOption(
                      preset: preset,
                      selected: theme.preset == preset,
                      onSelected: () => theme.setPreset(preset),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'Audio and playback', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: <Widget>[
                _PreferenceSwitch(
                  icon: Icons.equalizer_rounded,
                  title: 'Equalizer',
                  subtitle: 'Use the active Android audio effect profile',
                  value: _equalizerEnabled,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setEqualizer(controller, value),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.surround_sound_rounded,
                  title: '3D surround audio',
                  subtitle: 'Enable the optional native spatial effect',
                  value: _surroundEnabled,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setSurround(controller, value),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.all_inclusive_rounded,
                  title: 'Gapless playback',
                  subtitle: 'Reduce silence between queued tracks',
                  value: _gaplessPlayback,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setPreference(_gaplessKey, value, (next) => _gaplessPlayback = next),
                ),
                Divider(color: tokens.divider, height: 1),
                _PreferenceSwitch(
                  icon: Icons.notifications_none_rounded,
                  title: 'Playback notifications',
                  subtitle: 'Keep lock-screen and notification controls visible',
                  value: _playbackNotifications,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setPreference(_notificationsKey, value, (next) => _playbackNotifications = next),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'Storage', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: Column(
              children: <Widget>[
                _PreferenceSwitch(
                  icon: Icons.wifi_rounded,
                  title: 'Cache on Wi-Fi only',
                  subtitle: 'Avoid mobile-data downloads for offline audio',
                  value: _cacheOnWifiOnly,
                  enabled: _preferencesLoaded,
                  onChanged: (value) => _setPreference(_wifiCacheKey, value, (next) => _cacheOnWifiOnly = next),
                ),
                Divider(color: tokens.divider, height: 1),
                FutureBuilder<int>(
                  future: controller.audioHandler.cache.totalBytes(),
                  builder: (context, snapshot) {
                    final size = snapshot.data == null ? 'Calculating…' : _formatBytes(snapshot.data!);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sd_storage_outlined, color: tokens.accent),
                      title: const Text('YouTube audio cache', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('$size used · 512 MB maximum', style: TextStyle(color: tokens.textSecondary)),
                      trailing: TextButton(
                        onPressed: () => _clearCache(controller),
                        child: const Text('Clear'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(label: 'About Echo', tokens: tokens),
          _SettingsCard(
            tokens: tokens,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.graphic_eq_rounded, color: tokens.accent),
              title: const Text('Echo', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('Version $_appVersion', style: TextStyle(color: tokens.textSecondary)),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cacheOnWifiOnly = preferences.getBool(_wifiCacheKey) ?? true;
      _gaplessPlayback = preferences.getBool(_gaplessKey) ?? true;
      _playbackNotifications = preferences.getBool(_notificationsKey) ?? true;
      _equalizerEnabled = preferences.getBool(_equalizerKey) ?? true;
      _surroundEnabled = preferences.getBool(_surroundKey) ?? false;
      _preferencesLoaded = true;
    });
  }

  Future<void> _setPreference(
    String key,
    bool value,
    void Function(bool value) apply,
  ) async {
    apply(value);
    setState(() {});
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  Future<void> _setEqualizer(HybridMusicController controller, bool value) async {
    await controller.audioHandler.setEqualizerEnabled(value);
    await _setPreference(_equalizerKey, value, (next) => _equalizerEnabled = next);
  }

  Future<void> _setSurround(HybridMusicController controller, bool value) async {
    await controller.audioHandler.setThreeDSurroundEnabled(value);
    await _setPreference(_surroundKey, value, (next) => _surroundEnabled = next);
  }

  Future<void> _clearCache(HybridMusicController controller) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear YouTube cache?'),
        content: const Text('Completed offline audio will be removed. Your playlists and favorites will remain untouched.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear cache')),
        ],
      ),
    );
    if (shouldClear != true) return;
    await controller.audioHandler.cache.clearAll();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('YouTube cache cleared')));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.tokens});

  final String label;
  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.tokens, required this.child});

  final ThemeTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
      ),
      child: child,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.preset, required this.selected, required this.onSelected});

  final EchoThemePreset preset;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.fromPreset(preset);
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: <Color>[tokens.accentStrong, tokens.accent]),
              ),
              child: Icon(Icons.palette_outlined, color: tokens.isLight ? Colors.white : Colors.black, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(preset.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Radio<EchoThemePreset>(
              value: preset,
              groupValue: selected ? preset : null,
              onChanged: (_) => onSelected(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({required this.icon, required this.title, required this.subtitle, required this.value, required this.enabled, required this.onChanged});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: tokens.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: TextStyle(color: tokens.textSecondary)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

```

## `lib/services/local_playlist_manager.dart`

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_track.dart';

class EchoPlaylist {
  const EchoPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
  });

  final String id;
  final String name;
  final List<MediaTrack> tracks;

  EchoPlaylist copyWith({String? name, List<MediaTrack>? tracks}) {
    return EchoPlaylist(
      id: id,
      name: name ?? this.name,
      tracks: List<MediaTrack>.unmodifiable(tracks ?? this.tracks),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'tracks': tracks.map(_trackToJson).toList(growable: false),
      };

  factory EchoPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'];
    final tracks = rawTracks is List
        ? rawTracks
            .whereType<Map>()
            .map((item) => _trackFromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <MediaTrack>[];
    return EchoPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled playlist',
      tracks: List<MediaTrack>.unmodifiable(tracks),
    );
  }
}

/// Lightweight persistent storage for user-created playlists and favorites.
///
/// SharedPreferences is appropriate here because the records are small metadata
/// objects. Audio bytes remain owned by YouTubeAudioCache and are never copied
/// into the preferences file.
class LocalPlaylistManager extends ChangeNotifier {
  static const _playlistsKey = 'echo.custom_playlists.v1';
  static const _favoritesKey = 'echo.favorite_tracks.v1';

  SharedPreferences? _preferences;
  List<EchoPlaylist> _playlists = const <EchoPlaylist>[];
  List<MediaTrack> _favorites = const <MediaTrack>[];
  bool _isReady = false;

  bool get isReady => _isReady;
  List<EchoPlaylist> get playlists => _playlists;
  List<MediaTrack> get favorites => _favorites;

  bool isFavorite(MediaTrack track) => _favorites.any((item) => item.id == track.id);

  Future<void> initialize() async {
    if (_isReady) return;
    _preferences = await SharedPreferences.getInstance();
    try {
      final savedPlaylists = _preferences!.getString(_playlistsKey);
      final savedFavorites = _preferences!.getString(_favoritesKey);
      _playlists = savedPlaylists == null
          ? const <EchoPlaylist>[]
          : _decodePlaylists(savedPlaylists);
      _favorites = savedFavorites == null
          ? const <MediaTrack>[]
          : _decodeTracks(savedFavorites);
    } on FormatException {
      // A corrupt preferences payload should not block playback or library load.
      _playlists = const <EchoPlaylist>[];
      _favorites = const <MediaTrack>[];
    }
    _isReady = true;
    notifyListeners();
  }

  Future<void> toggleFavorite(MediaTrack track) async {
    _ensureReady();
    final next = List<MediaTrack>.from(_favorites);
    final existingIndex = next.indexWhere((item) => item.id == track.id);
    if (existingIndex >= 0) {
      next.removeAt(existingIndex);
    } else {
      next.add(track);
    }
    _favorites = List<MediaTrack>.unmodifiable(next);
    notifyListeners();
    await _persist();
  }

  Future<EchoPlaylist> createPlaylist(String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Playlist name cannot be empty.');
    }
    final playlist = EchoPlaylist(
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      name: normalized,
      tracks: const <MediaTrack>[],
    );
    _playlists = List<EchoPlaylist>.unmodifiable(<EchoPlaylist>[
      ..._playlists,
      playlist,
    ]);
    notifyListeners();
    await _persist();
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Playlist name cannot be empty.');
    }
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) => playlist.id == playlistId
              ? playlist.copyWith(name: normalized)
              : playlist)
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.where((playlist) => playlist.id != playlistId),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> addToPlaylist(String playlistId, MediaTrack track) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.map((playlist) {
        if (playlist.id != playlistId || playlist.tracks.any((item) => item.id == track.id)) {
          return playlist;
        }
        return playlist.copyWith(tracks: <MediaTrack>[...playlist.tracks, track]);
      }).toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.map((playlist) {
        if (playlist.id != playlistId) return playlist;
        return playlist.copyWith(
          tracks: playlist.tracks.where((track) => track.id != trackId).toList(growable: false),
        );
      }).toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> clearFavorites() async {
    _ensureReady();
    _favorites = const <MediaTrack>[];
    notifyListeners();
    await _persist();
  }

  void _ensureReady() {
    if (!_isReady) {
      throw StateError('LocalPlaylistManager.initialize() must complete before use.');
    }
  }

  Future<void> _persist() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setString(
      _playlistsKey,
      jsonEncode(_playlists.map((playlist) => playlist.toJson()).toList(growable: false)),
    );
    await preferences.setString(
      _favoritesKey,
      jsonEncode(_favorites.map(_trackToJson).toList(growable: false)),
    );
  }

  List<EchoPlaylist> _decodePlaylists(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid playlist data.');
    return List<EchoPlaylist>.unmodifiable(
      decoded
          .whereType<Map>()
          .map((item) => EchoPlaylist.fromJson(Map<String, dynamic>.from(item)))
          .where((playlist) => playlist.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  List<MediaTrack> _decodeTracks(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid favorite data.');
    return List<MediaTrack>.unmodifiable(
      decoded
          .whereType<Map>()
          .map((item) => _trackFromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
    );
  }
}

Map<String, dynamic> _trackToJson(MediaTrack track) => <String, dynamic>{
      'id': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'source': track.source.name,
      'uri': track.uri?.toString(),
      'artworkUri': track.artworkUri?.toString(),
      'durationMs': track.duration?.inMilliseconds,
      'folder': track.folder,
      'youtubeId': track.youtubeId,
      'viewCount': track.viewCount,
      'channelName': track.channelName,
    };

MediaTrack _trackFromJson(Map<String, dynamic> json) {
  final sourceName = json['source']?.toString() ?? TrackSource.local.name;
  final source = TrackSource.values.firstWhere(
    (item) => item.name == sourceName,
    orElse: () => TrackSource.local,
  );
  final durationMs = json['durationMs'];
  return MediaTrack(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Unknown title',
    artist: json['artist']?.toString() ?? 'Unknown artist',
    album: json['album']?.toString() ?? 'Unknown album',
    source: source,
    uri: _tryParseUri(json['uri']),
    artworkUri: _tryParseUri(json['artworkUri']),
    duration: durationMs is num ? Duration(milliseconds: durationMs.toInt()) : null,
    folder: json['folder']?.toString(),
    youtubeId: json['youtubeId']?.toString(),
    viewCount: (json['viewCount'] as num?)?.toInt(),
    channelName: json['channelName']?.toString(),
  );
}

Uri? _tryParseUri(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return Uri.tryParse(text);
}

```

## `lib/widgets/lyrics_view.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../services/lyrics_service.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({
    required this.lyricsFuture,
    required this.positionStream,
    this.height = 280,
    super.key,
  });

  final Future<SyncedLyrics?> lyricsFuture;
  final Stream<Duration> positionStream;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return FutureBuilder<SyncedLyrics?>(
      future: lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: height,
            child: Center(
              child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
            ),
          );
        }

        final lyrics = snapshot.data;
        if (lyrics == null) {
          return _LyricsMessage(
            message: 'No lyrics found for this track.',
            height: height,
          );
        }
        if (!lyrics.isSynced) {
          return _LyricsMessage(
            message: lyrics.plainText ?? 'Lyrics are available without timestamps.',
            height: height,
          );
        }

        return StreamBuilder<Duration>(
          stream: positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return _SyncedLyricsPanel(
              lines: lyrics.lines,
              position: position,
              height: height,
            );
          },
        );
      },
    );
  }

  static Future<void> showBottomSheet({
    required BuildContext context,
    required Future<SyncedLyrics?> lyricsFuture,
    required Stream<Duration> positionStream,
    String title = 'Lyrics',
  }) {
    final tokens = context.read<ThemeProvider>().tokens;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.background,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LyricsView(
                    lyricsFuture: lyricsFuture,
                    positionStream: positionStream,
                    height: double.infinity,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncedLyricsPanel extends StatefulWidget {
  const _SyncedLyricsPanel({required this.lines, required this.position, required this.height});

  final List<LyricLine> lines;
  final Duration position;
  final double height;

  @override
  State<_SyncedLyricsPanel> createState() => _SyncedLyricsPanelState();
}

class _SyncedLyricsPanelState extends State<_SyncedLyricsPanel> {
  final _scrollController = ScrollController();
  int? _lastScrolledIndex;

  int get _activeIndex {
    var active = 0;
    for (var index = 0; index < widget.lines.length; index++) {
      if (widget.lines[index].timestamp <= widget.position) {
        active = index;
      } else {
        break;
      }
    }
    return active;
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position || oldWidget.lines != widget.lines) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    if (!mounted || !_scrollController.hasClients) return;
    final index = _activeIndex;
    if (_lastScrolledIndex == index) return;
    _lastScrolledIndex = index;
    final target = (index * 52.0).clamp(0.0, _scrollController.position.maxScrollExtent).toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final activeIndex = _activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    return Container(
      width: double.infinity,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.divider),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 72),
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              color: active ? tokens.accent : tokens.textSecondary,
              fontSize: active ? 18 : 14,
              height: 1.45,
              fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(widget.lines[index].text, textAlign: TextAlign.center),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage({required this.message, required this.height});

  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.divider),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: tokens.textSecondary, height: 1.5),
      ),
    );
  }
}

```

## `lib/widgets/playlist_picker_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_track.dart';
import '../services/local_playlist_manager.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, MediaTrack track) async {
  final manager = context.read<LocalPlaylistManager>();
  if (!manager.isReady) return;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final playlists = manager.playlists;
      if (playlists.isEmpty) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Text('Create a custom playlist first from Library → Playlists.'),
          ),
        );
      }
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: <Widget>[
            Text('Add to playlist', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            ...playlists.map(
              (playlist) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: Text('${playlist.tracks.length}'),
                onTap: () async {
                  await manager.addToPlaylist(playlist.id, track);
                  if (context.mounted) Navigator.pop(context);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Added to ${playlist.name}')),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

```

## `lib/core/theme/theme_provider.dart`

```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'theme_tokens.dart';

export 'theme_tokens.dart' show EchoThemePreset, ThemeTokens;

class ThemeProvider extends ChangeNotifier {
  static const _presetKey = 'echo.theme_preset';

  ThemeProvider({EchoThemePreset initialPreset = EchoThemePreset.oledBlack}) : _preset = initialPreset;

  EchoThemePreset _preset;
  ImageProvider<Object>? _customBackground;

  EchoThemePreset get preset => _preset;
  ThemeTokens get tokens => ThemeTokens.fromPreset(_preset);
  ImageProvider<Object>? get customBackground => _customBackground;
  bool get hasCustomBackground => _customBackground != null;
  ThemeData get theme => buildAppTheme(tokens: tokens);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedId = preferences.getString(_presetKey);
    if (savedId == null) return;
    EchoThemePreset? savedPreset;
    for (final preset in EchoThemePreset.values) {
      if (preset.id == savedId) {
        savedPreset = preset;
        break;
      }
    }
    if (savedPreset != null && savedPreset != _preset) {
      _preset = savedPreset;
      notifyListeners();
    }
  }

  void setPreset(EchoThemePreset preset) {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    unawaited(_savePreset(preset));
  }

  Future<void> _savePreset(EchoThemePreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_presetKey, preset.id);
  }

  void setCustomBackground(ImageProvider<Object>? image) {
    if (_customBackground == image) return;
    _customBackground = image;
    notifyListeners();
  }

  void clearCustomBackground() {
    if (_customBackground == null) return;
    _customBackground = null;
    notifyListeners();
  }
}

class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeProvider>();
    final tokens = state.tokens;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: tokens.background),
        if (state.preset == EchoThemePreset.rgbRainbow)
          const RepaintBoundary(child: _RgbRainbowLayer()),
        if (state.customBackground != null) ...<Widget>[
          Positioned.fill(child: Image(image: state.customBackground!, fit: BoxFit.cover)),
          Positioned.fill(child: ColoredBox(color: tokens.scrim)),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: const SizedBox.expand(),
            ),
          ),
        ],
        child,
      ],
    );
  }
}

class _RgbRainbowLayer extends StatefulWidget {
  const _RgbRainbowLayer();

  @override
  State<_RgbRainbowLayer> createState() => _RgbRainbowLayerState();
}

class _RgbRainbowLayerState extends State<_RgbRainbowLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RgbRainbowPainter(_controller), child: const SizedBox.expand());
  }
}

class _RgbRainbowPainter extends CustomPainter {
  _RgbRainbowPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Offset.zero & size;
    final glows = <({Offset center, double radius, Color color})>[
      (center: Offset(size.width * (0.18 + math.sin(t) * 0.10), size.height * 0.18), radius: size.width * 0.62, color: const Color(0xFF7C5CFC).withValues(alpha: 0.18)),
      (center: Offset(size.width * (0.80 + math.cos(t * 0.78) * 0.11), size.height * 0.42), radius: size.width * 0.66, color: const Color(0xFF00CFFF).withValues(alpha: 0.11)),
      (center: Offset(size.width * 0.40, size.height * (0.88 + math.sin(t * 0.62) * 0.08)), radius: size.width * 0.58, color: const Color(0xFFFF3D81).withValues(alpha: 0.10)),
    ];
    for (final glow in glows) {
      paint.shader = RadialGradient(colors: <Color>[glow.color, glow.color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: glow.center, radius: glow.radius));
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RgbRainbowPainter oldDelegate) => oldDelegate.animation != animation;
}

```

## `lib/controllers/hybrid_music_controller.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/media_track.dart';
import '../services/hybrid_audio_handler.dart';
import '../services/lyrics_service.dart';
import '../services/media_library_service.dart';
import '../services/local_playlist_manager.dart';
import '../services/youtube_service.dart';

class HybridMusicController extends ChangeNotifier {
  HybridMusicController({
    required MediaLibraryService library,
    required HybridAudioHandler audioHandler,
    required LocalPlaylistManager playlistManager,
    LyricsService? lyricsService,
  })  : _library = library,
        _audioHandler = audioHandler,
        _playlistManager = playlistManager,
        _lyricsService = lyricsService ?? LyricsService() {
    _playlistManager.addListener(_onPlaylistChanged);
  }

  final MediaLibraryService _library;
  final HybridAudioHandler _audioHandler;
  final LocalPlaylistManager _playlistManager;
  final LyricsService _lyricsService;

  LibraryTab _selectedTab = LibraryTab.songs;
  List<MediaTrack> _localSongs = const <MediaTrack>[];
  List<MediaTrack> _youtubeResults = const <MediaTrack>[];
  List<ArtistModel> _artists = const <ArtistModel>[];
  List<AlbumModel> _albums = const <AlbumModel>[];
  List<PlaylistModel> _playlists = const <PlaylistModel>[];
  List<String> _folders = const <String>[];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _repeatOne = false;
  String? _errorMessage;

  LibraryTab get selectedTab => _selectedTab;
  List<MediaTrack> get localSongs => _localSongs;
  List<MediaTrack> get youtubeResults => _youtubeResults;
  List<ArtistModel> get artists => _artists;
  List<AlbumModel> get albums => _albums;
  List<PlaylistModel> get playlists => _playlists;
  List<String> get folders => _folders;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get repeatOne => _repeatOne;
  String? get errorMessage => _errorMessage;
  MediaTrack? get activeTrack => _audioHandler.activeTrack;
  HybridAudioHandler get audioHandler => _audioHandler;
  LyricsService get lyricsService => _lyricsService;
  YoutubeService get youtubeService => _audioHandler.youtubeService;
  LocalPlaylistManager get playlistManager => _playlistManager;

  List<MediaTrack> get visibleTracks {
    switch (_selectedTab) {
      case LibraryTab.videos:
        return _youtubeResults;
      case LibraryTab.playlists:
        return _localSongs;
      case LibraryTab.folders:
        return _localSongs;
      case LibraryTab.artists:
        return _localSongs;
      case LibraryTab.albums:
        return _localSongs;
      case LibraryTab.songs:
        return _localSongs;
    }
  }

  Future<void> loadLibrary() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _library.querySongs(),
        _library.queryArtists(),
        _library.queryAlbums(),
        _library.queryPlaylists(),
        _library.queryFolders(),
      ]);
      _localSongs = results[0] as List<MediaTrack>;
      _artists = results[1] as List<ArtistModel>;
      _albums = results[2] as List<AlbumModel>;
      _playlists = results[3] as List<PlaylistModel>;
      _folders = results[4] as List<String>;
    } catch (error) {
      _errorMessage = 'Unable to read the device music library: $error';
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> searchYouTube(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;

    _isSearching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _youtubeResults = await _audioHandler.searchYouTube(normalizedQuery);
      _selectedTab = LibraryTab.videos;
    } catch (error) {
      _errorMessage = 'YouTube search failed: $error';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> addToQueue(MediaTrack track) => _audioHandler.addToQueue(track);

  bool isFavorite(MediaTrack track) => _playlistManager.isFavorite(track);

  Future<void> toggleFavorite(MediaTrack track) => _playlistManager.toggleFavorite(track);

  Future<EchoPlaylist> createPlaylist(String name) => _playlistManager.createPlaylist(name);

  Future<void> addToPlaylist(String playlistId, MediaTrack track) => _playlistManager.addToPlaylist(playlistId, track);

  Future<void> cacheYouTubeTrack(
    MediaTrack track, {
    void Function(double progress)? onProgress,
  }) {
    return _audioHandler.cacheYouTubeTrack(track, onProgress: onProgress);
  }

  Future<void> playTrack(MediaTrack track) async {
    try {
      _errorMessage = null;
      notifyListeners();
      await _audioHandler.playTrack(track);
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Playback failed: $error';
      notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    if (_audioHandler.player.playing) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> toggleRepeat() async {
    _repeatOne = !_repeatOne;
    await _audioHandler.setRepeatMode(
      _repeatOne ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none,
    );
    notifyListeners();
  }

  void selectTab(LibraryTab tab) {
    if (_selectedTab == tab) return;
    _selectedTab = tab;
    notifyListeners();
  }

  void _onPlaylistChanged() {
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _playlistManager.removeListener(_onPlaylistChanged);
    _audioHandler.dispose();
    _lyricsService.dispose();
    super.dispose();
  }
}

```

## `lib/main.dart`

```dart
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/hybrid_music_controller.dart';
import 'core/theme/theme_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/hybrid_audio_handler.dart';
import 'services/media_library_service.dart';
import 'services/local_playlist_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init<HybridAudioHandler>(
    builder: HybridAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.hybrid_music_player.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    ),
  );

  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());

  final themeProvider = ThemeProvider();
  await themeProvider.load();
  final playlistManager = LocalPlaylistManager();
  await playlistManager.initialize();

  runApp(
    HybridMusicApp(
      audioHandler: audioHandler,
      themeProvider: themeProvider,
      playlistManager: playlistManager,
    ),
  );
}

class HybridMusicApp extends StatelessWidget {
  const HybridMusicApp({required this.audioHandler, required this.themeProvider, required this.playlistManager, super.key});

  final HybridAudioHandler audioHandler;
  final ThemeProvider themeProvider;
  final LocalPlaylistManager playlistManager;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocalPlaylistManager>.value(value: playlistManager),
        ChangeNotifierProvider<HybridMusicController>(
          create: (context) => HybridMusicController(
            library: MediaLibraryService(),
            audioHandler: audioHandler,
            playlistManager: context.read<LocalPlaylistManager>(),
          )..loadLibrary(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeState, _) {
          return MaterialApp(
            title: 'Echo',
            debugShowCheckedModeBanner: false,
            theme: themeState.theme,
            builder: (context, child) => ThemeBackdrop(
              child: child ?? const SizedBox.shrink(),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

```

## `lib/screens/player/full_player_screen.dart`

```dart
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/hybrid_audio_handler.dart';
import '../../services/lyrics_service.dart';
import '../../widgets/lyrics_view.dart';
import '../../widgets/alive_effects.dart';
import '../../widgets/audio_visualizer.dart';
import '../effects/equalizer_screen.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, animation, __) => const FullPlayerScreen(),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 260),
    );
  }

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  bool _showLyrics = false;
  double? _draggedPosition;
  String? _lyricsItemId;
  Future<SyncedLyrics?>? _lyricsFuture;

  Future<SyncedLyrics?> _loadLyrics(
    HybridMusicController controller,
    MediaItem item,
  ) {
    if (_lyricsItemId != item.id) {
      _lyricsItemId = item.id;
      _lyricsFuture = controller.lyricsService.loadFor(item);
    }
    return _lyricsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, mediaSnapshot) {
            final item = mediaSnapshot.data;
            if (item == null) return const _NoTrackState();

            return StreamBuilder<PlaybackState>(
              stream: handler.playbackState,
              builder: (context, playbackSnapshot) {
                final playbackState = playbackSnapshot.data;
                final isPlaying = playbackState?.playing ?? false;
                final isBuffering = playbackState?.processingState == AudioProcessingState.buffering ||
                    playbackState?.processingState == AudioProcessingState.loading;

                return Column(
                  children: <Widget>[
                    _TopBar(
                      onClose: () => Navigator.of(context).maybePop(),
                      onEffects: () => Navigator.of(context).push(EqualizerScreen.route()),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final recordSize = math.min(
                            constraints.maxWidth - 48,
                            math.max(230, constraints.maxHeight * 0.43),
                          ).toDouble();
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                            child: Column(
                              children: <Widget>[
                                Hero(
                                  tag: 'track-art-${item.id}',
                                  child: _AnimatedVinyl(
                                    artUri: item.artUri,
                                    isPlaying: isPlaying,
                                    size: recordSize,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                AudioVisualizer(
                                  playing: isPlaying,
                                  height: 32,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 18),
                                _TrackMeta(
                                  title: item.title,
                                  artist: item.artist ?? 'Unknown artist',
                                  onLyrics: () => setState(() => _showLyrics = !_showLyrics),
                                  lyricsSelected: _showLyrics,
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  child: _showLyrics
                                      ? LyricsView(
                                          key: ValueKey('lyrics-${item.id}'),
                                          lyricsFuture: _loadLyrics(controller, item),
                                          positionStream: handler.player.positionStream,
                                        )
                                      : const SizedBox(key: ValueKey('empty-lyrics')),
                                ),
                                const SizedBox(height: 22),
                                _SeekSection(
                                  handler: handler,
                                  draggedPosition: _draggedPosition,
                                  onDragStart: (value) => setState(() => _draggedPosition = value),
                                  onDragEnd: (value) async {
                                    setState(() => _draggedPosition = null);
                                    await handler.seek(Duration(milliseconds: value.round()));
                                  },
                                ),
                                const SizedBox(height: 13),
                                _TransportControls(
                                  handler: handler,
                                  isPlaying: isPlaying,
                                  isBuffering: isBuffering,
                                  onPlayPause: controller.togglePlayback,
                                ),
                                const SizedBox(height: 18),
                                _VolumeControl(handler: handler),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, required this.onEffects});

  final VoidCallback onClose;
  final VoidCallback onEffects;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Close player',
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          const Expanded(
            child: Text(
              'NOW PLAYING',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Equalizer',
            onPressed: onEffects,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

class _AnimatedVinyl extends StatefulWidget {
  const _AnimatedVinyl({
    required this.artUri,
    required this.isPlaying,
    required this.size,
  });

  final Uri? artUri;
  final bool isPlaying;
  final double size;

  @override
  State<_AnimatedVinyl> createState() => _AnimatedVinylState();
}

class _AnimatedVinylState extends State<_AnimatedVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _syncRotation();
  }

  void _syncRotation() {
    if (widget.isPlaying) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final tokens = context.read<ThemeProvider>().tokens;
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationController.value * math.pi * 2,
          child: AnimatedScale(
            scale: widget.isPlaying ? 1.0 : 0.94,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.045),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF080808),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.accentStrong.withValues(
                    alpha: widget.isPlaying ? 0.38 : 0.16,
                  ),
                  blurRadius: widget.isPlaying ? 44 : 18,
                  spreadRadius: widget.isPlaying ? 7 : 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[Color(0xFF333333), Color(0xFF080808)],
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox.expand(child: _Artwork(uri: widget.artUri)),
                  ),
                ),
                Container(
                  width: size * 0.18,
                  height: size * 0.18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accent,
                    border: Border.all(color: Colors.black, width: 5),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    if (uri == null) {
      return const ColoredBox(
        color: Color(0xFF25213A),
        child: Center(
          child: Icon(Icons.music_note_rounded, color: AppColors.accent, size: 72),
        ),
      );
    }
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFF25213A),
        child: Center(child: Icon(Icons.music_note_rounded, color: AppColors.accent, size: 72)),
      ),
    );
  }
}

class _TrackMeta extends StatelessWidget {
  const _TrackMeta({
    required this.title,
    required this.artist,
    required this.onLyrics,
    required this.lyricsSelected,
  });

  final String title;
  final String artist;
  final VoidCallback onLyrics;
  final bool lyricsSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 7),
        Text(
          artist,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: onLyrics,
          icon: Icon(lyricsSelected ? Icons.lyrics : Icons.lyrics_outlined, size: 17),
          label: Text(lyricsSelected ? 'Hide lyrics' : 'Show lyrics'),
          style: OutlinedButton.styleFrom(
            foregroundColor: lyricsSelected ? AppColors.accent : AppColors.textSecondary,
            side: BorderSide(
              color: lyricsSelected ? AppColors.accent : AppColors.divider,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

class _SeekSection extends StatelessWidget {
  const _SeekSection({
    required this.handler,
    required this.draggedPosition,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final HybridAudioHandler handler;
  final double? draggedPosition;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: handler.player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final totalMs = math.max(duration.inMilliseconds, 1).toDouble();
        return StreamBuilder<Duration>(
          stream: handler.player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final liveMs = position.inMilliseconds.clamp(0, totalMs.toInt()).toDouble();
            final value = draggedPosition ?? liveMs;
            return Column(
              children: <Widget>[
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surfaceMuted,
                    thumbColor: AppColors.textPrimary,
                    overlayColor: AppColors.accent.withValues(alpha: 0.16),
                  ),
                  child: Slider(
                    min: 0,
                    max: totalMs,
                    value: value.clamp(0, totalMs).toDouble(),
                    onChanged: duration == Duration.zero ? null : onDragStart,
                    onChangeEnd: duration == Duration.zero ? null : onDragEnd,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_formatDuration(Duration(milliseconds: value.round())), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Text(_formatDuration(duration), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.handler,
    required this.isPlaying,
    required this.isBuffering,
    required this.onPlayPause,
  });

  final HybridAudioHandler handler;
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: handler.player.shuffleModeEnabledStream,
      builder: (context, shuffleSnapshot) {
        return StreamBuilder<LoopMode>(
          stream: handler.player.loopModeStream,
          builder: (context, loopSnapshot) {
            final shuffleEnabled = shuffleSnapshot.data ?? false;
            final loopMode = loopSnapshot.data ?? LoopMode.off;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                IconButton(
                  tooltip: 'Shuffle',
                  onPressed: () => handler.setShuffleMode(
                    shuffleEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                  ),
                  icon: Icon(Icons.shuffle_rounded, color: shuffleEnabled ? AppColors.accent : AppColors.textSecondary),
                ),
                IconButton(
                  tooltip: 'Previous track',
                  onPressed: handler.skipToPrevious,
                  icon: const Icon(Icons.skip_previous_rounded, size: 31),
                ),
                BreathingGlow(
                  enabled: isPlaying && !isBuffering,
                  color: AppColors.accentStrong,
                  child: IconButton.filled(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(68, 68),
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.black,
                    ),
                    icon: isBuffering
                        ? const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                        : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 36),
                  ),
                ),
                IconButton(
                  tooltip: 'Next track',
                  onPressed: handler.skipToNext,
                  icon: const Icon(Icons.skip_next_rounded, size: 31),
                ),
                IconButton(
                  tooltip: 'Repeat mode',
                  onPressed: () => handler.setRepeatMode(_nextRepeatMode(loopMode)),
                  icon: Icon(
                    loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: loopMode == LoopMode.off ? AppColors.textSecondary : AppColors.accent,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  AudioServiceRepeatMode _nextRepeatMode(LoopMode mode) {
    return switch (mode) {
      LoopMode.off => AudioServiceRepeatMode.all,
      LoopMode.all => AudioServiceRepeatMode.one,
      LoopMode.one => AudioServiceRepeatMode.none,
    };
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.handler});

  final HybridAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: handler.player.volumeStream,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0).toDouble();
        return Row(
          children: <Widget>[
            Icon(
              volume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: AppColors.surfaceMuted,
                  inactiveTrackColor: AppColors.surfaceMuted,
                  thumbColor: AppColors.textSecondary,
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  onChanged: handler.setVolume,
                ),
              ),
            ),
            const Icon(Icons.volume_up_rounded, color: AppColors.textSecondary, size: 20),
          ],
        );
      },
    );
  }
}

class _NoTrackState extends StatelessWidget {
  const _NoTrackState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonal(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('No track is playing'),
      ),
    );
  }
}

```

## `lib/screens/library/local_media_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/shimmer_skeleton.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../home/widgets/library_tabs.dart';
import '../home/widgets/track_list_tile.dart';

class LocalMediaScreen extends StatelessWidget {
  const LocalMediaScreen({
    required this.selectedTab,
    required this.onTabSelected,
    super.key,
  });

  final LibraryTab selectedTab;
  final ValueChanged<LibraryTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    return Column(
      children: <Widget>[
        LibraryTabs(selected: selectedTab, onSelected: onTabSelected),
        const SizedBox(height: 18),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<LibraryTab>(selectedTab),
              child: _buildView(context, controller),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildView(BuildContext context, HybridMusicController controller) {
    if (controller.isLoading) return const LibraryLoadingState();

    return switch (selectedTab) {
      LibraryTab.songs => _SongsView(tracks: controller.localSongs),
      LibraryTab.artists => _ArtistsView(artists: controller.artists),
      LibraryTab.albums => _AlbumsView(albums: controller.albums),
      LibraryTab.folders => _FoldersView(
          folders: controller.folders,
          tracks: controller.localSongs,
        ),
      LibraryTab.videos => _VideosView(tracks: controller.youtubeResults),
      LibraryTab.playlists => _PlaylistsView(
          devicePlaylists: controller.playlists,
          customPlaylists: controller.playlistManager.playlists,
          favorites: controller.playlistManager.favorites,
        ),
    };
  }
}

class _SongsView extends StatelessWidget {
  const _SongsView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.library_music_outlined,
        title: 'Your library is waiting',
        subtitle: 'Music found on this device will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        final track = tracks[index];
        return TrackListTile(
          track: track,
          onTap: () => controller.playTrack(track),
          isFavorite: controller.isFavorite(track),
          onFavorite: () => controller.toggleFavorite(track),
          onAddToPlaylist: () => showAddToPlaylistSheet(context, track),
        );
      },
    );
  }
}

class _ArtistsView extends StatelessWidget {
  const _ArtistsView({required this.artists});

  final List<ArtistModel> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.person_outline_rounded,
        title: 'No artists yet',
        subtitle: 'Artists are created automatically from your local music metadata.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 178,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) => _ArtistCard(artist: artists[index]),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});

  final ArtistModel artist;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Hero(
            tag: 'artist-art-${artist.id}',
            child: ClipOval(
              child: QueryArtworkWidget(
                id: artist.id,
                type: ArtworkType.ARTIST,
                artworkWidth: 82,
                artworkHeight: 82,
                size: 240,
                nullArtworkWidget: const _EntityArtwork(icon: Icons.person_rounded, circular: true),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            artist.artist.trim().isEmpty ? 'Unknown artist' : artist.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${artist.numberOfTracks ?? 0} songs',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView({required this.albums});

  final List<AlbumModel> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.album_outlined,
        title: 'No albums yet',
        subtitle: 'Albums will appear once local audio metadata is available.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 248,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) => _AlbumCard(album: albums[index]),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final AlbumModel album;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Hero(
          tag: 'album-art-${album.id}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: QueryArtworkWidget(
              id: album.id,
              type: ArtworkType.ALBUM,
              artworkWidth: double.infinity,
              artworkHeight: 180,
              size: 600,
              nullArtworkWidget: const _EntityArtwork(icon: Icons.album_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          album.album.trim().isEmpty ? 'Unknown album' : album.album,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          '${album.artist ?? 'Unknown artist'}  •  ${album.numOfSongs} songs',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _FoldersView extends StatelessWidget {
  const _FoldersView({required this.folders, required this.tracks});

  final List<String> folders;
  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No audio folders found',
        subtitle: 'Folders containing local audio will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: folders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final folder = folders[index];
        final count = tracks.where((track) => track.folder?.endsWith(folder) ?? false).length;
        return _FolderRow(folder: folder, count: count);
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.count});

  final String folder;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: AppColors.accent.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.folder_rounded, color: AppColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('$count audio ${count == 1 ? 'file' : 'files'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _VideosView extends StatelessWidget {
  const _VideosView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.ondemand_video_rounded,
        title: 'Discover something new',
        subtitle: 'Search YouTube from Discover, then stream or cache results here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 258,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _VideoPreviewCard(
          track: track,
          onPlay: () => controller.playTrack(track),
        );
      },
    );
  }
}

class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({required this.track, required this.onPlay});

  final MediaTrack track;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Hero(
                  tag: 'track-art-${track.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: TrackArtwork(track: track, size: 320),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: _DurationBadge(duration: track.duration),
                ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(track.channelName ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final value = duration == null ? '--:--' : _formatDuration(duration!);
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.74), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView({required this.devicePlaylists, required this.customPlaylists, required this.favorites});

  final List<PlaylistModel> devicePlaylists;
  final List<EchoPlaylist> customPlaylists;
  final List<MediaTrack> favorites;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final totalItems = 1 + customPlaylists.length + devicePlaylists.length;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: totalItems + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: <Widget>[
              Expanded(child: Text('Your collections', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              FilledButton.tonalIcon(onPressed: () => _createPlaylist(context, controller), icon: const Icon(Icons.add_rounded), label: const Text('New')),
            ],
          );
        }
        if (index == 1) {
          return _CollectionCard(
            icon: Icons.favorite_rounded,
            title: 'Favorites',
            subtitle: 'Tracks you want to keep close',
            count: favorites.length,
          );
        }
        final customIndex = index - 2;
        if (customIndex < customPlaylists.length) {
          final playlist = customPlaylists[customIndex];
          return _CollectionCard(
            icon: Icons.queue_music_rounded,
            title: playlist.name,
            subtitle: 'Custom playlist',
            count: playlist.tracks.length,
            onDelete: () => controller.playlistManager.deletePlaylist(playlist.id),
          );
        }
        final deviceIndex = customIndex - customPlaylists.length;
        final playlist = devicePlaylists[deviceIndex];
        return _CollectionCard(
          icon: Icons.library_music_rounded,
          title: playlist.playlist,
          subtitle: 'Device playlist',
          count: playlist.numOfSongs,
        );
      },
    );
  }

  Future<void> _createPlaylist(BuildContext context, HybridMusicController controller) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(controller: nameController, autofocus: true, textInputAction: TextInputAction.done, decoration: const InputDecoration(hintText: 'Playlist name')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Create')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty) return;
    await controller.createPlaylist(name);
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.icon, required this.title, required this.subtitle, required this.count, this.onDelete});

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: <Widget>[
          _EntityArtwork(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text('$count songs', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          if (onDelete != null)
            IconButton(tooltip: 'Delete playlist', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
    );
  }
}

class _EntityArtwork extends StatelessWidget {
  const _EntityArtwork({required this.icon, this.circular = false});

  final IconData icon;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF2B264B), Color(0xFF6955C6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: AppColors.accent, size: 34),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: AppColors.textSecondary),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: AppColors.divider),
    boxShadow: <BoxShadow>[
      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
    ],
  );
}

```

## `lib/screens/home/widgets/track_list_tile.dart`

```dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/media_track.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({required this.track, required this.onTap, this.isFavorite = false, this.onFavorite, this.onAddToPlaylist, super.key});

  final MediaTrack track;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: <Widget>[
                TrackArtwork(track: track, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${track.artist}  •  ${track.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatDuration(track.duration), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                if (onAddToPlaylist != null)
                  IconButton(
                    tooltip: 'Add to playlist',
                    onPressed: onAddToPlaylist,
                    icon: const Icon(Icons.playlist_add_rounded, color: AppColors.textSecondary),
                  ),
                if (onFavorite != null)
                  IconButton(
                    tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                    onPressed: onFavorite,
                    icon: Icon(isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFavorite ? Colors.redAccent : AppColors.textSecondary),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Play ${track.title}',
                  onPressed: onTap,
                  icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({required this.track, required this.size, super.key});

  final MediaTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = _ArtworkFallback(size: size, source: track.source);
    if (track.isLocal) {
      final localId = int.tryParse(track.id);
      if (localId == null) return fallback;
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: QueryArtworkWidget(
          id: localId,
          type: ArtworkType.AUDIO,
          artworkWidth: size,
          artworkHeight: size,
          size: 300,
          quality: 100,
          nullArtworkWidget: fallback,
        ),
      );
    }

    final artwork = track.artworkUri;
    if (artwork == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.network(
        artwork.toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.size, required this.source});

  final double size;
  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          colors: source == TrackSource.youtube
              ? const <Color>[Color(0xFF6F1D3A), Color(0xFFEF476F)]
              : const <Color>[Color(0xFF24213D), Color(0xFF7C5CFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        source == TrackSource.youtube ? Icons.ondemand_video_rounded : Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.9),
        size: size * 0.45,
      ),
    );
  }
}

```

## `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

    <application
        android:label="Echo"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="false">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            android:stopWithTask="false">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>

```

## `android/app/src/main/res/values/styles.xml`

```xml
<resources>
    <style name="LaunchTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:fontFamily">sans</item>
        <item name="android:colorAccent">#7C5CFC</item>
    </style>
    <style name="NormalTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>

```

## `android/app/src/main/kotlin/com/example/hybrid_music_player/MainActivity.kt`

```kotlin
package com.example.hybrid_music_player

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()

```

## References

[1]: https://pub.dev/packages/shared_preferences "shared_preferences on pub.dev"
[2]: https://pub.dev/packages/audio_service "audio_service on pub.dev"
[3]: https://developer.android.com/develop/background-work/services/fgs "Android foreground services"

# Echo YouTube integration — copy-ready Dart codeboxes

These codeboxes are generated from the validated project sources.


## `lib/services/youtube_service.dart`

```dart
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/media_track.dart';

class YoutubeVideoResult {
  const YoutubeVideoResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    this.viewCount,
  });

  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final Uri? thumbnailUrl;
  final int? viewCount;

  MediaTrack toMediaTrack() {
    return MediaTrack.fromYoutube(
      id: videoId,
      title: title,
      artist: author,
      duration: duration,
      artworkUri: thumbnailUrl,
      viewCount: viewCount,
      channelName: author,
    );
  }
}

/// Source-only YouTube integration. It does not require an API key or backend.
///
/// The service is intentionally kept separate from playback so search, metadata
/// mapping, and URL extraction can be tested or replaced independently.
class YoutubeService {
  YoutubeService({YoutubeExplode? client}) : _client = client ?? YoutubeExplode();

  final YoutubeExplode _client;
  bool _closed = false;

  Future<List<YoutubeVideoResult>> searchVideos(String query, {int limit = 20}) async {
    _ensureOpen();
    final normalized = query.trim();
    if (normalized.isEmpty) return const <YoutubeVideoResult>[];
    if (limit <= 0) return const <YoutubeVideoResult>[];

    final results = await _client.search.search(normalized);
    return results.whereType<Video>().take(limit).map(_mapVideo).toList(growable: false);
  }

  Future<Uri> getAudioStreamUrl(String videoId) async {
    _ensureOpen();
    final normalizedId = videoId.trim();
    if (normalizedId.isEmpty) throw const FormatException('A YouTube video ID is required.');

    final manifest = await _client.videos.streams.getManifest(normalizedId);
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) {
      throw StateError('No audio-only stream was found for YouTube video $normalizedId.');
    }
    return audioStreams.withHighestBitrate().url;
  }

  Future<YoutubeVideoResult> getVideo(String videoId) async {
    _ensureOpen();
    final video = await _client.videos.get(videoId.trim());
    return _mapVideo(video);
  }

  YoutubeVideoResult _mapVideo(Video video) {
    return YoutubeVideoResult(
      videoId: video.id.value,
      title: video.title.trim().isEmpty ? 'Untitled video' : video.title,
      author: video.author.trim().isEmpty ? 'Unknown channel' : video.author,
      duration: video.duration,
      thumbnailUrl: Uri.tryParse(video.thumbnails.highResUrl),
      viewCount: video.engagement.viewCount,
    );
  }

  void _ensureOpen() {
    if (_closed) throw StateError('YoutubeService has already been disposed.');
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

```

## `lib/services/hybrid_audio_handler.dart`

```dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/hybrid_party_models.dart';
import '../models/media_track.dart';
import 'youtube_audio_cache.dart';
import 'youtube_service.dart';

/// Single source of truth for audio playback, notification controls, and queue metadata.
///
/// The handler resolves YouTube URLs just before playback because stream URLs are
/// temporary, then stores the resulting audio bytes through [YouTubeAudioCache].
class HybridAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  factory HybridAudioHandler({
    AudioPlayer? player,
    YoutubeExplode? youtube,
    YoutubeService? youtubeService,
    YouTubeAudioCache? cache,
    AndroidEqualizer? equalizer,
  }) {
    final resolvedEqualizer = equalizer ?? AndroidEqualizer();
    final resolvedPlayer = player ??
        AudioPlayer(
          audioPipeline: AudioPipeline(
            androidAudioEffects: <AndroidAudioEffect>[resolvedEqualizer],
          ),
        );
    return HybridAudioHandler._(
      player: resolvedPlayer,
      youtubeService: youtubeService ?? YoutubeService(client: youtube),
      cache: cache ?? YouTubeAudioCache(),
      equalizer: resolvedEqualizer,
    );
  }

  HybridAudioHandler._({
    required AudioPlayer player,
    required YoutubeService youtubeService,
    required YouTubeAudioCache cache,
    required AndroidEqualizer equalizer,
  })  : _player = player,
        _youtubeService = youtubeService,
        _cache = cache,
        _equalizer = equalizer {
    _subscriptions.add(
      _player.playbackEventStream.listen((_) => _broadcastPlaybackState()),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((_) => _broadcastPlaybackState()),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen(_onCurrentIndexChanged),
    );
  }

  final AudioPlayer _player;
  final YoutubeService _youtubeService;
  final YouTubeAudioCache _cache;
  final AndroidEqualizer _equalizer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<MediaTrack> _queueTracks = <MediaTrack>[];
  final _partyActions = StreamController<LocalPlaybackAction>.broadcast();
  static const _effectsChannel = MethodChannel('echo/audio_effects');
  bool _threeDSurroundEnabled = false;

  MediaTrack? _activeTrack;
  bool _isDisposed = false;

  AudioPlayer get player => _player;
  MediaTrack? get activeTrack => _activeTrack;
  YouTubeAudioCache get cache => _cache;
  YoutubeService get youtubeService => _youtubeService;
  AndroidEqualizer get equalizer => _equalizer;
  bool get threeDSurroundEnabled => _threeDSurroundEnabled;
  Stream<LocalPlaybackAction> get partyActions => _partyActions.stream;

  Future<void> setEqualizerEnabled(bool enabled) => _equalizer.setEnabled(enabled);

  Future<void> setThreeDSurroundEnabled(bool enabled) async {
    _threeDSurroundEnabled = enabled;
    try {
      await _effectsChannel.invokeMethod<void>('setVirtualizerEnabled', <String, dynamic>{
        'enabled': enabled,
        'audioSessionId': _player.androidAudioSessionId,
      });
    } on MissingPluginException {
      // The native virtualizer is optional. The EQ remains fully functional
      // when the platform implementation is not included in a build flavor.
    }
  }

  Future<void> playTrack(MediaTrack track, {bool autoPlay = true}) async {
    final item = track.toMediaItem();
    final source = await _resolveSource(track, item);
    _queueTracks
      ..clear()
      ..add(track);
    _activeTrack = track;
    mediaItem.add(item);
    queue.add(<MediaItem>[item]);
    await _player.setAudioSource(source);
    _emitPartyAction(PartyAction.trackChange);
    if (autoPlay) await play();
  }

  Future<void> addToQueue(MediaTrack track) async {
    final item = track.toMediaItem();
    final source = await _resolveSource(track, item);
    await _player.addAudioSource(source);
    _queueTracks.add(track);
    queue.add(<MediaItem>[...queue.value, item]);
  }

  Future<File> cacheYouTubeTrack(
    MediaTrack track, {
    void Function(double progress)? onProgress,
  }) async {
    final youtubeId = track.youtubeId;
    if (!track.isLocal && youtubeId != null && youtubeId.isNotEmpty) {
      if (await _cache.hasComplete(youtubeId)) return _cache.cachedFile(youtubeId);
      final streamUri = await _resolveYoutubeStreamUri(youtubeId);
      return _cache.downloadToCache(
        videoId: youtubeId,
        streamUri: streamUri,
        onProgress: onProgress,
      );
    }
    throw StateError('Only YouTube tracks can be downloaded to the offline cache.');
  }

  Future<Uri> _resolveYoutubeStreamUri(String youtubeId) => _youtubeService.getAudioStreamUrl(youtubeId);

  Future<AudioSource> _resolveSource(MediaTrack track, MediaItem item) async {
    if (track.isLocal) {
      final uri = track.uri;
      if (uri == null) throw StateError('Local track is missing a file URI.');
      return AudioSource.uri(uri, tag: item);
    }

    final youtubeId = track.youtubeId;
    if (youtubeId == null || youtubeId.isEmpty) {
      throw StateError('YouTube track is missing a video ID.');
    }

    // Skip YouTube entirely when a completed local copy is available. This is
    // the offline-resilience path and avoids refreshing an expired stream URL.
    if (await _cache.hasComplete(youtubeId)) {
      final cachedFile = await _cache.cachedFile(youtubeId);
      return AudioSource.uri(Uri.file(cachedFile.path), tag: item);
    }

    final streamUri = await _resolveYoutubeStreamUri(youtubeId);
    return _cache.sourceFor(
      videoId: youtubeId,
      streamUri: streamUri,
      tag: item,
    );
  }

  Future<List<MediaTrack>> searchYouTube(String query, {int limit = 20}) async {
    final results = await _youtubeService.searchVideos(query, limit: limit);
    return results.map((result) => result.toMediaTrack()).toList(growable: false);
  }

  @override
  Future<void> play() async {
    await _player.play();
    _emitPartyAction(PartyAction.play);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _emitPartyAction(PartyAction.pause);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _emitPartyAction(PartyAction.seek);
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      _emitPartyAction(PartyAction.nextTrack);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
    _emitPartyAction(PartyAction.previousTrack);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(shuffleMode != AudioServiceShuffleMode.none);
    await super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
    await super.setRepeatMode(repeatMode);
  }

  void _onCurrentIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _queueTracks.length) return;
    final track = _queueTracks[index];
    _activeTrack = track;
    mediaItem.add(track.toMediaItem());
  }

  void _emitPartyAction(PartyAction action) {
    final item = mediaItem.value;
    if (_isDisposed || item == null) return;
    _partyActions.add(
      LocalPlaybackAction(
        action: action,
        trackId: item.id,
        title: item.title,
        position: _player.position,
        playing: _player.playing,
      ),
    );
  }

  void _broadcastPlaybackState() {
    if (_isDisposed) return;

    final processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0],
        processingState: processingState,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex ?? 0,
      ),
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _partyActions.close();
    await _youtubeService.dispose();
    await _cache.dispose();
    await _player.dispose();
  }
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
import '../services/youtube_service.dart';

class HybridMusicController extends ChangeNotifier {
  HybridMusicController({
    required MediaLibraryService library,
    required HybridAudioHandler audioHandler,
    LyricsService? lyricsService,
  })  : _library = library,
        _audioHandler = audioHandler,
        _lyricsService = lyricsService ?? LyricsService();

  final MediaLibraryService _library;
  final HybridAudioHandler _audioHandler;
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

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _audioHandler.dispose();
    _lyricsService.dispose();
    super.dispose();
  }
}

```

## `lib/screens/discover/youtube_search_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../widgets/shimmer_skeleton.dart';

class YoutubeSearchScreen extends StatefulWidget {
  const YoutubeSearchScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, animation, __) => const YoutubeSearchScreen(),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 280),
    );
  }

  @override
  State<YoutubeSearchScreen> createState() => _YoutubeSearchScreenState();
}

class _YoutubeSearchScreenState extends State<YoutubeSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _downloadProgress = <String, double>{};
  final _cachedIds = <String>{};
  final _queuedIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HybridMusicController>();
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('Discover', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: 'Close discover',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(child: _SearchHeader(controller: controller, searchController: _searchController, focusNode: _focusNode, onSearch: _search)),
            ),
            SliverToBoxAdapter(child: _TrendingChips(onSelected: _search)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              sliver: SliverToBoxAdapter(child: _ResultHeader(controller: controller)),
            ),
            if (controller.isSearching)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(child: _DiscoverLoadingState()),
              )
            else if (controller.youtubeResults.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: _DiscoverEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.builder(
                  itemCount: controller.youtubeResults.length,
                  itemBuilder: (context, index) {
                    final track = controller.youtubeResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _YoutubeResultCard(
                        track: track,
                        cached: _cachedIds.contains(track.id),
                        progress: _downloadProgress[track.id],
                        queued: _queuedIds.contains(track.id),
                        onStream: () => controller.playTrack(track),
                        onQueue: () => _queueTrack(track),
                        onCache: () => _cacheTrack(track),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _focusNode.unfocus();
    await context.read<HybridMusicController>().searchYouTube(normalized);
  }

  Future<void> _queueTrack(MediaTrack track) async {
    try {
      await context.read<HybridMusicController>().addToQueue(track);
      if (!mounted) return;
      setState(() => _queuedIds.add(track.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${track.title} added to queue')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not queue ${track.title}: $error')));
    }
  }

  Future<void> _cacheTrack(MediaTrack track) async {
    if (_downloadProgress.containsKey(track.id) || _cachedIds.contains(track.id)) return;
    setState(() => _downloadProgress[track.id] = 0);
    try {
      await context.read<HybridMusicController>().cacheYouTubeTrack(
        track,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress[track.id] = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(track.id);
        _cachedIds.add(track.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${track.title} is available offline')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(track.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cache ${track.title}: $error')),
      );
    }
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller, required this.searchController, required this.focusNode, required this.onSearch});

  final HybridMusicController controller;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Find your next favorite', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 6),
        Text('Stream instantly or keep it close for offline listening.', style: TextStyle(color: tokens.textSecondary)),
        const SizedBox(height: 20),
        TextField(
          controller: searchController,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: onSearch,
          style: TextStyle(color: tokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search YouTube',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.isSearching
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(onPressed: () => onSearch(searchController.text), icon: const Icon(Icons.arrow_forward_rounded)),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

class _TrendingChips extends StatelessWidget {
  const _TrendingChips({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _queries = <String>[
    'Chill electronic mix',
    'Lo-fi beats',
    'Deep focus music',
    'Acoustic covers',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _queries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => ActionChip(
          onPressed: () => onSelected(_queries[index]),
          avatar: Icon(Icons.auto_awesome_rounded, size: 15, color: tokens.accent),
          label: Text(_queries[index]),
          backgroundColor: tokens.surface,
          side: BorderSide(color: tokens.divider),
          labelStyle: TextStyle(color: tokens.textSecondary, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.controller});

  final HybridMusicController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.youtubeResults.length;
    return Row(
      children: <Widget>[
        Text(count == 0 ? 'Trending for you' : 'Search results', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        if (count > 0) Text('$count', style: TextStyle(color: context.read<ThemeProvider>().tokens.textSecondary)),
      ],
    );
  }
}

class _YoutubeResultCard extends StatelessWidget {
  const _YoutubeResultCard({required this.track, required this.cached, required this.progress, required this.queued, required this.onStream, required this.onQueue, required this.onCache});

  final MediaTrack track;
  final bool cached;
  final double? progress;
  final bool queued;
  final VoidCallback onStream;
  final VoidCallback onQueue;
  final VoidCallback onCache;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
        boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Hero(
            tag: 'track-art-${track.id}',
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _Thumbnail(uri: track.artworkUri),
                  Positioned(right: 12, bottom: 12, child: _DurationBadge(duration: track.duration)),
                  Positioned(left: 12, bottom: 12, child: _YouTubeBadge()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.2)),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(Icons.account_circle_outlined, size: 17, color: tokens.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(track.channelName ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w700))),
                    if (track.viewCount != null) Text(_formatViews(track.viewCount!), style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onStream,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Instant Stream'),
                        style: FilledButton.styleFrom(backgroundColor: tokens.accentStrong, foregroundColor: tokens.isLight ? Colors.white : Colors.black, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      ),
                    ),
                    const SizedBox(width: 9),
                    IconButton.filledTonal(
                      tooltip: queued ? 'Already queued' : 'Add to queue',
                      onPressed: queued ? null : onQueue,
                      icon: Icon(queued ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded, size: 19),
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: queued ? Colors.greenAccent : tokens.textPrimary),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: cached || progress != null ? null : onCache,
                        icon: progress != null
                            ? SizedBox.square(dimension: 17, child: CircularProgressIndicator(value: progress == 0 ? null : progress, strokeWidth: 2))
                            : Icon(cached ? Icons.check_rounded : Icons.download_for_offline_rounded, size: 18),
                        label: Text(cached ? 'Offline ready' : progress != null ? '${(progress! * 100).round()}%' : 'Download'),
                        style: OutlinedButton.styleFrom(foregroundColor: cached ? Colors.greenAccent : tokens.textPrimary, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M views';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K views';
    return '$views views';
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    if (uri == null) return const _ThumbnailFallback();
    return Image.network(uri.toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _ThumbnailFallback());
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: <Color>[tokens.surfaceMuted, tokens.accentStrong], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(child: Icon(Icons.ondemand_video_rounded, color: tokens.accent, size: 42)),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final value = duration == null ? 'LIVE' : '${duration!.inMinutes}:${duration!.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.76), borderRadius: BorderRadius.circular(8)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
    );
  }
}

class _YouTubeBadge extends StatelessWidget {
  const _YouTubeBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
      child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text('YOUTUBE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.7))),
    );
  }
}

class _DiscoverLoadingState extends StatelessWidget {
  const _DiscoverLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(3, (_) => const Padding(padding: EdgeInsets.only(bottom: 16), child: ShimmerSkeleton(width: double.infinity, height: 280, radius: 24))),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.explore_outlined, size: 58, color: tokens.textSecondary),
            SizedBox(height: 18),
            Text('Search for a mood', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Try one of the curated topics above or search for an artist, album, or mix.', textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

```

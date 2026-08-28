import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'controllers/hybrid_music_controller.dart';
import 'core/theme/theme_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/hybrid_audio_handler.dart';
import 'services/media_library_service.dart';
import 'services/local_playlist_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final HybridAudioHandler audioHandler;
  try {
    audioHandler = await AudioService.init<HybridAudioHandler>(
      builder: HybridAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.yazen.channel.audio',
        androidNotificationChannelName: 'Music playback',
        androidNotificationIcon: 'drawable/yazen_notification_icon',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
  } catch (_) {
    // Keep the first frame available even if the media-service plugin is not
    // ready on a fresh install; the handler still supports foreground audio.
    audioHandler = HybridAudioHandler();
  }

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await audioHandler.configureAudioSession(session);
  } catch (_) {
    // Audio session configuration is optional for showing the first frame.
    // Playback can configure itself later when the platform becomes ready.
  }

  final themeProvider = ThemeProvider();
  try {
    await themeProvider.load();
  } catch (_) {
    // Use the default theme when first-run preferences are unavailable.
  }
  final playlistManager = LocalPlaylistManager();
  try {
    await playlistManager.initialize();
  } catch (_) {
    // Start with empty local collections when persisted data is unreadable.
  }
  try {
    await audioHandler.restoreLastPlayback();
  } catch (_) {
    // A stale or unavailable file must never block the first app frame.
  }

  runApp(
    HybridMusicApp(
      audioHandler: audioHandler,
      themeProvider: themeProvider,
      playlistManager: playlistManager,
    ),
  );
}

class HybridMusicApp extends StatelessWidget {
  const HybridMusicApp({
    required this.audioHandler,
    required this.themeProvider,
    required this.playlistManager,
    super.key,
  });

  final HybridAudioHandler audioHandler;
  final ThemeProvider themeProvider;
  final LocalPlaylistManager playlistManager;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocalPlaylistManager>.value(
          value: playlistManager,
        ),
        ChangeNotifierProvider<HybridMusicController>(
          create:
              (context) => HybridMusicController(
                library: MediaLibraryService(),
                audioHandler: audioHandler,
                playlistManager: context.read<LocalPlaylistManager>(),
              )..loadLibrary(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeState, _) {
          return MaterialApp(
            title: 'YAZEN',
            debugShowCheckedModeBanner: false,
            theme: themeState.theme,
            builder:
                (context, child) =>
                    ThemeBackdrop(child: child ?? const SizedBox.shrink()),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

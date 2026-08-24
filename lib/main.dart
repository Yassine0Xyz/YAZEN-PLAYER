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

  final audioHandler = await AudioService.init<HybridAudioHandler>(
    builder: HybridAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId:
          'com.example.hybrid_music_player.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());
  await audioHandler.configureAudioSession(session);

  final themeProvider = ThemeProvider();
  await themeProvider.load();
  final playlistManager = LocalPlaylistManager();
  await playlistManager.initialize();
  await audioHandler.restoreLastPlayback();

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
            title: 'Echo',
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

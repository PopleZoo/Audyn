import 'package:audio_service/audio_service.dart';
import 'package:audyn_prototype/providers/player_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'audio_handler.dart';
import 'core/download/download_manager.dart';
import 'core/playlist/playlist_manager.dart';
import 'core/playback/playback_manager.dart';
import 'features/home/playlists_overview_screen.dart';

// 🔑 Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // Initialize core services
  final playlistManager = await PlaylistManager.create();
  final downloadManager = DownloadManager();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.audyn_prototype.channel.audio',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );
  final audioHandler = await initAudioService();
  final playbackManager = PlaybackManager(audioHandler);


  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaylistManager>.value(value: playlistManager),
        ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
        ChangeNotifierProvider<PlaybackManager>.value(value: playbackManager),
        ChangeNotifierProvider<PlayerUIState>(create: (_) => PlayerUIState()),
      ],
      child: const AudynApp(),
    ),
  );
}

class AudynApp extends StatelessWidget {
  const AudynApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Audyn Prototype',
      theme: ThemeData.dark(),
      home: const PlaylistsOverviewScreen(),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'audio_handler.dart';
import 'core/download/download_manager.dart';
import 'core/playlist/playlist_manager.dart';
import 'core/playback/playback_manager.dart';
import 'features/home/playlists_overview_screen.dart';
import 'providers/player_ui_state.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.audyn.channel.audio',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );

  await _requestNotificationPermissionIfNeeded();

  final playlistManager = await PlaylistManager.create();
  final downloadManager = DownloadManager();
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

Future<void> _requestNotificationPermissionIfNeeded() async {
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isRestricted) {
      await Permission.notification.request();
    }
  }
}

class AudynApp extends StatelessWidget {
  const AudynApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Audyn',
      theme: ThemeData.dark(),
      home: const PlaylistsOverviewScreen(),
    );
  }
}

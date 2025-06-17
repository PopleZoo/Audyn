import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio_handler.dart';
import 'core/playback/playback_manager.dart';
import 'core/playlist/playlist_manager.dart';
import 'features/home/playlists_overview_screen.dart';
import 'features/home/search_screen.dart';
import 'features/home/download_screen.dart';
import 'features/player/Bottom_player.dart';

// Global navigator key if needed
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AppWithPlayer extends StatefulWidget {
  const AppWithPlayer({Key? key}) : super(key: key);

  @override
  State<AppWithPlayer> createState() => _AppWithPlayerState();
}

class _AppWithPlayerState extends State<AppWithPlayer> {
  int _selectedIndex = 0;

  static final List<Widget> _pages = [
    const PlaylistsOverviewScreen(),
    const BrowseScreen(),
    const DownloadScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = context.watch<PlaybackManager>();

    return Scaffold(
      body: Stack(
        children: [
          _pages[_selectedIndex],
          if (playbackManager.showBottomPlayer)
            Align(
              alignment: Alignment.bottomCenter,
              child: BottomPlayer(),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download),
            label: 'Downloads',
          ),
        ],
      ),
    );
  }
}

void main() {
  final audioHandler = MyAudioHandler();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlaybackManager(audioHandler),
        ),
        ChangeNotifierProvider(create: (_) => PlaylistManager()),
        // Add other providers here
      ],
      child: const AudynApp(),
    ),
  );
}

class AudynApp extends StatelessWidget {
  const AudynApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Audyn',
      theme: ThemeData.dark(),
      home: const AppWithPlayer(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio_handler.dart';
import 'core/download/download_manager.dart';
import 'core/playback/playback_manager.dart';
import 'core/playlist/playlist_manager.dart';
import 'features/home/playlists_overview_screen.dart';
import 'features/home/search_screen.dart';
import 'features/home/download_screen.dart';
import 'features/player/bottom_player.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootApp());
}

class BootApp extends StatefulWidget {
  const BootApp({super.key});

  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  late MyAudioHandler _audioHandler;
  late PlaylistManager _playlistManager;
  late PlaybackManager _playbackManager;
  late DownloadManager _downloadManager;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _audioHandler = await initAudioService();
    _playlistManager = await PlaylistManager.create();
    _playbackManager = PlaybackManager(_audioHandler);
    _downloadManager = DownloadManager();

    setState(() {
      _isReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MultiProvider(
      providers: [
        Provider<MyAudioHandler>.value(value: _audioHandler),
        ChangeNotifierProvider.value(value: _playlistManager),
        ChangeNotifierProvider.value(value: _playbackManager),
        ChangeNotifierProvider.value(value: _downloadManager),
      ],
      child: AudynApp(audioHandler: _audioHandler),
    );
  }
}

class AudynApp extends StatelessWidget {
  final MyAudioHandler audioHandler;

  const AudynApp({Key? key, required this.audioHandler}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Audyn',
      theme: ThemeData.dark().copyWith(
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: AppWithPlayer(audioHandler: audioHandler),
    );
  }
}

class AppWithPlayer extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const AppWithPlayer({Key? key, required this.audioHandler}) : super(key: key);

  @override
  State<AppWithPlayer> createState() => _AppWithPlayerState();
}

class _AppWithPlayerState extends State<AppWithPlayer> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    PlaylistsOverviewScreen(),
    BrowseScreen(),
    DownloadScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = context.watch<PlaybackManager>();

    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playbackManager.showBottomPlayer) const BottomPlayer(),
          BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
              BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
            ],
          ),
        ],
      ),
    );
  }
}

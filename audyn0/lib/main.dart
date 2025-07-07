import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// App & Core
import 'package:audyn/src/app.dart';
import 'package:audyn/src/core/di/service_locator.dart';
import 'package:audyn/src/data/services/hive_box.dart';
import 'package:audyn/services/music_seeder_service.dart';
import 'client_supabase.dart';

// Bloc Imports
import 'package:audyn/src/bloc/theme/theme_bloc.dart';
import 'package:audyn/src/bloc/home/home_bloc.dart';
import 'package:audyn/src/bloc/song/song_bloc.dart';
import 'package:audyn/src/bloc/player/player_bloc.dart';
import 'package:audyn/src/bloc/favorites/favorites_bloc.dart';
import 'package:audyn/src/bloc/recents/recents_bloc.dart';
import 'package:audyn/src/bloc/search/search_bloc.dart';
import 'package:audyn/src/bloc/scan/scan_cubit.dart';
import 'package:audyn/src/bloc/playlists/playlists_cubit.dart';
import 'package:audyn/src/bloc/Downloads/DownloadsBloc.dart';
import 'package:audyn/src/data/repositories/player_repository.dart';

Future<void> main() async {
  // Ensure Flutter engine is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env
  await dotenv.load(fileName: "assets/env/.env");

  // Initialize Supabase
  await SupabaseClientService().init();

  // Setup Dependency Injection
  init();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox(HiveBox.boxName);

  // Initialize the Music Player
  await sl<MusicPlayer>().init();

  // Initialize background work manager
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Schedule background seeding task
  Workmanager().registerPeriodicTask(
    'periodicMusicSeeding',
    'seedMissingSongs',
    frequency: const Duration(hours: 12),
    initialDelay: const Duration(minutes: 1),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );

  // Request necessary media permissions
  await _requestMediaPermissions();

  // Launch the app
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<ThemeBloc>()),
        BlocProvider(create: (_) => sl<HomeBloc>()),
        BlocProvider(create: (_) => sl<SongBloc>()),
        BlocProvider(create: (_) => sl<PlayerBloc>()),
        BlocProvider(create: (_) => sl<FavoritesBloc>()),
        BlocProvider(create: (_) => sl<RecentsBloc>()),
        BlocProvider(create: (_) => sl<SearchBloc>()),
        BlocProvider(create: (_) => sl<ScanCubit>()),
        BlocProvider(create: (_) => sl<PlaylistsCubit>()),
        BlocProvider(create: (_) => sl<DownloadsBloc>()),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> _requestMediaPermissions() async {
  final audioGranted = await Permission.audio.isGranted;

  if (audioGranted) return;

  final permissionsToRequest = [
    Permission.audio,
    Permission.storage,
    Permission.manageExternalStorage,
  ];

  final statuses = await permissionsToRequest.request();

  if (statuses.values.any((status) => status.isGranted)) {
    debugPrint("✅ Permissions granted.");
  } else {
    debugPrint("❌ Permissions denied. Media access won't work.");
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'seedMissingSongs') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final accepted = prefs.getBool('disclaimerAccepted') ?? false;

        if (!accepted) {
          debugPrint('[Workmanager] Disclaimer not accepted, skipping.');
          return true;
        }

        final seeder = MusicSeederService();
        await seeder.init();
        await seeder.seedMissingSongs();

        debugPrint('[Workmanager] Successfully seeded missing songs.');
      } catch (e, stackTrace) {
        debugPrint('[Workmanager] Error during seeding: $e\n$stackTrace');
      }
    }
    return true;
  });
}

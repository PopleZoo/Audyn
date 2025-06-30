import 'package:audyn/src/bloc/Downloads/DownloadsBloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

import 'package:audyn/src/app.dart';
import 'package:audyn/src/bloc/favorites/favorites_bloc.dart';
import 'package:audyn/src/bloc/home/home_bloc.dart';
import 'package:audyn/src/bloc/player/player_bloc.dart';
import 'package:audyn/src/bloc/playlists/playlists_cubit.dart';
import 'package:audyn/src/bloc/recents/recents_bloc.dart';
import 'package:audyn/src/bloc/scan/scan_cubit.dart';
import 'package:audyn/src/bloc/search/search_bloc.dart';
import 'package:audyn/src/bloc/song/song_bloc.dart';
import 'package:audyn/src/bloc/theme/theme_bloc.dart';
import 'package:audyn/src/core/di/service_locator.dart';
import 'package:audyn/src/data/repositories/player_repository.dart';
import 'package:audyn/src/data/services/hive_box.dart';
import 'package:audyn/services/music_seeder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize dependency injection
  init();

  // Initialize workmanager
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // Register periodic background task to seed songs every 12 hours
  Workmanager().registerPeriodicTask(
    "periodicMusicSeeding",
    "seedMissingSongs",
    frequency: const Duration(hours: 12),
    initialDelay: const Duration(minutes: 1),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
      requiresCharging: false,
    ),
  );

  // Request media library permission (necessary for scanning music)
  final status = await Permission.mediaLibrary.request();

  if (status != PermissionStatus.granted) {
    debugPrint("Media library permission not granted.");
  }

  // Initialize Hive local database
  await Hive.initFlutter();
  await Hive.openBox(HiveBox.boxName);

  // Initialize audio service (music player)
  await sl<MusicPlayer>().init();

  // Run the main app with BlocProviders
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => sl<HomeBloc>()),
        BlocProvider(create: (context) => sl<ThemeBloc>()),
        BlocProvider(create: (context) => sl<SongBloc>()),
        BlocProvider(create: (context) => sl<FavoritesBloc>()),
        BlocProvider(create: (context) => sl<PlayerBloc>()),
        BlocProvider(create: (context) => sl<RecentsBloc>()),
        BlocProvider(create: (context) => sl<SearchBloc>()),
        BlocProvider(create: (context) => sl<ScanCubit>()),
        BlocProvider(create: (context) => sl<PlaylistsCubit>()),
        BlocProvider(create: (context) => sl<DownloadsBloc>()),
      ],
      child: const MyApp(),
    ),
  );
}

// WorkManager callback entry point
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'seedMissingSongs') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final consent = prefs.getBool('disclaimerAccepted') ?? false;

        if (!consent) {
          print('[Workmanager] Disclaimer not accepted, skipping seeding.');
          return Future.value(true);
        }

        final seeder = MusicSeederService();
        await seeder.init();
        await seeder.seedMissingSongs();

        print('[Workmanager] Successfully seeded missing songs.');
      } catch (e, stack) {
        print('[Workmanager] Error during seeding: $e\n$stack');
      }
    }
    return Future.value(true);
  });
}

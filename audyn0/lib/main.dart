import 'package:audyn/src/bloc/Downloads/DownloadsBloc.dart';
import 'package:audyn/src/data/repositories/player_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:audyn/src/data/services/hive_box.dart';
import 'package:audyn/services/music_seeder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup dependency injection
  init();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox(HiveBox.boxName);

  // Initialize Music Player
  await sl<MusicPlayer>().init();

  // Initialize background workmanager
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // Register periodic task
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

  // Request permissions (media)
  await _requestMediaPermissions();

  // Run the app
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<HomeBloc>()),
        BlocProvider(create: (_) => sl<ThemeBloc>()),
        BlocProvider(create: (_) => sl<SongBloc>()),
        BlocProvider(create: (_) => sl<FavoritesBloc>()),
        BlocProvider(create: (_) => sl<PlayerBloc>()),
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
  // Android 13+ requires this permission
  if (await Permission.audio.isGranted) return;

  Map<Permission, PermissionStatus> statuses;

  if (await Permission.manageExternalStorage.isGranted ||
      await Permission.audio.isGranted ||
      await Permission.storage.isGranted) {
    return;
  }

  // Request permissions based on Android version
  if (await Permission.manageExternalStorage.isDenied) {
    statuses = await [
      Permission.manageExternalStorage,
      Permission.audio,
      Permission.storage,
    ].request();
  } else {
    statuses = await [
      Permission.audio,
      Permission.storage,
    ].request();
  }

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
        final consent = prefs.getBool('disclaimerAccepted') ?? false;

        if (!consent) {
          debugPrint('[Workmanager] Disclaimer not accepted, skipping.');
          return true;
        }

        final seeder = MusicSeederService();
        await seeder.init();
        await seeder.seedMissingSongs();

        debugPrint('[Workmanager] Successfully seeded missing songs.');
      } catch (e, stack) {
        debugPrint('[Workmanager] Error during seeding: $e\n$stack');
      }
    }
    return true;
  });
}

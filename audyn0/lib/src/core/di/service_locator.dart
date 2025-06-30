import 'package:audyn/src/bloc/Downloads/DownloadsBloc.dart';
import 'package:audyn/src/data/repositories/downloads_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:audyn/src/bloc/playlists/playlists_cubit.dart';
import 'package:audyn/src/bloc/favorites/favorites_bloc.dart';
import 'package:audyn/src/bloc/home/home_bloc.dart';
import 'package:audyn/src/bloc/player/player_bloc.dart';
import 'package:audyn/src/bloc/recents/recents_bloc.dart';
import 'package:audyn/src/bloc/scan/scan_cubit.dart';
import 'package:audyn/src/bloc/search/search_bloc.dart';
import 'package:audyn/src/bloc/song/song_bloc.dart';
import 'package:audyn/src/bloc/theme/theme_bloc.dart';
import 'package:audyn/src/data/repositories/favorites_repository.dart';
import 'package:audyn/src/data/repositories/home_repository.dart';
import 'package:audyn/src/data/repositories/player_repository.dart';
import 'package:audyn/src/data/repositories/recents_repository.dart';
import 'package:audyn/src/data/repositories/search_repository.dart';
import 'package:audyn/src/data/repositories/song_repository.dart';
import 'package:audyn/src/data/repositories/theme_repository.dart';
import 'package:on_audio_query/on_audio_query.dart';
final sl = GetIt.instance;

void init() {
  // Bloc
  sl.registerFactory(() => ThemeBloc(repository: sl()));
  sl.registerFactory(() => HomeBloc(repository: sl()));
  sl.registerFactory(() => PlayerBloc(repository: sl()));
  sl.registerFactory(() => SongBloc(repository: sl()));
  sl.registerFactory(() => FavoritesBloc(repository: sl()));
  sl.registerFactory(() => RecentsBloc(repository: sl()));
  sl.registerFactory(() => SearchBloc(repository: sl()));

  // Register DownloadsBloc with its repository
  sl.registerFactory(() => DownloadsBloc(repository: sl()));

  // Cubit
  sl.registerFactory(() => ScanCubit());
  sl.registerFactory(() => PlaylistsCubit());

  // Repository
  sl.registerLazySingleton(() => ThemeRepository());
  sl.registerLazySingleton(() => HomeRepository());
  sl.registerLazySingleton<MusicPlayer>(() => JustAudioPlayer());
  sl.registerLazySingleton(() => SongRepository());
  sl.registerLazySingleton(() => FavoritesRepository());
  sl.registerLazySingleton(() => RecentsRepository());
  sl.registerLazySingleton(() => SearchRepository());

  // Register DownloadsRepository
  sl.registerLazySingleton(() => DownloadsRepository());

  // Third Party
  sl.registerLazySingleton(() => OnAudioQuery());
}

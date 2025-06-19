import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../main.dart';
import '../../utils/playlist_cover_generator.dart';
import '../models/music_track.dart';
import '../models/playlist.dart';

class PlaylistManager extends ChangeNotifier {
  PlaylistManager._();

  static const _prefsPlaylistsKey = 'playlists_data';
  static const _mainFolderName = 'AudynMusic';

  final List<Playlist> _playlists = [];
  final Uuid _uuid = Uuid();

  late Directory _baseDir;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  String get baseDirPath => _baseDir.path;

  /// Factory constructor to create and initialize PlaylistManager.
  static Future<PlaylistManager> create() async {
    final manager = PlaylistManager._();
    await manager._initialize();
    return manager;
  }

  /// Generates a stable SHA1 hash from input string (used for playlist IDs).
  String generateStableId(String input) {
    final bytes = utf8.encode(input);
    final digest = sha1.convert(bytes);
    return digest.toString();
  }

  /// Recursively scan a folder for supported music tracks.
  Future<List<MusicTrack>> scanFolderForTracks({required String folderPath}) async {
    final dir = Directory(folderPath);
    List<MusicTrack> tracks = [];

    try {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
          if (['mp3', 'flac', 'wav'].contains(ext)) {
            try {
              final metadata = await MetadataRetriever.fromFile(entity);
              String? coverPath;

              if (metadata.albumArt != null) {
                final tempDir = await getTemporaryDirectory();
                final coverFile = File(p.join(tempDir.path, '${entity.uri.pathSegments.last}_cover.jpg'));
                await coverFile.writeAsBytes(metadata.albumArt!);
                coverPath = coverFile.path;
              }

              tracks.add(MusicTrack(
                id: entity.path,
                title: metadata.trackName ?? p.basename(entity.path),
                artist: metadata.albumArtistName ?? 'Unknown',
                localPath: entity.path,
                coverUrl: coverPath ?? '',
              ));
            } catch (e) {
              debugPrint('Metadata parsing failed for ${entity.path}: $e');
              // fallback minimal info
              tracks.add(MusicTrack(
                id: entity.path,
                title: p.basename(entity.path),
                artist: 'Unknown',
                localPath: entity.path,
                coverUrl: '',
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning tracks in folder: $e');
    }

    return tracks;
  }

  /// Initialize base directory, load saved playlists, and sync folders.
  Future<void> _initialize() async {
    await _loadBaseDir();
    await _loadFromPrefs();
    await _syncFoldersWithPlaylists();
    notifyListeners();
  }

  Future<void> _loadBaseDir() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      throw Exception('Unable to get external storage directory');
    }

    _baseDir = Directory(p.join(externalDir.path, _mainFolderName));
    print('Base music directory path: ${_baseDir.path}');

    if (!await _baseDir.exists()) {
      print('Base music directory does not exist, creating...');
      await _baseDir.create(recursive: true);
    } else {
      final folders = _baseDir.listSync().whereType<Directory>().map((d) => d.path).toList();
      print('Folders found in base directory: $folders');
    }
    notifyListeners();
  }


  /// Loads playlists from SharedPreferences.
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsPlaylistsKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      _playlists.clear();
      _playlists.addAll(jsonList.map((e) => Playlist.fromJson(e)));
      notifyListeners();
    }
  }

  /// Saves playlists to SharedPreferences.
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(_playlists.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsPlaylistsKey, jsonString);
  }

  /// Scans the base directory for subfolders, updating or adding playlists.
  Future<void> scanMusicDirectory() async {
    if (!await _baseDir.exists()) return;

    final folders = _baseDir.listSync().whereType<Directory>().toList();

    for (final dir in folders) {
      final name = p.basename(dir.path);
      final tracks = await scanFolderForTracks(folderPath: dir.path);

      if (tracks.isNotEmpty) {
        final existingIndex = _playlists.indexWhere((p) => p.folderPath == dir.path);
        final playlist = Playlist(
          name: name,
          tracks: tracks,
          id: generateStableId(dir.path),
          folderPath: dir.path,
        );

        if (existingIndex != -1) {
          _playlists[existingIndex] = playlist;
        } else {
          _playlists.add(playlist);
        }
      }
    }

    notifyListeners();
    await _saveToPrefs();
  }

  /// Syncs folders on disk with internal playlist list, adding missing playlists.
  Future<void> _syncFoldersWithPlaylists() async {
    if (!await _baseDir.exists()) return;

    final folders = _baseDir.listSync().whereType<Directory>();

    for (final folder in folders) {
      if (p.basename(folder.path).startsWith('_')) continue; // skip special folders

      final exists = _playlists.any((p) => p.folderPath == folder.path);
      if (!exists) {
        final newPlaylist = Playlist(
          id: _uuid.v4(),
          name: p.basename(folder.path),
          folderPath: folder.path,
          tracks: [],
        );
        _playlists.add(newPlaylist);
        await refreshPlaylist(newPlaylist.id);
      }
    }

    await _saveToPrefs();
    notifyListeners();
  }

  /// Resync all playlists by scanning all folders & updating track lists.
  Future<void> resyncPlaylists() async {
    try {
      // Wait a moment before starting to give the OS time to settle
      await Future.delayed(const Duration(seconds: 1));

      // First scan base dir for new playlist folders or removed ones
      await scanMusicDirectory();

      for (final playlist in _playlists) {
        final dir = Directory(playlist.folderPath);

        const maxAttempts = 3;
        var attempt = 0;
        var success = false;

        while (attempt < maxAttempts && !success) {
          attempt++;
          if (!await dir.exists()) {
            debugPrint("Attempt $attempt: Directory missing for playlist '${playlist.name}': ${playlist.folderPath}");
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          try {
            debugPrint("Attempt $attempt: Refreshing playlist '${playlist.name}' from folder: ${playlist.folderPath}");
            await refreshPlaylist(playlist.id);
            success = true;
          } catch (e) {
            debugPrint("Attempt $attempt: Failed to refresh playlist '${playlist.name}': $e");
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        if (!success) {
          debugPrint("Failed to refresh playlist '${playlist.name}' after $maxAttempts attempts");
        }
      }

      notifyListeners();

      ScaffoldMessenger.maybeOf(appNavigatorKey.currentContext!)?.showSnackBar(
        const SnackBar(content: Text('Playlists resynced successfully')),
      );
    } catch (e) {
      debugPrint("Failed to resync playlists: $e");
      ScaffoldMessenger.maybeOf(appNavigatorKey.currentContext!)?.showSnackBar(
        SnackBar(content: Text('Failed to resync playlists: $e')),
      );
    }
  }


  /// Creates a new playlist folder and playlist entry.
  Future<Playlist> createPlaylist(String name) async {
    final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String candidateName = sanitized;
    int counter = 1;

    while (await Directory(p.join(_baseDir.path, candidateName)).exists()) {
      candidateName = '$sanitized ($counter)';
      counter++;
    }

    final playlistDir = Directory(p.join(_baseDir.path, candidateName));
    await playlistDir.create(recursive: true);

    final newPlaylist = Playlist(
      id: _uuid.v4(),
      name: candidateName,
      folderPath: playlistDir.path,
      tracks: [],
    );

    _playlists.add(newPlaylist);
    notifyListeners();
    await _saveToPrefs();
    return newPlaylist;
  }

  /// Adds an existing playlist if not already present.
  Future<void> addPlaylist(Playlist playlist) async {
    if (!_playlists.any((p) => p.id == playlist.id)) {
      _playlists.add(playlist);
      notifyListeners();
      await _saveToPrefs();
    }
  }

  /// Removes a playlist and moves its folder to _Trash.
  Future<void> removePlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere(
          (p) => p.id == playlistId,
      orElse: () => Playlist(id: '', name: '', folderPath: '', tracks: []),
    );

    if (playlist.folderPath.isNotEmpty) {
      final folder = Directory(playlist.folderPath);
      if (await folder.exists()) {
        final trashDir = Directory(p.join(_baseDir.path, '_Trash'));
        if (!await trashDir.exists()) await trashDir.create();

        final trashedPath = p.join(trashDir.path, p.basename(folder.path));
        await folder.rename(trashedPath);
      }
    }

    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    await _saveToPrefs();
  }

  /// Adds a track to a playlist if it does not already exist.
  Future<void> addTrackToPlaylist(String playlistId, MusicTrack track) async {
    final playlist = _playlists.firstWhere(
          (p) => p.id == playlistId,
      orElse: () => throw Exception('Playlist not found'),
    );

    if (!playlist.tracks.any((t) => t.id == track.id)) {
      playlist.tracks.add(track);
      notifyListeners();
      await _saveToPrefs();
    }
  }

  /// Removes a track from a playlist by its track ID.
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlist = _playlists.firstWhere(
          (p) => p.id == playlistId,
      orElse: () => throw Exception('Playlist not found'),
    );

    playlist.tracks.removeWhere((t) => t.id == trackId);
    notifyListeners();
    await _saveToPrefs();
  }

  /// Clears all playlists and saves.
  Future<void> clearPlaylists() async {
    _playlists.clear();
    notifyListeners();
    await _saveToPrefs();
  }

  /// Returns the directory of a playlist by ID, creating if missing.
  Future<Directory> getPlaylistFolderById(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final folder = Directory(playlist.folderPath);
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  /// Saves a track file inside a playlist folder.
  Future<void> saveTrackFile(String playlistId, String fileName, List<int> bytes) async {
    final folder = await getPlaylistFolderById(playlistId);
    final file = File(p.join(folder.path, fileName));
    await file.writeAsBytes(bytes);
  }

  /// Refreshes a single playlist's tracks by rescanning its folder.
  Future<void> refreshPlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final dir = Directory(playlist.folderPath);

    if (!await dir.exists()) return;

    final newTracks = await scanFolderForTracks(folderPath: dir.path);
    playlist.tracks = newTracks;

    await generatePlaylistCover(dir.path);

    notifyListeners();
    await _saveToPrefs();
  }

  /// Restores a playlist if not already in list.
  void restorePlaylist(Playlist playlist) {
    if (!_playlists.any((p) => p.id == playlist.id)) {
      _playlists.add(playlist);
      notifyListeners();
    }
  }

  /// Resyncs a playlist by name (scans folder and updates tracks).
  Future<void> resyncPlaylist(String playlistName) async {
    final index = _playlists.indexWhere((p) => p.name == playlistName);
    if (index == -1) return;

    final folder = Directory(_playlists[index].folderPath);
    if (await folder.exists()) {
      final newTracks = await scanFolderForTracks(folderPath: folder.path);
      _playlists[index].tracks = newTracks;
      await generatePlaylistCover(folder.path);
      notifyListeners();
      await _saveToPrefs();
    }
  }
}

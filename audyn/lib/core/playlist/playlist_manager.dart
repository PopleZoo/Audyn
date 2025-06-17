import 'dart:convert';
import 'dart:io';
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
  static const _prefsPlaylistsKey = 'playlists_data';
  static const _mainFolderName = 'AudynMusic';

  final List<Playlist> _playlists = [];
  final Uuid _uuid = Uuid();

  late Directory _baseDir;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  String get baseDirPath => _baseDir.path;

  PlaylistManager._();

  static Future<PlaylistManager> create() async {
    final manager = PlaylistManager._();
    await manager._initialize();
    return manager;
  }

  String generateUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<List<MusicTrack>> scanFolderForTracks({required String folderPath}) async {
    final dir = Directory(folderPath);
    List<MusicTrack> tracks = [];

    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
          if (['mp3', 'flac', 'wav'].contains(ext)) {
            tracks.add(MusicTrack(
              id: generateUniqueId(),
              title: p.basename(entity.path),
              artist: 'Unknown',
              localPath: entity.path,
              coverUrl: '',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning tracks in folder: $e');
    }
    return tracks;
  }

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
    if (!await _baseDir.exists()) {
      await _baseDir.create(recursive: true);
    }
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsPlaylistsKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      _playlists.clear();
      _playlists.addAll(jsonList.map((e) => Playlist.fromJson(e)));
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(_playlists.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsPlaylistsKey, jsonString);
  }

  Future<void> _syncFoldersWithPlaylists() async {
    final folders = _baseDir.listSync().whereType<Directory>();

    for (final folder in folders) {
      if (p.basename(folder.path).startsWith('_')) continue;

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
  }

  Future<void> resyncPlaylists() async {
    try {
      for (final playlist in _playlists) {
        final dir = Directory(playlist.folderPath);

        if (!await dir.exists()) {
          debugPrint("Directory for playlist '${playlist.name}' does not exist: ${playlist.folderPath}");
          continue;
        }

        debugPrint("Refreshing playlist '${playlist.name}' from folder: ${playlist.folderPath}");
        await refreshPlaylist(playlist.id);
      }

      ScaffoldMessenger.maybeOf(navigatorKey.currentContext!)?.showSnackBar(
        const SnackBar(content: Text('Playlists resynced successfully')),
      );

      notifyListeners();
    } catch (e) {
      debugPrint("Failed to resync playlists: $e");
      ScaffoldMessenger.maybeOf(navigatorKey.currentContext!)?.showSnackBar(
        SnackBar(content: Text('Failed to resync playlists: $e')),
      );
    }
  }

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

  Future<void> addPlaylist(Playlist playlist) async {
    if (!_playlists.any((p) => p.id == playlist.id)) {
      _playlists.add(playlist);
      notifyListeners();
      await _saveToPrefs();
    }
  }

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

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlist = _playlists.firstWhere(
          (p) => p.id == playlistId,
      orElse: () => throw Exception('Playlist not found'),
    );

    playlist.tracks.removeWhere((t) => t.id == trackId);
    notifyListeners();
    await _saveToPrefs();
  }

  Future<void> clearPlaylists() async {
    _playlists.clear();
    notifyListeners();
    await _saveToPrefs();
  }

  Future<Directory> getPlaylistFolderById(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final folder = Directory(playlist.folderPath);
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<void> saveTrackFile(String playlistId, String fileName, List<int> bytes) async {
    final folder = await getPlaylistFolderById(playlistId);
    final file = File(p.join(folder.path, fileName));
    await file.writeAsBytes(bytes);
  }

  Future<void> refreshPlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    final dir = Directory(playlist.folderPath);

    if (!await dir.exists()) return;

    final files = dir.listSync().whereType<File>().toList();

    // Replace the entire tracks list:
    List<MusicTrack> newTracks = [];

    for (final file in files) {
      try {
        final metadata = await MetadataRetriever.fromFile(file);
        String? coverPath;

        if (metadata.albumArt != null) {
          final tempDir = await getTemporaryDirectory();
          final coverFile = File(p.join(tempDir.path, '${file.uri.pathSegments.last}_cover.jpg'));
          await coverFile.writeAsBytes(metadata.albumArt!);
          coverPath = coverFile.path;
        }

        final track = MusicTrack(
          id: file.path,
          title: metadata.trackName ?? p.basename(file.path),
          artist: metadata.albumArtistName ?? 'Unknown',
          localPath: file.path,
          coverUrl: coverPath ?? '',
        );

        newTracks.add(track);
      } catch (e) {
        debugPrint('Failed to parse metadata for ${file.path}: $e');
      }
    }

    playlist.tracks = newTracks;

    notifyListeners();
    await _saveToPrefs();
  }

  void restorePlaylist(Playlist playlist) {
    if (!_playlists.any((p) => p.id == playlist.id)) {
      _playlists.add(playlist);
      notifyListeners();
    }
  }

  Future<void> resyncPlaylist(String playlistName) async {
    final index = _playlists.indexWhere((p) => p.name == playlistName);
    if (index == -1) return;

    final folder = Directory(_playlists[index].folderPath);
    if (await folder.exists()) {
      final newTracks = await scanFolderForTracks(folderPath: folder.path);
      _playlists[index].tracks = newTracks;
      await generatePlaylistCover(folder.path); // if using auto cover generation
      notifyListeners();
      await _saveToPrefs();
    }
  }
}

/*─────────────────────────────────────────────────────────────*\
│  lib/services/music_seeder_service.dart                      │
\*─────────────────────────────────────────────────────────────*/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/CryptoHelper.dart';
import '../src/data/services/LibtorrentService.dart';

class MusicSeederService {
  MusicSeederService._(this.audioQuery);

  static Future<MusicSeederService> create([OnAudioQuery? aq]) async {
    final service = MusicSeederService._(aq ?? OnAudioQuery());
    await service._init();
    return service;
  }

  final OnAudioQuery audioQuery;
  final LibtorrentService _libtorrent = LibtorrentService();

  Directory? torrentsDir;
  final Set<String> knownTorrentNames = {};
  final Map<String, String> _nameToPathMap = {};
  final Map<String, Map<String, dynamic>> _metaCache = {};

  Map<String, String> get nameToPathMap => _nameToPathMap;

  static const _allowedExt = ['.mp3', '.flac', '.wav', '.m4a'];

  Future<void> _init() async {
    final base = await getApplicationDocumentsDirectory();
    torrentsDir = Directory(p.join(base.path, 'torrents'));
    if (!await torrentsDir!.exists()) {
      await torrentsDir!.create(recursive: true);
      debugPrint('[Seeder] Created torrents directory at: ${torrentsDir!.path}');
    } else {
      debugPrint('[Seeder] Using existing torrents directory: ${torrentsDir!.path}');
    }
  }

  static String norm(String name) {
    final base = p.basename(name);
    return base.toLowerCase().replaceAll(RegExp(r'[^\w]+'), '_');
  }

  Future<List<String>> seedMissingSongs({
    Duration gap = const Duration(milliseconds: 120),
  }) async {
    if (!(await audioQuery.permissionsStatus())) {
      if (!await audioQuery.permissionsRequest()) return [];
    }

    final songs = await audioQuery.querySongs();
    final valid = <String>[];

    for (final s in songs) {
      final ext = p.extension(s.data).toLowerCase();
      if (!_allowedExt.contains(ext)) continue;

      final file = File(s.data);
      if (!await file.exists()) continue;

      try {
        final meta = await MetadataRetriever.fromFile(file);
        final longEnough = (meta.trackDuration ?? 0) > 30 * 1000;
        final hasTrackTag = (meta.trackName ?? '').trim().isNotEmpty;
        if (longEnough && hasTrackTag) valid.add(s.data);
      } catch (_) {
        // ignore bad file
      }
    }

    final createdTorrents = await _seedFiles(valid, gap);
    return createdTorrents;
  }

  Future<List<String>> _seedFiles(List<String> paths, Duration gap) async {
    if (torrentsDir == null) {
      debugPrint('[Seeder] torrentsDir not initialized.');
      return [];
    }

    final active = <String>{
      ...(await _libtorrent.getAllTorrents())
          .map((m) => norm(m['name']?.toString() ?? ''))
    };

    final createdTorrents = <String>[];

    for (final songPath in paths) {
      final file = File(songPath);
      if (!await file.exists()) continue;

      final key = norm(songPath);
      final encPath = p.join(torrentsDir!.path, '$key.audyn.torrent');

      Uint8List? torrentBytesPlain;
      try {
        torrentBytesPlain = await createTorrentBytesFromPath(file.path);
        if (torrentBytesPlain == null || torrentBytesPlain.isEmpty) {
          debugPrint('[Seeder] ❌ Failed to create torrent for $songPath');
          continue;
        }
      } catch (e) {
        debugPrint('[Seeder] ❌ createTorrentBytes failed: $e');
        continue;
      }

      try {
        final encBytes = CryptoHelper.encryptBytes(torrentBytesPlain);
        await File(encPath).writeAsBytes(encBytes, flush: true);
        createdTorrents.add(encPath);
      } catch (e) {
        debugPrint('[Seeder] ❌ Writing encrypted file failed: $e');
        continue;
      }

      if (!active.contains(key)) {
        final ok = await _libtorrent.addTorrentFromBytes(
          torrentBytesPlain,
          p.dirname(songPath),
          seedMode: true,
          announce: false,
        );
        if (!ok) {
          debugPrint('[Seeder] ⚠️ addTorrentFromBytes failed for $songPath');
          continue;
        }
      }

      if (knownTorrentNames.add(key)) {
        _nameToPathMap[key] = songPath;
      }

      await Future.delayed(gap);
    }

    return createdTorrents;
  }

  Future<Map<String, dynamic>?> getMetadataForName(String anyName) async {
    final key = norm(anyName);
    if (_metaCache.containsKey(key)) return _metaCache[key];

    final path = _nameToPathMap[key];
    if (path == null) return null;

    try {
      final meta = await MetadataRetriever.fromFile(File(path));
      final artistNamesList = meta.trackArtistNames ?? [];
      final artistNamesStr = artistNamesList.join(', ');

      return _metaCache[key] = {
        'title': meta.trackName ?? '',
        'artist': artistNamesStr,
        'artistnames': artistNamesList,
        'album': meta.albumName ?? '',
        'albumArt': meta.albumArt,
        'duration': meta.trackDuration ?? 0,
      };
    } catch (e) {
      debugPrint('[Meta] read error: $e');
      return null;
    }
  }

  String? getEncryptedTorrentPath(String anyName) {
    final key = norm(anyName);
    if (!knownTorrentNames.contains(key) || torrentsDir == null) return null;
    return p.join(torrentsDir!.path, '$key.audyn.torrent');
  }

  List<String> getLocalFilesForTorrent(String anyName) {
    final path = _nameToPathMap[norm(anyName)];
    if (path == null) return [];
    final file = File(path);
    if (file.existsSync()) return [p.basename(path)];

    final dir = Directory(path);
    if (!dir.existsSync()) return [];

    return dir
        .listSync()
        .whereType<File>()
        .map((e) => p.basename(e.path))
        .toList();
  }

  /// Create torrent bytes from a given song path using libtorrent
  Future<Uint8List?> createTorrentBytesFromPath(String filePath) async {
    return await _libtorrent.createTorrentBytes(filePath);
  }

  /// Seeds a single song, returns the encrypted .torrent path
  Future<String?> seedSong(String songFilePath) async {
    final file = File(songFilePath);
    if (!await file.exists()) return null;

    final torrentBytes = await createTorrentBytesFromPath(file.path);
    if (torrentBytes == null || torrentBytes.isEmpty) return null;

    final encBytes = CryptoHelper.encryptBytes(torrentBytes);
    if (encBytes == null) return null;

    final key = norm(songFilePath);
    final outPath = p.join(torrentsDir!.path, '$key.audyn.torrent');
    await File(outPath).writeAsBytes(encBytes);

    final alreadySeeding = (await _libtorrent.getAllTorrents())
        .any((m) => norm(m['name']?.toString() ?? '') == key);

    if (!alreadySeeding) {
      final ok = await _libtorrent.addTorrentFromBytes(
        torrentBytes,
        p.dirname(songFilePath),
        seedMode: true,
        announce: false,
      );
      if (!ok) {
        debugPrint('[Seeder] ⚠️ Failed to start torrent for $songFilePath');
      }
    }

    _nameToPathMap[key] = songFilePath;
    knownTorrentNames.add(key);

    return outPath;
  }
}

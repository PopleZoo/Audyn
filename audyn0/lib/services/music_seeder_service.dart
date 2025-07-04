import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../src/data/services/LibtorrentService.dart';
import '../src/native/libtorrent_wrapper.dart';

class MusicSeederService {
  final OnAudioQuery audioQuery;
  final Set<String> knownTorrentNames = {};  // track torrents by sanitized name or full path
  late final String torrentsDir;

  final Map<String, String> _nameToPathMap = {};  // key: torrentName or sanitized file base name
  final Map<String, Map<String, dynamic>?> _metadataCache = {};

  Map<String, String> get nameToPathMap => _nameToPathMap;

  MusicSeederService([OnAudioQuery? audioQuery])
      : audioQuery = audioQuery ?? OnAudioQuery() {
    debugPrint('[MusicSeederService] Constructor called');
  }

  static const List<String> allowedExtensions = ['.mp3', '.flac', '.wav', '.m4a'];

  Future<void> _initPaths() async {
    final directory = await getApplicationDocumentsDirectory();
    final basePath = directory.path;

    torrentsDir = p.join(basePath, 'torrents');
  }

  Future<void> init() async {
    await _initPaths();

    final dir = Directory(torrentsDir);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  Future<void> resetSeedingState() async {
    try {
      knownTorrentNames.clear();
      _nameToPathMap.clear();
      _metadataCache.clear();
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to reset seeding state: $e');
    }
  }

  Future<void> restartSeeding() async {
    await init();
    await resetSeedingState();

    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();

      for (final torrent in currentTorrents) {
        final torrentName = torrent['name']?.toString();
        if (torrentName == null || torrentName.isEmpty) continue;
        await LibtorrentWrapper.removeTorrentByName(torrentName);
      }
    } catch (_) {}

    knownTorrentNames.clear();
    _nameToPathMap.clear();
    _metadataCache.clear();

    await seedMissingSongs();
  }

  Future<void> seedMissingSongs({Duration delayBetweenAdds = const Duration(milliseconds: 200)}) async {
    try {
      final permission = await audioQuery.permissionsStatus();
      if (!permission) return;
    } catch (_) {
      return;
    }

    final List<SongModel> allSongs = await audioQuery.querySongs();
    final List<String> validFilePaths = [];

    for (final song in allSongs) {
      final ext = p.extension(song.data).toLowerCase();
      if (!(song.isMusic == true && allowedExtensions.contains(ext))) continue;

      final file = File(song.data);
      if (!await file.exists()) continue;

      try {
        final metadata = await MetadataRetriever.fromFile(file);
        final hasAnyMetadata = (metadata.trackName?.trim().isNotEmpty ?? false) ||
            (metadata.authorName?.trim().isNotEmpty ?? false) ||
            (metadata.albumName?.trim().isNotEmpty ?? false);
        final durationOk = (metadata.trackDuration != null && metadata.trackDuration! > 30 * 1000);
        if (hasAnyMetadata && durationOk) validFilePaths.add(song.data);
      } catch (_) {}
    }

    await seedFiles(validFilePaths, delayBetweenAdds: delayBetweenAdds);
  }

  Future<void> seedFiles(List<String> filePaths, {Duration delayBetweenAdds = const Duration(milliseconds: 100)}) async {
    final rawStats = await LibtorrentWrapper.getTorrentStats();

    final decoded = jsonDecode(rawStats);

    List<Map<String, dynamic>> currentTorrents = [];

    if (decoded is List) {
      currentTorrents = decoded.whereType<Map<String, dynamic>>().toList();
    } else if (decoded is Map<String, dynamic> && decoded.containsKey('torrents')) {
      final torrentsRaw = decoded['torrents'];
      if (torrentsRaw is List) {
        currentTorrents = torrentsRaw.whereType<Map<String, dynamic>>().toList();
      }
    } else {
      debugPrint('[MusicSeederService.seedFiles] Unexpected rawStats format: ${decoded.runtimeType}');
    }

    final Set<String> activeTorrentNames = currentTorrents
        .map((t) => t['name']?.toString())
        .whereType<String>()
        .toSet();

    final libtorrent = LibtorrentService();

    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) continue;

      final title = p.basenameWithoutExtension(path).replaceAll(RegExp(r"[^\w\s]"), "_");
      final torrentFilePath = p.join(torrentsDir, '$title.torrent');
      final torrentFile = File(torrentFilePath);

      String torrentName = title;

      if (!await torrentFile.exists()) {
        final createdName = await libtorrent.createTorrentAndGetName(path);
        if (createdName == null) continue;
        torrentName = createdName;
      }

      if (!activeTorrentNames.contains(torrentName)) {
        await libtorrent.addTorrent(
          torrentFilePath,
          p.dirname(path),
          seedMode: true,
          announce: false,
          enableDHT: false, // Disabled due to removal of infoHash
          enableLSD: true,
          enableUTP: true,
          enableTrackers: false,
          enablePeerExchange: true,
        );
      }

      // NOTE: putEncryptedSwarmData removed or should be adapted to work without hashes

      if (!knownTorrentNames.contains(torrentName)) {
        knownTorrentNames.add(torrentName);
        _nameToPathMap[torrentName] = path;
        // Save method calls if you want persistence here
      }

      await Future.delayed(delayBetweenAdds);
    }
  }

  Future<Map<String, dynamic>?> getMetadataForName(String torrentName) async {
    if (_metadataCache.containsKey(torrentName)) return _metadataCache[torrentName];
    final path = _nameToPathMap[torrentName];
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final metadata = await MetadataRetriever.fromFile(file);
    final metaMap = {
      'title': metadata.trackName ?? '',
      'artist': metadata.authorName ?? '',
      'album': metadata.albumName ?? '',
      'albumArt': metadata.albumArt,
      'duration': metadata.trackDuration ?? 0,
    };
    _metadataCache[torrentName] = metaMap;
    return metaMap;
  }

  String? getTorrentFilePathForName(String torrentName) {
    if (!knownTorrentNames.contains(torrentName)) return null;
    final title = p.basenameWithoutExtension(_nameToPathMap[torrentName] ?? torrentName)
        .replaceAll(RegExp(r"[^\w\s]"), "_");
    return p.join(torrentsDir, '$title.torrent');
  }

  Future<void> addTorrentByName(String torrentName) async {
    final libtorrent = LibtorrentService();
    final path = _nameToPathMap[torrentName];
    if (path == null || path.isEmpty) return;

    final torrentPath = getTorrentFilePathForName(torrentName);
    if (torrentPath == null || !File(torrentPath).existsSync()) return;

    await libtorrent.addTorrent(
      torrentPath,
      p.dirname(path),
      seedMode: true,
      announce: false,
      enableDHT: false,
      enableLSD: true,
      enableUTP: true,
      enableTrackers: false,
      enablePeerExchange: true,
    );
  }
}

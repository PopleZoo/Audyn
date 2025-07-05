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
  final Set<String> knownTorrentNames = {}; // Normalized torrent names
  late final String torrentsDir;

  final Map<String, String> _nameToPathMap = {}; // normalizedName -> full file path
  final Map<String, Map<String, dynamic>?> _metadataCache = {};

  Map<String, String> get nameToPathMap => _nameToPathMap;

  MusicSeederService([OnAudioQuery? audioQuery])
      : audioQuery = audioQuery ?? OnAudioQuery() {
    debugPrint('[MusicSeederService] Constructor called');
  }

  static const List<String> allowedExtensions = ['.mp3', '.flac', '.wav', '.m4a'];

  /// Normalize torrent names to a consistent key format for indexing
  /// Example: "Tenacious D - Video Games.mp3" -> "tenacious_d___video_games"
  static String normalizeTorrentName(String name) {
    return p.basenameWithoutExtension(name)
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w]+"), "_");
  }

  Future<void> _initPaths() async {
    final directory = await getApplicationDocumentsDirectory();
    torrentsDir = p.join(directory.path, 'torrents');
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
        final torrentNameRaw = torrent['name']?.toString();
        if (torrentNameRaw == null || torrentNameRaw.isEmpty) continue;

        final normalized = normalizeTorrentName(torrentNameRaw);
        await LibtorrentWrapper.removeTorrentByName(torrentNameRaw);
        knownTorrentNames.remove(normalized);
        _nameToPathMap.remove(normalized);
        _metadataCache.remove(normalized);
      }
    } catch (_) {}

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

    final Set<String> activeTorrentNamesRaw = currentTorrents
        .map((t) => t['name']?.toString())
        .whereType<String>()
        .toSet();

    // Normalize active torrent names for quick lookup
    final Set<String> activeTorrentNames = activeTorrentNamesRaw.map(normalizeTorrentName).toSet();

    final libtorrent = LibtorrentService();

    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) continue;

      // Use normalized title for torrent name
      final normalizedTitle = normalizeTorrentName(path);
      final torrentFilePath = p.join(torrentsDir, '$normalizedTitle.torrent');
      final torrentFile = File(torrentFilePath);

      String torrentName = normalizedTitle;

      if (!await torrentFile.exists()) {
        final createdName = await libtorrent.createTorrentAndGetName(path);
        if (createdName == null) continue;

        // Normalize created torrent name
        torrentName = normalizeTorrentName(createdName);
      }

      if (!activeTorrentNames.contains(torrentName)) {
        await libtorrent.addTorrent(
          torrentFilePath,
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

      if (!knownTorrentNames.contains(torrentName)) {
        knownTorrentNames.add(torrentName);
        _nameToPathMap[torrentName] = path;
      }

      await Future.delayed(delayBetweenAdds);
    }
  }

  Future<Map<String, dynamic>?> getMetadataForName(String torrentName) async {
    final normalizedName = normalizeTorrentName(torrentName);

    if (_metadataCache.containsKey(normalizedName)) return _metadataCache[normalizedName];

    final path = _nameToPathMap[normalizedName];
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final metadata = await MetadataRetriever.fromFile(file);
      final metaMap = {
        'title': metadata.trackName ?? '',
        'artist': metadata.authorName ?? '',
        'album': metadata.albumName ?? '',
        'albumArt': metadata.albumArt,
        'duration': metadata.trackDuration ?? 0,
      };
      _metadataCache[normalizedName] = metaMap;
      return metaMap;
    } catch (e) {
      debugPrint('[getMetadataForName] Failed to read metadata for $torrentName: $e');
      return null;
    }
  }

  String? getTorrentFilePathForName(String torrentName) {
    final normalizedName = normalizeTorrentName(torrentName);
    if (!knownTorrentNames.contains(normalizedName)) return null;

    final filePath = _nameToPathMap[normalizedName];
    if (filePath == null) return null;

    final normalizedTitle = normalizeTorrentName(filePath);
    return p.join(torrentsDir, '$normalizedTitle.torrent');
  }

  Future<void> addTorrentByName(String torrentName) async {
    final libtorrent = LibtorrentService();
    final normalizedName = normalizeTorrentName(torrentName);

    final path = _nameToPathMap[normalizedName];
    if (path == null || path.isEmpty) return;

    final torrentPath = getTorrentFilePathForName(normalizedName);
    if (torrentPath == null || !File(torrentPath).existsSync()) return;

    await libtorrent.addTorrent(
      torrentPath,
      p.dirname(path),
      seedMode: true,
      announce: false,
      enableDHT: true,
      enableLSD: true,
      enableUTP: true,
      enableTrackers: false,
      enablePeerExchange: true,
    );
  }
}

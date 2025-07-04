// SwarmView.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../bloc/Downloads/DownloadsBloc.dart';
import '../../../../bloc/playlists/playlists_cubit.dart';
import '../../../../data/services/LibtorrentService.dart';

/// Background isolate function to check if a specific file exists in a directory.
Future<bool> probeFilePresence(List<String> args) async {
  final dirPath = args[0];
  final fileName = args[1];
  try {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      debugPrint('[probe] dir missing: $dirPath');
      return false;
    }
    final target = File(p.join(dirPath, fileName));
    final exists = await target.exists();
    debugPrint('[probe] ${target.path} -> $exists');
    return exists;
  } catch (e, st) {
    debugPrint('[probe] error: $e\n$st');
    return false;
  }
}

class SwarmView extends StatefulWidget {
  const SwarmView({Key? key}) : super(key: key);

  @override
  _SwarmViewState createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  final LibtorrentService _libtorrentService = LibtorrentService();
  final MusicSeederService _musicSeeder = MusicSeederService();

  List<Map<String, dynamic>> _torrents = [];
  List<Map<String, dynamic>> _filteredTorrents = [];
  final Map<String, Map<String, dynamic>> _metadataCache = {};

  bool _isLoading = true;
  bool _isError = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initSeedingAndFetch();
  }

  Future<void> _initSeedingAndFetch() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      await _musicSeeder.init();
      await _musicSeeder.seedMissingSongs();
      await _fetchTorrentStats();
    } catch (e) {
      debugPrint('[init] seeding failed: $e');
      setState(() {
        _isError = true;
        _isLoading = false;
      });
    }
  }

  /// Check if audio files exist in the torrent save directory.
  Future<bool> _isTorrentFilesPresent(String infoHash, String expectedFileName) async {
    final savePath = await _libtorrentService.getTorrentSavePath(infoHash);
    if (savePath == null || savePath.isEmpty) {
      debugPrint('[presence] savePath null for $infoHash');
      return false;
    }

    try {
      final dir = Directory(savePath);
      if (!await dir.exists()) {
        debugPrint('[presence] directory does not exist: $savePath');
        return false;
      }

      final files = await dir.list().toList();
      final hasAudioFile = files.any((entity) =>
      entity is File &&
          (entity.path.toLowerCase().endsWith('.mp3') ||
              entity.path.toLowerCase().endsWith('.m4a') ||
              entity.path.toLowerCase().endsWith('.flac') ||
              entity.path.toLowerCase().endsWith('.wav')));

      debugPrint('[presence] audio files in $savePath: $hasAudioFile');
      return hasAudioFile;
    } catch (e, st) {
      debugPrint('[presence] error scanning directory: $e\n$st');
      return false;
    }
  }

  Future<String> _torrentFilePath(String infoHash) async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, 'torrents', '$infoHash.torrent');
  }

  Future<void> _fetchTorrentStats() async {
    setState(() => _isLoading = true);

    try {
      final rawStats = await _libtorrentService.getTorrentStats();
      debugPrint('[fetch] rawStats: $rawStats');

      if (rawStats == null || rawStats.isEmpty) {
        debugPrint('[fetch] no torrent stats returned');
        setState(() {
          _torrents = [];
          _filteredTorrents = [];
          _isError = false;
          _isLoading = false;
        });
        return;
      }

      final torrents = (jsonDecode(rawStats) as List).cast<Map<String, dynamic>>();
      for (final t in torrents) {
        final infoHash = (t['info_hash'] ?? '').toString().toLowerCase();
        if (infoHash.isEmpty) continue;

        if (!_metadataCache.containsKey(infoHash)) {
          final meta = await _musicSeeder.getMetadataForHash(infoHash);
          _metadataCache[infoHash] = {
            'meta_title': meta?['title'] ?? t['name'] ?? infoHash,
            'meta_artist': meta?['artist'] ?? '',
            'meta_album': meta?['album'] ?? '',
            'meta_albumArt': meta?['albumArt'], // May be null or Uint8List
          };
        }
        t.addAll(_metadataCache[infoHash]!);

        final fileName = '${_metadataCache[infoHash]!['meta_title'] ?? infoHash}.mp3';
        final hasFiles = await _isTorrentFilesPresent(infoHash, fileName);
        t['file_found'] = hasFiles;

        if (!hasFiles) {
          debugPrint('[fetch] skip – file missing for $infoHash');
          continue;
        }

        final torrentPath = await _torrentFilePath(infoHash);
        if (!File(torrentPath).existsSync()) {
          debugPrint('[fetch] .torrent missing – not re-adding $infoHash');
          continue;
        }

        try {
          await _libtorrentService.removeTorrent(infoHash);
          await _musicSeeder.addTorrentByHash(infoHash);
          debugPrint('[fetch] re-seeded $infoHash');
        } catch (e, st) {
          debugPrint('[fetch] re-add failed for $infoHash: $e\n$st');
        }
      }

      setState(() {
        _torrents = torrents;
        _applySearchFilter();
        _isError = false;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('[fetch] fatal error: $e\n$st');
      setState(() {
        _isLoading = false;
        _isError = true;
      });
    }
  }

  void _applySearchFilter() {
    final q = _searchQuery.toLowerCase();
    _filteredTorrents = _torrents.where((t) {
      return (t['info_hash'] ?? '').toString().toLowerCase().contains(q) ||
          (t['meta_title'] ?? '').toString().toLowerCase().contains(q) ||
          (t['meta_artist'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<String?> _getSavedPath(String infoHash) async {
    final path = await _libtorrentService.getTorrentSavePath(infoHash);
    return (path != null && path.isNotEmpty) ? path : null;
  }

  Future<List<String>> _getPlaylists(String infoHash) async {
    try {
      final playlistsCubit = context.read<PlaylistsCubit>();
      final playlists = playlistsCubit.state is PlaylistsLoaded
          ? (playlistsCubit.state as PlaylistsLoaded).playlists
          : <PlaylistModel>[];

      final fileName = '${_metadataCache[infoHash]?['meta_title'] ?? infoHash}.mp3';

      List<String> matchedPlaylists = [];

      for (final p in playlists) {
        final playlistSongs =
        await OnAudioQuery().queryAudiosFrom(AudiosFromType.PLAYLIST, p.id);
        final match = playlistSongs.any((song) =>
        song.title.toLowerCase().contains(fileName.toLowerCase()) ||
            fileName.toLowerCase().contains(song.title.toLowerCase()));

        if (match) matchedPlaylists.add(p.playlist);
      }

      return matchedPlaylists;
    } catch (e) {
      debugPrint('[getPlaylists] Error fetching playlists: $e');
      return [];
    }
  }

  Future<void> _handleTorrentTap(Map<String, dynamic> torrent) async {
    final infoHash = (torrent['info_hash'] ?? '').toString();
    final title = (torrent['meta_title'] ?? torrent['name'] ?? infoHash).toString();
    final isLocal = (torrent['file_found'] ?? false) as bool;

    if (isLocal) {
      final savedPath = await _getSavedPath(infoHash) ?? 'Unknown location';
      final playlists = await _getPlaylists(infoHash);
      final playlistStr = playlists.isEmpty ? 'Not in any playlist' : playlists.join(', ');

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('"$title" is already downloaded'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Stored at:'),
              SelectableText(savedPath, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('Playlist(s):'),
              SelectableText(playlistStr),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    // Not local — prompt user for download folder and optional playlist input
    final result = await showDialog<({String folder, List<String> playlists})?>(
      context: context,
      builder: (ctx) {
        final folderCtl = TextEditingController();
        final playlistCtl = TextEditingController();

        return AlertDialog(
          title: Text('Download "$title"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: folderCtl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Destination folder',
                  hintText: 'Tap to choose',
                ),
                onTap: () async {
                  final picked = await FilePicker.platform.getDirectoryPath();
                  if (picked != null) folderCtl.text = picked;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: playlistCtl,
                decoration: const InputDecoration(
                  labelText: 'Playlist(s)',
                  hintText: 'Comma‑separated (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              child: const Text('Download'),
              onPressed: () {
                final folder = folderCtl.text.trim();
                if (folder.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please choose a folder.')),
                  );
                  return;
                }
                final playlists = playlistCtl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                Navigator.pop(ctx, (folder: folder, playlists: playlists));
              },
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.folder.isEmpty) return;

    context.read<DownloadsBloc>().add(
      StartDownload(
        infoHash: infoHash,
        name: title,
        destinationFolder: result.folder,
        playlist: result.playlists,
      ),
    );

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Downloading "$title"…')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchTorrentStats,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search torrents',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applySearchFilter();
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isError
                ? const Center(
              child: Text(
                'Failed to load torrents.',
                style: TextStyle(color: Colors.red),
              ),
            )
                : RefreshIndicator(
              onRefresh: _fetchTorrentStats,
              child: _filteredTorrents.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: Text('No torrents found.'),
                    ),
                  ),
                ],
              )
                  : ListView.builder(
                itemCount: _filteredTorrents.length,
                itemBuilder: (context, i) {
                  final t = _filteredTorrents[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    leading: t['meta_albumArt'] != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        t['meta_albumArt'] as Uint8List,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(
                      Icons.music_note,
                      size: 48,
                      color: (t['file_found'] ?? false)
                          ? Colors.grey
                          : Colors.purpleAccent,
                    ),
                    title: Text(
                      (t['meta_title'] ?? 'Unknown').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: (t['file_found'] ?? false)
                            ? Colors.grey
                            : null,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((t['meta_artist'] ?? '').toString().isNotEmpty)
                          Text(
                            t['meta_artist'],
                            style: TextStyle(
                              fontSize: 14,
                              color: (t['file_found'] ?? false)
                                  ? Colors.grey
                                  : null,
                            ),
                          ),
                        if ((t['meta_album'] ?? '').toString().isNotEmpty)
                          Text(
                            t['meta_album'],
                            style: TextStyle(
                              fontSize: 12,
                              color: (t['file_found'] ?? false)
                                  ? Colors.grey.withOpacity(0.5)
                                  : Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (_) {
                            final state = t['state'] ?? -1;
                            final states = [
                              'Queued',
                              'Checking',
                              'Downloading Metadata',
                              'Downloading',
                              'Finished',
                              'Seeding',
                              'Allocating',
                              'Checking Resume',
                              'Unknown'
                            ];
                            final displayState = (state >= 0 && state < states.length)
                                ? states[state]
                                : 'Unknown';
                            final upload = ((t['upload_rate'] ?? 0) / 1024).toStringAsFixed(1);
                            final download =
                            ((t['download_rate'] ?? 0) / 1024).toStringAsFixed(1);
                            final seeders = t['seeders'] ?? 0;
                            final peers = t['peers'] ?? 0;

                            return Text(
                              '$displayState • Seeders: $seeders • Peers: $peers\n↑ $upload KB/s • ↓ $download KB/s',
                              style: TextStyle(
                                fontSize: 11,
                                color: (t['file_found'] ?? false) ? Colors.grey : null,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    trailing: (t['file_found'] ?? false)
                        ? Icon(Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary)
                        : (t['state'] == 5
                        ? const Icon(Icons.verified, color: Colors.lightBlueAccent)
                        : null),
                    onTap: () => _handleTorrentTap(t),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

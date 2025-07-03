import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:audyn/utils/file_probe.dart';
import '../../../../../services/music_seeder_service.dart';
import '../../../../../services/swarm_metadata_service.dart';
import '../../../../bloc/Downloads/DownloadsBloc.dart';
import '../../../../data/services/LibtorrentService.dart';
import '../home_page.dart';

class SwarmView extends StatefulWidget {
  const SwarmView({Key? key}) : super(key: key);

  @override
  _SwarmViewState createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  final LibtorrentService _libtorrentService = LibtorrentService();
  final MusicSeederService _musicSeeder = MusicSeederService();
  final SwarmMetadataService _metadataService = SwarmMetadataService(useMock: false);

  List<Map<String, dynamic>> _torrents = [];
  List<Map<String, dynamic>> _filteredTorrents = [];
  final Map<String, Map<String, dynamic>> _metadataCache = {};

  bool _isLoading = true;
  bool _isError = false;
  String _searchQuery = '';
  bool _userLoggedIn = false;

  final supabase = Supabase.instance.client;
  RealtimeChannel? _realtime;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  @override
  void dispose() {
    _realtime?.unsubscribe();
    super.dispose();
  }

  Future<void> clearAllTorrents() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Remove all torrents from local libtorrent
      await removeAllTorrents();

      // 2. Delete all seeder_peers rows for this user
      await supabase.from('seeder_peers').delete().eq('user_id', userId);

      // 3. Delete all torrents rows for this user (if you track ownership)
      await supabase.from('torrents').delete().eq('owner_id', userId);

      // 4. Clear local caches and torrent lists
      setState(() {
        _torrents.clear();
        _filteredTorrents.clear();
        _metadataCache.clear();
      });

      // 5. Refresh torrent stats / UI
      await _fetchTorrentStats();
    } catch (e, st) {
      debugPrint('clearAllTorrents error: $e\n$st');
      setState(() {
        _isError = true;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> removeAllTorrents() async {
    final torrents = await _libtorrentService.getAllTorrents();
    for (final t in torrents) {
      final infoHash = t['info_hash'];
      if (infoHash != null) {
        await _libtorrentService.removeTorrent(infoHash);
      }
    }
  }

  Future<void> _checkLogin() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      await _promptLogin();
      return;
    }

    setState(() => _userLoggedIn = true);

    _realtime = supabase.channel('public:seeder_peers')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        table: 'seeder_peers',
        callback: (_) => _fetchTorrentStats(),
      )
      ..subscribe();

    await _initSeedingAndFetch();
  }

  Future<void> _promptLogin() async {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );

    if (loggedIn == true) {
      await _checkLogin();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
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
      setState(() {
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTorrentStats() async {
    setState(() => _isLoading = true);

    try {
      final rawStats = await _libtorrentService.getTorrentStats();
      final torrents = (jsonDecode(rawStats) as List).cast<Map<String, dynamic>>();

      final userId = supabase.auth.currentUser!.id;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final upserts = <Map<String, dynamic>>[];
      final deletions = <String>[];

      for (final t in torrents) {
        final infoHash = (t['info_hash'] ?? '').toString();
        if (infoHash.isEmpty) continue;

        final hasFiles = await _isTorrentFilesPresent(infoHash);

        // Remove and re-add torrent if hash exists and files are present, to restart seeding
        if (hasFiles) {
          // Remove existing torrent from libtorrent before re-adding
          await _libtorrentService.removeTorrent(infoHash);

          // Re-add the torrent via the musicSeeder or libtorrentService
          // Assuming _musicSeeder has a method for this (adjust if different)
          await _musicSeeder.addTorrentByHash(infoHash);

          // Then prepare upsert for supabase
          final exists = await supabase
              .from('torrents')
              .select('info_hash')
              .eq('info_hash', infoHash)
              .maybeSingle();

          if (exists != null) {
            upserts.add({'user_id': userId, 'info_hash': infoHash, 'last_seen': nowIso});
          } else {
            debugPrint('⚠️ Skipping peer insert: infoHash $infoHash missing from torrents table');
          }
        } else {
          deletions.add(infoHash);
        }

        // Cache metadata
        if (!_metadataCache.containsKey(infoHash)) {
          final SongMetadata? meta = await _metadataService.getMetadataByHash(infoHash);
          final fallback = await _musicSeeder.getMetadataForHash(infoHash) ?? {};
          _metadataCache[infoHash] = meta != null
              ? {
            'title': meta.title,
            'artist': meta.artist,
            'album': meta.album ?? '',
            'albumArt': null,
          }
              : fallback;
        }
        _metadataCache[infoHash]!.forEach((k, v) => t['meta_$k'] = v);
      }

      // Upsert all peers that have files present
      if (upserts.isNotEmpty) {
        await supabase.from('seeder_peers').upsert(upserts);
      }

      // Delete seeder_peers entries for torrents that no longer have files locally
      if (deletions.isNotEmpty) {
        final deleteFutures = deletions.map((hash) {
          return supabase.from('seeder_peers').delete().eq('user_id', userId).eq('info_hash', hash);
        });
        await Future.wait(deleteFutures);
      }

      // Rest of your existing logic for seeder counts etc...
      // ...

      setState(() {
        _torrents = torrents;
        _applySearchFilter();
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('SwarmView fetch error: $e\n$st');
      setState(() {
        _isLoading = false;
        _isError = true;
      });
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────
  void _applySearchFilter() {
    final q = _searchQuery.toLowerCase();
    _filteredTorrents = _torrents.where((t) {
      return (t['info_hash'] ?? '').toString().toLowerCase().contains(q) ||
          (t['meta_title'] ?? '').toString().toLowerCase().contains(q) ||
          (t['meta_artist'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<bool> _isTorrentFilesPresent(String infoHash) async {
    final savePath = await _libtorrentService.getTorrentSavePath(infoHash);
    debugPrint('Checking torrent files presence for infoHash=$infoHash at path: $savePath');

    if (savePath == null || savePath.isEmpty) return false;

    try {
      // Ensure the directory exists, create if missing
      await ensureDirectoryExists(savePath);

      final result = await compute(probeFilePresence, savePath);
      return result;
    } catch (e, st) {
      debugPrint('❌ Error in compute for probeFilePresence with path "$savePath": $e\n$st');
      rethrow;
    }
  }

  bool _probe(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    return dir.listSync(recursive: true, followLinks: false).any((e) => e is File);
  }

  Future<void> _handleTorrentTap(Map<String, dynamic> torrent) async {
    final infoHash = (torrent['info_hash'] ?? '').toString();
    final displayTitle = (torrent['meta_title'] as String?)?.trim() ?? 'Unknown';

    final isSeeding = (torrent['state'] ?? -1) == 5;

    final isLocalFile = await _isTorrentFilesPresent(infoHash);

    if (isSeeding && !isLocalFile) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cannot download "$displayTitle" because you are seeding but files are not present locally.',
            ),
          ),
        );
      }
      return;
    }

    if (isLocalFile) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$displayTitle" is already downloaded.')),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download?'),
        content: Text('Do you want to download "$displayTitle"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download')),
        ],
      ),
    );

    if (confirm != true) return;

    final destinationFolder = await pickFolder();
    final List<String> playlist = await pickPlaylist();

    if (!mounted) return;

    context.read<DownloadsBloc>().add(
      StartDownload(
        infoHash: infoHash,
        name: displayTitle,
        destinationFolder: destinationFolder,
        playlist: playlist,
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "$displayTitle" to downloads')),
      );
      Navigator.pushNamed(context, '/downloads');
    }
  }

  Future<String> pickFolder() async {
    try {
      String? folderPath = await FilePicker.platform.getDirectoryPath();
      return folderPath ?? '';
    } catch (e) {
      debugPrint('pickFolder error: $e');
      return '';
    }
  }

  Future<List<String>> pickPlaylist() async {
    final result = await _askForPlaylist();
    if (result == null) return [];
    return result;
  }

  Future<List<String>?> _askForPlaylist() async {
    final controller = TextEditingController();

    final result = await showDialog<List<String>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Playlist (optional)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter playlist items separated by commas',
            hintText: 'e.g. song1,song2,song3',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                Navigator.pop(ctx, <String>[]);
              } else {
                final list = text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                Navigator.pop(ctx, list);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return result;
  }

  Widget buildTorrentTile(Map<String, dynamic> t, VoidCallback onTap) {
    final name = t['name'] ?? 'Unknown';
    final uploadRateKb = (t['upload_rate'] ?? 0) / 1024;
    final downloadRateKb = (t['download_rate'] ?? 0) / 1024;

    final displayTitle = (t['meta_title'] as String?)?.trim() ?? 'unknown';
    final displayArtist = (t['meta_artist'] as String?)?.trim() ?? 'unknown';
    final displayAlbum = (t['meta_album'] as String?)?.trim() ?? 'unknown';
    final Uint8List? albumArt = t['meta_albumArt'] as Uint8List?;

    final bool isSeeding = (t['state'] ?? -1) == 5;
    final bool isLocalFile = (t['file_found'] ?? false) == true;
    final String infoHash = (t['info_hash'] ?? '').toString();
    final bool isKnown = _musicSeeder.knownHashes.contains(infoHash);

    final int dbSeeders = t['db_seeders'] ?? 0; // From Supabase

    const states = [
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
    final int state = t['state'] ?? -1;
    final String displayState = (state >= 0 && state < states.length) ? states[state] : 'Unknown';
    final int seeders = t['seeders'] ?? 0; // from libtorrent swarm
    final int peers = t['peers'] ?? 0;

    return ListTile(
      enabled: !isLocalFile,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      leading: albumArt != null
          ? ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(albumArt, width: 56, height: 56, fit: BoxFit.cover),
      )
          : Icon(
        Icons.music_note,
        size: 48,
        color: isLocalFile ? Colors.grey : Colors.purpleAccent,
      ),
      title: Text(
        displayTitle.isNotEmpty ? displayTitle : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isLocalFile ? Colors.grey : null),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (displayArtist.isNotEmpty)
            Text(
              displayArtist,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isLocalFile ? Colors.grey : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (displayAlbum.isNotEmpty)
            Text(
              displayAlbum,
              style: TextStyle(
                fontSize: 12,
                color: (Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ?? Colors.grey)
                    .withOpacity(isLocalFile ? 0.4 : 1.0),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            '$displayState • Seeders (swarm): $seeders • Peers: $peers\nSeeders (database): $dbSeeders\n↑ ${uploadRateKb.toStringAsFixed(1)} KB/s • ↓ ${downloadRateKb.toStringAsFixed(1)} KB/s',
            style: TextStyle(
              fontSize: 12,
              color: isLocalFile ? Colors.grey : null,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: isKnown
          ? const Icon(Icons.cloud_done_rounded, color: Colors.greenAccent)
          : (isSeeding
          ? const Icon(Icons.verified, color: Colors.lightBlueAccent)
          : (isLocalFile
          ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
          : null)),
      onTap: isLocalFile ? null : onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_userLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audyn Swarm')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Waiting for login...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            tooltip: 'Clear All Torrents',
            icon: const Icon(Icons.delete_forever),
            onPressed: _isLoading
                ? null
                : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear All Torrents?'),
                  content: const Text(
                      'This will remove all torrents and clear related data. This action cannot be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear All')),
                  ],
                ),
              );
              if (confirm == true) {
                await clearAllTorrents();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search torrents',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
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
                style: TextStyle(color: Colors.redAccent),
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
                    child: Center(child: Text('No torrents found.')),
                  ),
                ],
              )
                  : ListView.builder(
                itemCount: _filteredTorrents.length,
                itemBuilder: (context, index) => buildTorrentTile(
                  _filteredTorrents[index],
                      () => _handleTorrentTap(_filteredTorrents[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> ensureDirectoryExists(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('Directory does not exist, creating: $path');
      await dir.create(recursive: true);
    }
  }

// Your existing probe function can stay as is
  bool probeFilePresence(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    return dir.listSync(recursive: true, followLinks: false).any((e) => e is File);
  }

}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../../services/music_seeder_service.dart';
import '../../../../data/services/LibtorrentService.dart';

// Paste or import your buildTorrentTile function here
Widget buildTorrentTile(
    Map<String, dynamic> t,
    BuildContext context,
    VoidCallback onTap,
    ) {
  final name = t['name'] ?? 'Unknown';
  final uploadRateKb = (t['upload_rate'] ?? 0) / 1024;
  final downloadRateKb = (t['download_rate'] ?? 0) / 1024;

  final displayTitle = (t['meta_title'] as String?)?.trim() ?? 'unknown';
  final displayArtist = (t['meta_artist'] as String?)?.trim() ?? 'unknown';
  final displayAlbum = (t['meta_album'] as String?)?.trim() ?? 'unknown';
  final Uint8List? albumArt = t['meta_albumArt'] as Uint8List?;

  final bool isSeeding = (t['state'] ?? -1) == 5; // Seeding state index
  final bool isLocalFile = (t['file_found'] ?? false) == true;

  String mapState(int state) {
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
    return (state >= 0 && state < states.length) ? states[state] : 'Unknown';
  }

  String getDisplayState(Map<String, dynamic> t) {
    final bool local = (t['file_found'] ?? false) == true;
    final int state = t['state'] ?? -1;
    final int seeders = t['seeders'] ?? 0;
    final int peers = t['peers'] ?? 0;

    if (local) {
      return "Local • Seeders: $seeders • Peers: $peers";
    }

    return "${mapState(state)} • Seeders: $seeders • Peers: $peers";
  }

  return ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    leading: albumArt != null
        ? ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(albumArt, width: 56, height: 56, fit: BoxFit.cover),
    )
        : const Icon(Icons.music_note, size: 48, color: Colors.purpleAccent),
    title: Text(
      displayTitle.isNotEmpty ? displayTitle : name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (displayArtist.isNotEmpty)
          Text(
            displayArtist,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (displayAlbum.isNotEmpty)
          Text(
            displayAlbum,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ?? Colors.grey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        Text(
          '${getDisplayState(t)}\n↑ ${uploadRateKb.toStringAsFixed(1)} KB/s • ↓ ${downloadRateKb.toStringAsFixed(1)} KB/s',
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
    isThreeLine: true,
    trailing: isSeeding
        ? const Icon(Icons.verified, color: Colors.lightBlueAccent)
        : (isLocalFile ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null),
    onTap: onTap,
  );
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
  bool _isLoading = true;
  bool _isError = false;
  String _searchQuery = '';
  bool _disclaimerAccepted = false;
  Timer? _periodicTimer;

  // Cache metadata to avoid repeated lookups
  final Map<String, Map<String, dynamic>> _metadataCache = {};

  @override
  void initState() {
    super.initState();
    _showDisclaimerIfNeeded();

    _periodicTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _disclaimerAccepted) {
        _fetchTorrentStats();
      }
    });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  Future<void> _showDisclaimerIfNeeded() async {
    await Future.delayed(Duration.zero);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Disclaimer'),
        content: const Text(
          'This feature is experimental and data may be incomplete or inconsistent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      setState(() {
        _disclaimerAccepted = true;
      });

      try {
        await _musicSeeder.init();
        await _musicSeeder.seedMissingSongs();
        debugPrint('[SwarmView] User music seeding started after consent.');
      } catch (e) {
        debugPrint('[SwarmView] Failed to seed user music: $e');
      }

      await _fetchTorrentStats();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _fetchTorrentStats() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final rawStats = await _libtorrentService.getTorrentStats();
      final List<Map<String, dynamic>> torrents = (jsonDecode(rawStats) as List)
          .whereType<Map<String, dynamic>>()
          .toList();

      for (final torrent in torrents) {
        final infoHash = torrent['info_hash']?.toString() ?? '';
        if (infoHash.isEmpty) continue;

        // Fetch metadata once
        if (!_metadataCache.containsKey(infoHash)) {
          final metadata = await _libtorrentService.getTorrentMetadata(infoHash);
          _metadataCache[infoHash] = metadata ?? {};
        }

        // Merge metadata into torrent map with meta_ prefix
        final metadata = _metadataCache[infoHash] ?? {};
        metadata.forEach((key, value) {
          torrent['meta_$key'] = value;
        });
      }

      setState(() {
        _torrents = torrents;
        _applySearchFilter();
        _isLoading = false;
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isError = true;
      });
      debugPrint('[SwarmView] Failed to fetch torrent stats: $e');
    }
  }

  void _applySearchFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredTorrents = List.from(_torrents);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredTorrents = _torrents.where((torrent) {
        final infoHash = (torrent['info_hash'] ?? '').toString().toLowerCase();
        final name = (_metadataCache[infoHash]?['name'] ?? '').toString().toLowerCase();
        final artist = (_metadataCache[infoHash]?['artist'] ?? '').toString().toLowerCase();
        return infoHash.contains(query) ||
            name.contains(query) ||
            artist.contains(query);
      }).toList();
    }
  }

  void _onTorrentTap(Map<String, dynamic> torrent) {
    final infoHash = (torrent['info_hash'] ?? '').toString();
    final meta = _metadataCache[infoHash] ?? {};
    final name = meta['name'] ?? infoHash;
    final artist = meta['artist'] ?? 'Unknown Artist';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: Text('Artist: $artist\nInfo Hash: $infoHash'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetAndRestartSeeding() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _musicSeeder.resetSeedingState();
      await _musicSeeder.seedMissingSongs();
      await _fetchTorrentStats();
      debugPrint('[SwarmView] Seeding reset and restarted.');
    } catch (e) {
      debugPrint('[SwarmView] Failed to reset and restart seeding: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_disclaimerAccepted) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset and Restart Seeding',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Confirm Reset'),
                  content: const Text(
                    'This will clear all swarm data and restart seeding. Continue?',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                  ],
                ),
              );
              if (confirm == true) {
                await _resetAndRestartSeeding();
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
                ? Center(
              child: Text(
                'Failed to load torrents. Pull down to retry.',
                style: const TextStyle(color: Colors.redAccent),
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
                  context,
                      () => _onTorrentTap(_filteredTorrents[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

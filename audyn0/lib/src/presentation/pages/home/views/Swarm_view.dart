import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../services/music_seeder_service.dart';
import '../../../../bloc/Downloads/DownloadsBloc.dart';
import '../../../../data/services/LibtorrentService.dart';

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
      setState(() => _disclaimerAccepted = true);

      try {
        await _musicSeeder.init();
        await _musicSeeder.seedMissingSongs();
        debugPrint('[SwarmView] Music seeding started after consent.');
      } catch (e) {
        debugPrint('[SwarmView] Failed to seed music: $e');
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

        if (!_metadataCache.containsKey(infoHash)) {
          final metadata = await _musicSeeder.getMetadataForHash(infoHash);
          _metadataCache[infoHash] = metadata ?? {};
        }

        final meta = _metadataCache[infoHash]!;
        meta.forEach((key, value) {
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
      debugPrint('[SwarmView] Error: $e');
      setState(() {
        _isLoading = false;
        _isError = true;
      });
    }
  }

  void _applySearchFilter() {
    final query = _searchQuery.trim().toLowerCase();
    _filteredTorrents = _torrents.where((torrent) {
      final infoHash = (torrent['info_hash'] ?? '').toString().toLowerCase();
      final title = (torrent['meta_title'] ?? '').toString().toLowerCase();
      final artist = (torrent['meta_artist'] ?? '').toString().toLowerCase();
      return infoHash.contains(query) || title.contains(query) || artist.contains(query);
    }).toList();
  }

  Future<void> _handleTorrentTap(Map<String, dynamic> torrent) async {
    final infoHash = (torrent['info_hash'] ?? '').toString();
    final displayTitle = (torrent['meta_title'] as String?)?.trim() ?? 'Unknown';

    final isSeeding = (torrent['state'] ?? -1) == 5;

    // Check if files are actually local on disk:
    final isLocalFile = await _isTorrentFilesPresent(infoHash);

    if (isSeeding && !isLocalFile) {
      // You are seeding, but files are not physically found => show proper message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot download "$displayTitle" because you are seeding but files are not present locally.'),
        ),
      );
      return;
    }

    if (isLocalFile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$displayTitle" is already downloaded.')),
      );
      return;
    }

    // If neither local nor seeding => proceed to download prompt
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

    // Prompt for folder and playlist (implement folder picker here)
    final destinationFolder = await pickFolder(); // Implement folder picker dialog
    final List<String> playlist = await pickPlaylist(); // Implement playlist selection dialog or leave empty

    context.read<DownloadsBloc>().add(
      StartDownload(
        infoHash: infoHash,
        name: displayTitle,
        destinationFolder: destinationFolder,
        playlist: playlist,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "$displayTitle" to downloads')),
    );

    Navigator.pushNamed(context, '/downloads');
  }

  Future<String> pickFolder() async {
    try {
      String? folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath == null) {
        // User canceled the picker
        return '';
      }
      return folderPath;
    } catch (e) {
      debugPrint('pickFolder error: $e');
      return '';
    }
  }

  Future<List<String>> pickPlaylist() async {
    final result = await _askForPlaylist();
    if (result == null) {
      return [];
    }
    return result;
  }

// Helper dialog to input playlist (comma separated)
  Future<List<String>?> _askForPlaylist() async {
    TextEditingController controller = TextEditingController();

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
    final int seeders = t['seeders'] ?? 0;
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
            '$displayState • Seeders: $seeders • Peers: $peers\n↑ ${uploadRateKb.toStringAsFixed(1)} KB/s • ↓ ${downloadRateKb.toStringAsFixed(1)} KB/s',
            style: TextStyle(
              fontSize: 12,
              color: isLocalFile ? Colors.grey : null,
            ),
            maxLines: 2,
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
    if (!_disclaimerAccepted) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Audyn Swarm')),
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

  Future<bool> _isTorrentFilesPresent(String infoHash) async {
    try {
      final savePath = await _libtorrentService.getTorrentSavePath(infoHash);
      debugPrint('[SwarmView] getTorrentSavePath for $infoHash: $savePath');
      if (savePath == null || savePath.isEmpty) return false;

      final directory = Directory(savePath);
      if (!await directory.exists()) return false;

      // Recursively list files to find at least one file
      await for (var entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          return true; // Found at least one file
        }
      }
      return false; // No files found
    } catch (e) {
      debugPrint('[SwarmView] _isTorrentFilesPresent error: $e');
      return false;
    }
  }
}

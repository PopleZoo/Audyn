import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:audyn/src/data/services/LibtorrentService.dart';
import 'package:audyn/services/music_seeder_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../bloc/Downloads/DownloadsBloc.dart';

class SwarmView extends StatefulWidget {
  const SwarmView({super.key});

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  final _libtorrentService = LibtorrentService();
  final _audioQuery = OnAudioQuery();
  final _musicSeeder = MusicSeederService(OnAudioQuery());

  String? _version;
  List<Map<String, dynamic>> _torrents = [];
  List<Map<String, dynamic>> _filteredTorrents = [];
  String _searchQuery = '';
  bool _isError = false;
  bool _disclaimerAccepted = false;

  final Map<String, String> _pathLookup = {};

  @override
  void initState() {
    super.initState();
    _showDisclaimerIfNeeded();
  }

  Future<void> _showDisclaimerIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('disclaimerAccepted') ?? false;

    if (!accepted) {
      bool doNotShowAgain = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Before You Seed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'By seeding music, you confirm you have the rights or permission to share your files. '
                      'This app connects users peer-to-peer and does not host any content.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: doNotShowAgain,
                      onChanged: (val) {
                        setDialogState(() => doNotShowAgain = val ?? false);
                      },
                    ),
                    const Expanded(child: Text("Don't show again")),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (doNotShowAgain) {
                    await prefs.setBool('disclaimerAccepted', true);
                  }
                  Navigator.of(context).pop();
                  _disclaimerAccepted = true;
                  await _initialize();
                },
                child: const Text("I Understand"),
              ),
            ],
          ),
        ),
      );
    } else {
      _disclaimerAccepted = true;
      await _initialize();
    }
  }

  Future<void> _initialize() async {

    try {
      final permission = await _audioQuery.permissionsStatus();
      if (!permission) {
        await _audioQuery.permissionsRequest();
      }

      final version = await _libtorrentService.getVersion();
      if (version == null || version.isEmpty) {
        throw Exception("Failed to get Libtorrent version.");
      }
      _version = version;

      unawaited(_seedMissingSongsInBackground());
      unawaited(_fetchTorrentStats());

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _version = 'Error: $e';
      });
    }
  }

  Future<void> _seedMissingSongsInBackground() async {
    try {
      await _musicSeeder.init();

      final songs = await _audioQuery.querySongs();
      _pathLookup.clear();
      for (final song in songs) {
        final filename = File(song.data).uri.pathSegments.last.toLowerCase().trim();
        _pathLookup[filename] = song.data;
      }

      await _musicSeeder.seedMissingSongs();
      await _fetchTorrentStats();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[seedMissingSongsInBackground] Error: $e');
    }
  }

  Future<void> _fetchTorrentStats() async {
    try {
      final raw = await _libtorrentService.getTorrentStats();
      debugPrint('[fetchTorrentStats] raw data: $raw');

      final decoded = jsonDecode(raw);
      if (decoded is! List) throw FormatException("Expected List but got ${decoded.runtimeType}");

      final newTorrents = decoded.whereType<Map<String, dynamic>>().toList();

      for (final newT in newTorrents) {
        final name = newT['name']?.toString() ?? '';
        final index = _torrents.indexWhere((t) => t['name'] == name);
        if (index != -1) {
          _torrents[index] = {..._torrents[index], ...newT};
        } else {
          newT['meta_title'] = '';
          newT['meta_artist'] = '';
          newT['meta_album'] = '';
          newT['meta_albumArt'] = null;
          _torrents.add(newT);
        }
      }

      _torrents.removeWhere((oldT) => !newTorrents.any((newT) => newT['name'] == oldT['name']));

      final enriched = await Future.wait(_torrents.map(_enrichWithMetadata));

      if (!mounted) return;
      setState(() {
        _torrents = enriched;
        _applySearchFilter();
        _isError = false;
      });
    } catch (e) {
      debugPrint('[_fetchTorrentStats] Error: $e');
      if (mounted) setState(() => _isError = true);
    }
  }

  Future<Map<String, dynamic>> _enrichWithMetadata(Map<String, dynamic> t) async {
    String? filePath;

    final infoHash = t['info_hash']?.toString();
    if (infoHash != null && _musicSeeder.hashToPathMap.containsKey(infoHash)) {
      filePath = _musicSeeder.hashToPathMap[infoHash];
    }

    final nameKey = (t['name']?.toString().toLowerCase().trim() ?? '');
    filePath ??= _pathLookup[nameKey];

    final file = filePath != null ? File(filePath) : null;
    final fileExists = file?.existsSync() ?? false;
    t['file_found'] = fileExists;

    if (fileExists) {
      try {
        final meta = await MetadataRetriever.fromFile(file!);
        if (meta.trackArtistNames != null && meta.trackArtistNames!.isNotEmpty) {
          final artists = meta.trackArtistNames!;
          final mainArtist = artists[0];
          final featuredArtists = artists.length > 1 ? artists.sublist(1).join(', ') : '';
          t['meta_artist'] = featuredArtists.isNotEmpty ? '$mainArtist ft. $featuredArtists' : mainArtist;
        } else {
          t['meta_artist'] = '';
        }

        t['meta_title'] = meta.trackName ?? '';
        t['meta_album'] = meta.albumName ?? '';
        t['meta_albumArt'] = meta.albumArt;
      } catch (e) {
        t['meta_artist'] = '';
        t['meta_title'] = '';
        t['meta_album'] = '';
        t['meta_albumArt'] = null;
      }
    } else {
      t['meta_artist'] = '';
      t['meta_title'] = '';
      t['meta_album'] = '';
      t['meta_albumArt'] = null;
    }

    return t;
  }

  void _applySearchFilter() {
    if (!mounted) return;
    setState(() {
      if (_searchQuery.trim().isEmpty) {
        _filteredTorrents = List.from(_torrents);
        return;
      }
      final query = _searchQuery.toLowerCase();
      _filteredTorrents = _torrents.where((t) {
        final name = (t['name']?.toString().toLowerCase()) ?? '';
        final artist = (t['meta_artist']?.toLowerCase()) ?? '';
        final title = (t['meta_title']?.toLowerCase()) ?? '';
        final album = (t['meta_album']?.toLowerCase()) ?? '';
        return name.contains(query) || artist.contains(query) || title.contains(query) || album.contains(query);
      }).toList();
    });
  }

  String _mapState(int state) {
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

  String _getDisplayState(Map<String, dynamic> t) {
    final bool isLocalFile = (t['file_found'] ?? false) == true;
    final int state = t['state'] ?? -1;
    final int seeders = t['seeders'] ?? 0;
    final int peers = t['peers'] ?? 0;

    if (isLocalFile) {
      return "Local • Seeders: $seeders • Peers: $peers";
    }

    return "${_mapState(state)} • Seeders: $seeders • Peers: $peers";
  }

  Widget _buildTorrentTile(Map<String, dynamic> t) {
    final name = t['name'] ?? 'Unknown';
    final uploadRateKb = (t['upload_rate'] ?? 0) / 1024;
    final downloadRateKb = (t['download_rate'] ?? 0) / 1024;

    final displayTitle = (t['meta_title'] as String?)?.trim() ?? 'unknown';
    final displayArtist = (t['meta_artist'] as String?)?.trim() ?? 'unknown';
    final displayAlbum = (t['meta_album'] as String?)?.trim() ?? 'unknown';
    final Uint8List? albumArt = t['meta_albumArt'] as Uint8List?;

    final isSeeding = _mapState(t['state'] ?? -1) == 'Seeding';
    final isLocalFile = (t['file_found'] ?? false) == true;

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
      subtitle: TorrentMetadataDisplay(
        artist: displayArtist,
        album: displayAlbum,
        extraInfo:
        '${_getDisplayState(t)}\n↑ ${uploadRateKb.toStringAsFixed(1)} KB/s • ↓ ${downloadRateKb.toStringAsFixed(1)} KB/s',
      ),
      isThreeLine: true,
      trailing: isSeeding
          ? const Icon(Icons.verified, color: Colors.lightBlueAccent)
          : (isLocalFile ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null),
      onTap: () => _onTorrentTap(t, displayTitle, displayArtist, albumArt),
    );
  }

  void _onTorrentTap(
      Map<String, dynamic> t,
      String displayTitle,
      String displayArtist,
      Uint8List? albumArt,
      ) {
    final name = t['name'] ?? 'Unknown';
    final isLocalFile = (t['file_found'] ?? false) == true;
    final isSeeding = _mapState(t['state'] ?? -1) == 'Seeding';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(displayTitle.isNotEmpty ? displayTitle : name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (albumArt != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(albumArt, width: 200, height: 200, fit: BoxFit.cover),
                ),
              const SizedBox(height: 12),
              if (displayArtist.isNotEmpty)
                Text("Artist: $displayArtist", style: const TextStyle(fontWeight: FontWeight.w600)),
              if ((t['meta_album'] as String?)?.isNotEmpty ?? false)
                Text("Album: ${t['meta_album']}"),
              const SizedBox(height: 12),
              Text('State: ${_getDisplayState(t)}'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: isLocalFile
                    ? null
                    : () async {
                  Navigator.pop(context);
                  debugPrint("Downloading torrent: ${t['name']}");
                  context.read<DownloadsBloc>().add(StartDownload(t['info_hash'], t['name']));
                  await _libtorrentService.downloadTorrent(context, t['info_hash']);
                },
                child: Text(isLocalFile ? 'Already downloaded' : 'Download'),
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                        (states) => isLocalFile ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isSeeding && isLocalFile)
            TextButton(
              child: Text('Stop Seeding',style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onPressed: () async {
                Navigator.pop(context); // Close main dialog first

                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Stop Seeding'),
                    content: Text('Do you want to stop seeding "$name"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Stop'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  final infoHash = t['info_hash']?.toString();
                  if (infoHash == null) return;

                  final removed = await _musicSeeder.removeTorrent(infoHash);
                  if (removed) {
                    await _fetchTorrentStats();
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to stop seeding.')),
                      );
                    }
                  }
                }
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _isError
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: $_version', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initialize,
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Libtorrent: $_version', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by artist, title, album...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (query) {
              _searchQuery = query;
              _applySearchFilter();
            },
          ),
          const SizedBox(height: 8),
          const Divider(),
          const Text('Active Torrents:', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchTorrentStats,
              child: _filteredTorrents.isEmpty
                  ? const Center(child: Text("No matching torrents."))
                  : ListView.separated(
                itemCount: _filteredTorrents.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, index) => _buildTorrentTile(_filteredTorrents[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TorrentMetadataDisplay extends StatelessWidget {
  final String artist;
  final String album;
  final String extraInfo;

  const TorrentMetadataDisplay({
    super.key,
    required this.artist,
    required this.album,
    required this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (artist.isNotEmpty)
          Text(
            artist,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (album.isNotEmpty)
          Text(
            album,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6) ?? Colors.grey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        Text(
          extraInfo,
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

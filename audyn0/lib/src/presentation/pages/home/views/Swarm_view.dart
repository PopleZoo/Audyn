// SwarmView.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path/path.dart' as p;

import '../../../../../services/music_seeder_service.dart';
import '../../../../data/services/LibtorrentService.dart';

class SwarmView extends StatefulWidget {
  const SwarmView({Key? key}) : super(key: key);

  @override
  State<SwarmView> createState() => _SwarmViewState();
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

  Future<void> _fetchTorrentStats() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final torrents = await _libtorrentService.getAllTorrents();
      final List<Map<String, dynamic>> enriched = [];

      for (final t in torrents) {
        final torrentName = (t['name'] ?? '').toString();

        if (!_metadataCache.containsKey(torrentName)) {
          final metaMap = await _musicSeeder.getMetadataForName(torrentName);
          if (metaMap != null) {
            _metadataCache[torrentName] = {
              'meta_title': metaMap['title'] ?? 'Unknown',
              'meta_artist': metaMap['artist'] ?? '',
              'meta_album': metaMap['album'] ?? '',
              'meta_albumArt': metaMap['albumArt'],
              'meta_duration': metaMap['duration'] ?? 0,
            };
          }
        }

        final fileFound = _musicSeeder.nameToPathMap.containsKey(torrentName);

        enriched.add({
          ...t,
          'file_found': fileFound,
          ...(_metadataCache[torrentName] ?? {}),
        });
      }

      setState(() {
        _torrents = enriched;
        _applySearchFilter();
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('[fetch] fatal error: $e\n$st');
      setState(() {
        _isError = true;
        _isLoading = false;
      });
    }
  }

  void _applySearchFilter() {
    final q = _searchQuery.toLowerCase();
    _filteredTorrents = _torrents.where((t) {
      return (t['name'] ?? '').toString().toLowerCase().contains(q) ||
          (t['meta_title'] ?? '').toString().toLowerCase().contains(q) ||
          (t['meta_artist'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _deleteTorrentByName(String torrentName) async {
    try {
      await _libtorrentService.removeTorrentByName(torrentName);
      _metadataCache.remove(torrentName);
      _torrents.removeWhere((t) => (t['name'] ?? '') == torrentName);
      _applySearchFilter();
      setState(() {});
    } catch (e) {
      debugPrint('[delete] Failed to delete torrent by name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchTorrentStats,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              onChanged: (value) {
                _searchQuery = value;
                _applySearchFilter();
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Search torrents...',
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
          ? const Center(child: Text('Failed to load torrents', style: TextStyle(color: Colors.red)))
          : _buildListView(),
    );
  }

  Widget _buildListView() {
    if (_filteredTorrents.isEmpty) {
      return const Center(child: Text('No torrents found.'));
    }
    return RefreshIndicator(
      onRefresh: _fetchTorrentStats,
      child: ListView.builder(
        itemCount: _filteredTorrents.length,
        itemBuilder: (ctx, i) {
          final t = _filteredTorrents[i];
          final hasAlbumArt = t['meta_albumArt'] is Uint8List;

          return ListTile(
            leading: hasAlbumArt
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                t['meta_albumArt'],
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            )
                : const Icon(Icons.music_note, size: 48),
            title: Text(t['meta_title'] ?? t['name'] ?? 'Unknown'),
            subtitle: Text(t['meta_artist'] ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteTorrentByName(t['name'] ?? ''),
            ),
          );
        },
      ),
    );
  }
}

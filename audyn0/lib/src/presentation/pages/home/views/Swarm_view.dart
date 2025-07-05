import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
        if (torrentName.isEmpty) continue;

        if (!_metadataCache.containsKey(torrentName)) {
          final metaMap = await _musicSeeder.getMetadataForName(torrentName);
          debugPrint('Metadata for "$torrentName": $metaMap');
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
      final name = (t['name'] ?? '').toString().toLowerCase();
      final title = (t['meta_title'] ?? '').toString().toLowerCase();
      final artist = (t['meta_artist'] ?? '').toString().toLowerCase();
      return name.contains(q) || title.contains(q) || artist.contains(q);
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.background,
        elevation: 1,
        title: Text(
          'Audyn Swarm',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchTorrentStats,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _buildSearchField(theme),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
          ? Center(
        child: Text(
          'Failed to load torrents',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      )
          : _buildListView(theme),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      onChanged: (value) {
        _searchQuery = value;
        _applySearchFilter();
        setState(() {});
      },
      style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
      cursorColor: Colors.white70,
      decoration: InputDecoration(
        hintText: 'Search torrents...',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        prefixIcon: Icon(Icons.search, color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildListView(ThemeData theme) {
    if (_filteredTorrents.isEmpty) {
      return Center(
        child: Text(
          'No torrents found.',
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white54),
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.white54,
      onRefresh: _fetchTorrentStats,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _filteredTorrents.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
        itemBuilder: (ctx, i) {
          final t = _filteredTorrents[i];
          final hasAlbumArt = t['meta_albumArt'] is Uint8List;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                : Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note, size: 36, color: Colors.white38),
            ),
            title: Text(
              t['meta_title'] ?? t['name'] ?? 'Unknown',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              t['meta_artist'] ?? '',
              style: theme.textTheme.displaySmall?.copyWith(color: Colors.white60),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteTorrentByName(t['name'] ?? ''),
              tooltip: 'Delete torrent',
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/playlist/playlist_manager.dart';
import '../../core/models/music_track.dart';
import '../../core/api/musicbrainz_api.dart'; // Your API here
import 'dart:typed_data';

// Import the dialog you created for picking/creating playlist
import 'playlist_picker_dialog.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final List<MusicTrack> _results = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await MusicBrainzAPI.search(query);
      setState(() {
        _results.clear();
        _results.addAll(results);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndAddTrack(MusicTrack track) async {
    final playlistManager = context.read<PlaylistManager>();

    // Show dialog to pick or create playlist
    final selectedPlaylistId = await showDialog<String?>(
      context: context,
      builder: (_) => PlaylistPickerDialog(playlists: playlistManager.playlists),
    );

    if (selectedPlaylistId == null) return;

    String playlistIdToUse = selectedPlaylistId;

    if (selectedPlaylistId.startsWith('new:')) {
      final newPlaylistName = await showDialog<String?>(
        context: context,
        builder: (context) {
          final TextEditingController nameController = TextEditingController();

          return AlertDialog(
            title: const Text('New Playlist'),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: 'Enter playlist name'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, name);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );

      if (newPlaylistName == null || newPlaylistName.isEmpty) {
        return; // User cancelled or entered no name
      }

      final newPlaylist = await playlistManager.createPlaylist(newPlaylistName);
      playlistIdToUse = newPlaylist.id;
    }


    // Simulate downloading a file
    final fakeBytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    await playlistManager.saveTrackFile(playlistIdToUse, '${track.title}.mp3', fakeBytes);
    await playlistManager.addTrackToPlaylist(playlistIdToUse, track);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${track.title}" to playlist')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildAlbumCover(String? url) {
    if (url == null || url.isEmpty) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Icon(Icons.music_note, size: 32, color: Colors.grey),
      );
    }
    return Image.network(
      url,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.broken_image, size: 32, color: Colors.grey);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          width: 50,
          height: 50,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _performSearch(_searchController.text),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: _performSearch,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? const Center(child: Text('No results'))
          : ListView.builder(
        itemCount: _results.length,
        itemBuilder: (ctx, i) {
          final track = _results[i];
          return ListTile(
            leading: _buildAlbumCover(track.coverUrl),
            title: Text(track.title),
            subtitle: Text(track.artist),
            trailing: IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _downloadAndAddTrack(track),
            ),
          );
        },
      ),
    );
  }
}

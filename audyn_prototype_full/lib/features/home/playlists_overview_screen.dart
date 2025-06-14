import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/download/download_manager.dart';
import '../../core/models/playlist.dart';
import '../../core/playlist/playlist_manager.dart';
import '../../core/playback/playback_manager.dart';
import '../../widgets/animated_bottom_player.dart';
import '../home/search_screen.dart';
import 'download_screen.dart';
import 'playlist_screen.dart';

class PlaylistsOverviewScreen extends StatefulWidget {
  const PlaylistsOverviewScreen({super.key});

  @override
  State<PlaylistsOverviewScreen> createState() => _PlaylistsOverviewScreenState();
}

class _PlaylistsOverviewScreenState extends State<PlaylistsOverviewScreen> {
  Playlist? _deletedPlaylist;
  Timer? _deleteTimer;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _deleteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistManager = context.watch<PlaylistManager>();
    final playlists = _filteredPlaylists(playlistManager.playlists);
    final downloadManager = context.watch<DownloadManager>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Your Playlists"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: _buildDrawer(downloadManager),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child: playlists.isEmpty
                    ? const Center(
                  child: Text("No playlists found.",
                      style: TextStyle(color: Colors.white54, fontSize: 16)),
                )
                    : _buildPlaylistGrid(playlists, playlistManager),
              ),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: AnimatedBottomPlayer(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search playlists...',
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, color: Colors.white54),
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
              });
            },
          )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
      ),
    );
  }

  List<Playlist> _filteredPlaylists(List<Playlist> allPlaylists) {
    if (_searchQuery.isEmpty) return allPlaylists;
    return allPlaylists
        .where((playlist) => playlist.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  Drawer _buildDrawer(DownloadManager downloadManager) {
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.black),
            child: Text('Menu',
                style: TextStyle(color: Colors.white, fontSize: 20)),
          ),
          ListTile(
            leading: const Icon(Icons.search, color: Colors.white),
            title: const Text('Search Songs', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.library_music, color: Colors.grey),
            title: const Text('Playlists', style: TextStyle(color: Colors.grey)),
            onTap: () {
              Navigator.pop(context); // Prevent infinite stacking of this screen
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.white),
            title: const Text('Downloads', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DownloadScreen()));
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Download Progress', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: downloadManager.overallProgress,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(downloadManager.overallProgress * 100).toStringAsFixed(0)}% completed',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPlaylistGrid(List<Playlist> playlists, PlaylistManager manager) {
    final playbackManager = context.read<PlaybackManager>();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 3 / 4,
      ),
      itemCount: playlists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildCreatePlaylistTile(manager);

        final playlist = playlists[index - 1];
        final isPlaying = playbackManager.isPlaylistPlaying(playlist);

        return _buildPlaylistTile(playlist, manager, playbackManager, isPlaying);
      },
    );
  }

  Widget _buildCreatePlaylistTile(PlaylistManager manager) {
    return GestureDetector(
      onTap: () async {
        final name = await _showCreatePlaylistDialog(context);
        if (name != null && name.isNotEmpty) {
          final newPlaylist = await manager.createPlaylist(name);
          if (context.mounted && newPlaylist != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PlaylistScreen(
                  playlistId: newPlaylist.id,
                  folderPath: newPlaylist.folderPath,
                ),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Playlist "$name" created')),
            );
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_circle_outline, size: 48, color: Colors.white70),
            SizedBox(height: 12),
            Text('Create Playlist', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistTile(Playlist playlist, PlaylistManager manager, PlaybackManager playbackManager, bool isPlaying) {
    return Dismissible(
      key: Key(playlist.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _handleDismiss(context, manager, playlist),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaylistScreen(
                playlistId: playlist.id,
                folderPath: playlist.folderPath,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCoverImage(playlist),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "${playlist.tracks.length} ${playlist.tracks.length == 1 ? "track" : "tracks"}",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle),
                          color: playbackManager.isPlaylistShuffled(playlist)
                              ? Colors.lightBlueAccent
                              : Colors.white70,
                          tooltip: 'Toggle Shuffle',
                          onPressed: () {
                            setState(() {
                              playbackManager.toggleShuffleForPlaylist(playlist);
                            });
                          },
                        ),
                        Consumer<PlaybackManager>(
                          builder: (context, playback, _) {
                            final isCurrent = playback.isCurrentPlaylist(playlist);
                            final isPlaying = isCurrent && playback.isPlaying;

                            return IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              tooltip: isPlaying ? 'Pause' : 'Play',
                              onPressed: () async {
                                if (isPlaying) {
                                  playback.pause();
                                } else if (isCurrent) {
                                  playback.resume();
                                } else {
                                  await playback.setPlaylist(
                                    playlist.tracks,
                                    shuffle: playback.isPlaylistShuffled(playlist),
                                    playlistId: playlist.id,
                                  );
                                }
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: 'Delete Playlist',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Playlist'),
                                content: Text('Are you sure you want to delete "${playlist.name}"?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _handleDismiss(context, manager, playlist);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _handleDismiss(BuildContext context, PlaylistManager manager, Playlist playlist) async {
    _deletedPlaylist = playlist;
    manager.removePlaylist(playlist.id);

    final snackBar = SnackBar(
      content: Text('Deleted "${playlist.name}"'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          _deleteTimer?.cancel();
          manager.restorePlaylist(_deletedPlaylist!);
          _deletedPlaylist = null;
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    _deleteTimer?.cancel();
    _deleteTimer = Timer(snackBar.duration, () {
      _deletedPlaylist = null;
    });

    return false;
  }

  Widget _buildCoverImage(Playlist playlist) {
    if (playlist.coverImagePath != null &&
        playlist.coverImagePath!.isNotEmpty &&
        File(playlist.coverImagePath!).existsSync()) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Image.file(
          File(playlist.coverImagePath!),
          fit: BoxFit.cover,
          height: 120,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _defaultCoverIcon(),
        ),
      );
    }
    return _defaultCoverIcon();
  }

  Widget _defaultCoverIcon() {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white54, size: 64),
      ),
    );
  }

  Future<String?> _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
  }
}

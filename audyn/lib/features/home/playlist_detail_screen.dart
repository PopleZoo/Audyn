import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../../core/playlist/playlist_manager.dart';
import '../../core/models/music_track.dart';
import '../../core/playback/playback_manager.dart';
import '../../widget/track_list_item.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistName;
  final Future<void> Function() onRescan;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistName,
    required this.onRescan,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  static const bool isDebug = false;
  static const int maxVisibleTracks = 300;
  late PlaybackManager _playback;

  String _searchQuery = '';
  String _sortBy = 'Title';
  bool _ascending = true;

  // Track shuffle & repeat state synced with PlaybackManager:
  bool _isShuffleActive = false;
  RepeatMode _repeatMode = RepeatMode.off;

  Future<String?> _getCoverPath(String folderPath) async {
    final coverFile = File('$folderPath/cover.jpg');
    return await coverFile.exists() ? coverFile.path : null;
  }

  Future<bool> _fileExists(String path) async {
    return await File(path).exists();
  }

  List<MusicTrack> _applyFilters(List<MusicTrack> tracks) {
    var filtered = tracks.where((track) {
      return track.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          track.artist.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      int compare;
      switch (_sortBy) {
        case 'Artist':
          compare = a.artist.compareTo(b.artist);
          break;
        case 'Date Added':
          final aDate = a.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
          compare = aDate.compareTo(bDate);
          break;
        case 'Title':
        default:
          compare = a.title.compareTo(b.title);
      }
      return _ascending ? compare : -compare;
    });

    return filtered;
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _playback = context.read<PlaybackManager>(); // cache once here

    // Listen to PlaybackManager to sync shuffle & repeat states.
    _isShuffleActive = _playback.isShuffleEnabled;
    _repeatMode = _playback.repeatMode;

    _playback.addListener(_playbackListener);
  }

  @override
  void dispose() {
    _playback.removeListener(_playbackListener); // use cached instance
    super.dispose();
  }

  void _playbackListener() {
    if (mounted) {
      setState(() {
        _isShuffleActive = _playback.isShuffleEnabled; // cached instance
        _repeatMode = _playback.repeatMode;           // cached instance
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistManager = context.watch<PlaylistManager>();
    final playlists = playlistManager.playlists;
    final playlist = playlists.firstWhereOrNull((p) => p.name == widget.playlistName);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Playlist has no songs")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Wow such empty"),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async => await widget.onRescan(),
                child: const Text("Rescan Music Directory"),
              ),
            ],
          ),
        ),
      );
    }

    final visibleTracks = isDebug
        ? playlist.tracks.take(maxVisibleTracks).toList()
        : playlist.tracks;

    final displayedTracks = _applyFilters(visibleTracks);

    final playback = context.read<PlaybackManager>();

    // Assume PlaybackManager has a bool to detect bottom player visibility
    final isBottomPlayerVisible = playback.showBottomPlayer;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          FutureBuilder<String?>(
            future: _getCoverPath(playlist.folderPath),
            builder: (context, snapshot) {
              final coverPath = snapshot.data;
              return Container(
                padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 20),
                decoration: BoxDecoration(
                  image: coverPath != null
                      ? DecorationImage(
                    image: FileImage(File(coverPath)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.5),
                      BlendMode.darken,
                    ),
                  )
                      : null,
                  color: Colors.grey[900],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            playlist.name,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${playlist.tracks.length} tracks',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    Selector<PlaybackManager, bool>(
                      selector: (_, pm) => pm.isPlaying &&
                          const DeepCollectionEquality().equals(
                            pm.currentTrack,
                            playlist.tracks,
                          ),
                      builder: (context, isPlaylistPlaying, _) {
                        return Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.lightBlueAccent,
                                foregroundColor: Colors.black,
                              ),
                              icon: Icon(isPlaylistPlaying ? Icons.pause : Icons.play_arrow),
                              label: Text(isPlaylistPlaying ? "Pause" : "Play"),
                              onPressed: () {
                                if (isPlaylistPlaying) {
                                  playback.pause();
                                } else {
                                  playback.setPlaylist(playlist.tracks, shuffle: false);
                                }
                              },
                            ),
                            const SizedBox(width: 12),

                            // Shuffle button
                            Ink(
                              decoration: BoxDecoration(
                                color: _isShuffleActive ? Colors.lightBlueAccent.withOpacity(0.3) : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(Icons.shuffle, color: _isShuffleActive ? Colors.lightBlueAccent : Colors.white, size: 24),
                                onPressed: () async {
                                  final newShuffleState = !_isShuffleActive;
                                  if (isBottomPlayerVisible) {
                                    playback.setShuffleEnabled(newShuffleState);
                                  } else {
                                    await playback.setPlaylist(
                                      playlist.tracks,
                                      shuffle: newShuffleState,
                                      playlistId: playlist.name,
                                    );
                                  }
                                  setState(() => _isShuffleActive = newShuffleState);
                                },
                                tooltip: 'Shuffle Play',
                                splashRadius: 24,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Repeat button
                            Ink(
                              decoration: BoxDecoration(
                                color: _repeatMode != RepeatMode.off ? Colors.lightBlueAccent.withOpacity(0.3) : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _repeatMode == RepeatMode.all ? Icons.repeat :
                                  _repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                                  color: _repeatMode != RepeatMode.off ? Colors.lightBlueAccent : Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  RepeatMode nextMode;
                                  switch (_repeatMode) {
                                    case RepeatMode.off:
                                      nextMode = RepeatMode.all;
                                      break;
                                    case RepeatMode.all:
                                      nextMode = RepeatMode.one;
                                      break;
                                    case RepeatMode.one:
                                      nextMode = RepeatMode.off;
                                      break;
                                    case RepeatMode.group:
                                      throw UnimplementedError('Group repeat mode not supported.');
                                  }
                                  if (isBottomPlayerVisible) {
                                    playback.setRepeatMode(nextMode);
                                  } else {
                                    playback.setRepeatMode(nextMode);
                                    playback.setPlaylist(
                                      playlist.tracks,
                                      shuffle: _isShuffleActive,
                                      playlistId: playlist.name,
                                    );
                                  }
                                  setState(() => _repeatMode = nextMode);
                                },
                                tooltip: 'Repeat Mode',
                                splashRadius: 24,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Resync button
                            IconButton(
                              icon: const Icon(Icons.sync, color: Colors.white70),
                              tooltip: 'Resync Playlist',
                              onPressed: () async {
                                await playlistManager.resyncPlaylist(playlist.name);
                              },
                            ),

                            const SizedBox(width: 12),

                            // DELETE button
                            IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                              tooltip: 'Delete Playlist',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Playlist'),
                                    content: Text('Are you sure you want to delete the playlist "${playlist.name}"? This action cannot be undone.'),
                                    actions: [
                                      TextButton(
                                        child: const Text('Cancel'),
                                        onPressed: () => Navigator.of(context).pop(false),
                                      ),
                                      TextButton(
                                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        onPressed: () => Navigator.of(context).pop(true),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await playlistManager.removePlaylist(playlist.id);
                                  if (mounted) {
                                    Navigator.of(context).pop();  // Go back after delete
                                  }
                                }
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(height: 1, color: Colors.white24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search tracks...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    DropdownButton<String>(
                      value: _sortBy,
                      dropdownColor: Colors.black,
                      style: const TextStyle(color: Colors.white),
                      items: ['Title', 'Artist', 'Date Added'].map((e) {
                        return DropdownMenuItem(
                          value: e,
                          child: Text(e),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sortBy = value);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        color: Colors.white,
                      ),
                      onPressed: () => setState(() => _ascending = !_ascending),
                      tooltip: 'Toggle Sort Direction',
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              cacheExtent: 500,
              itemCount: displayedTracks.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, indent: 80),
              itemBuilder: (context, i) {
                final track = displayedTracks[i];
                return TrackListItem(track: track, fullPlaylist: playlist.tracks);
              },
            ),
          ),
        ],
      ),
    );
  }
}

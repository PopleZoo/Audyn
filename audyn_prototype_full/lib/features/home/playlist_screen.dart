import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/music_track.dart';
import '../../core/models/playlist.dart';
import '../../core/playback/playback_manager.dart';
import '../../core/playlist/playlist_manager.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  final String folderPath;

  const PlaylistScreen({
    super.key,
    required this.playlistId,
    required this.folderPath,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {

  void _togglePlay(MusicTrack track) {
    final playbackManager = context.read<PlaybackManager>();

    if (playbackManager.currentTrack?.id == track.id && playbackManager.isPlaying) {
      playbackManager.pause();
    } else {
      playbackManager.playTrack(track);
    }
  }


  @override
  Widget build(BuildContext context) {
    final playlistManager = context.watch<PlaylistManager>();
    final playlist = playlistManager.playlists.firstWhere(
          (p) => p.id == widget.playlistId,
      orElse: () => Playlist(
        id: '',
        name: 'Unknown Playlist',
        tracks: [],
        folderPath: widget.folderPath,
      ),
    );

    if (playlist.id.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Playlist not found')),
        body: const Center(child: Text('Playlist does not exist', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.lightBlueAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              try {
                await playlistManager.resyncPlaylists();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playlists resynced')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to resync: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSpotifyHeader(playlist),
          Expanded(
            child: ListView.builder(
              itemCount: playlist.tracks.length,
              itemBuilder: (context, index) {
                final track = playlist.tracks[index];
                final playbackManager = context.watch<PlaybackManager>();
                final isPlaying = playbackManager.currentTrack?.id == track.id && playbackManager.isPlaying;

                return FutureBuilder<MusicTrack>(
                  future: _enrichMetadataIfNeeded(track),
                  builder: (context, snapshot) {
                    final enrichedTrack = snapshot.data ?? track;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      onTap: () => _togglePlay(enrichedTrack),
                      leading: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: isPlaying ? Colors.lightBlueAccent : Colors.white,
                        size: 32,
                      ),
                      title: Text(
                        enrichedTrack.title,
                        style: TextStyle(
                          color: isPlaying ? Colors.lightBlueAccent : Colors.white,
                          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(enrichedTrack.artist, style: const TextStyle(color: Colors.lightBlueAccent)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          playlistManager.removeTrackFromPlaylist(playlist.id, enrichedTrack.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Removed "${enrichedTrack.title}"'),
                              action: SnackBarAction(
                                label: 'Undo',
                                textColor: Colors.white,
                                onPressed: () {
                                  playlistManager.addTrackToPlaylist(playlist.id, enrichedTrack);
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSpotifyHeader(Playlist playlist) {
    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Show cover image if available, else fallback to default icon widget
          playlist.coverImagePath != null && playlist.coverImagePath!.isNotEmpty
              ? Image.network(
            playlist.coverImagePath!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Show default icon if image fails to load
              return _defaultPlaylistCover();
            },
          )
              : _defaultPlaylistCover(),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.9),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${playlist.tracks.length} ${playlist.tracks.length == 1 ? "song" : "songs"}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultPlaylistCover() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(
          Icons.library_music,
          color: Colors.white54,
          size: 96,
        ),
      ),
    );
  }



  Future<String?> _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<MusicTrack> _enrichMetadataIfNeeded(MusicTrack track) async {
    if (track.coverUrl != null && track.artist.isNotEmpty) return track;

    final query = Uri.encodeComponent('${track.artist} ${track.title}');
    final uri = Uri.parse('https://musicbrainz.org/ws/2/recording?query=$query&fmt=json&limit=1');
    final response = await http.get(uri, headers: {
      'User-Agent': 'FlutterMusicApp/1.0 (your@email.com)',
    });

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final recordings = data['recordings'] as List?;
      if (recordings != null && recordings.isNotEmpty) {
        final recording = recordings.first;
        final artistName = recording['artist-credit']?[0]?['name'] ?? track.artist;
        final releaseId = recording['releases']?[0]?['id'];
        String? coverUrl;

        if (releaseId != null) {
          final coverResponse = await http.get(Uri.parse('https://coverartarchive.org/release/$releaseId/front'));
          if (coverResponse.statusCode == 200) {
            coverUrl = 'https://coverartarchive.org/release/$releaseId/front';
          }
        }

        return track.copyWith(
          artist: artistName,
          title: recording['title'] ?? track.title,
          coverUrl: coverUrl,
        );
      }
    }
    return track;
  }
}

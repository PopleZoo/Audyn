import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/music_track.dart';
import '../../core/playback/playback_manager.dart';

class TrackListItem extends StatelessWidget {
  final MusicTrack track;
  final List<MusicTrack> fullPlaylist;

  const TrackListItem({
    super.key,
    required this.track,
    required this.fullPlaylist,
  });

  Future<bool> _fileExists(String path) async {
    return await File(path).exists();
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackManager>();
    final isCurrent = playback.currentTrack?.id == track.id;
    final isPlaying = playback.isPlaying;
    final isCurrentlyPlaying = isCurrent && isPlaying;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 50,
              height: 50,
              child: track.coverUrl == null
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : FutureBuilder<bool>(
                future: _fileExists(track.coverUrl!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 1,
                        valueColor: AlwaysStoppedAnimation(Colors.white30),
                      ),
                    );
                  }
                  if (snapshot.data == true) {
                    return Image.file(
                      File(track.coverUrl!),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    );
                  } else {
                    return const Icon(Icons.music_note, color: Colors.white54);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isCurrentlyPlaying ? Icons.pause_circle : Icons.play_circle,
              color: Colors.white,
              size: 30,
            ),
            onPressed: () {
              if (isCurrentlyPlaying) {
                playback.pause();
              } else {
                playback.setPlaylist(fullPlaylist, shuffle: false);
                playback.playTrack(track);
              }
            },
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final playback = context.read<PlaybackManager>();

    return ListTile(
      key: ValueKey(track.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 50,
          height: 50,
          child: track.coverUrl == null
              ? const Icon(Icons.music_note, color: Colors.white54)
              : Image.file(
            File(track.coverUrl!),
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const Icon(Icons.music_note, color: Colors.white54),
          ),
        ),
      ),
      title: Text(
        track.title,
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artist,
        style: const TextStyle(color: Colors.white54),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),

      /// Only rebuild trailing when currentTrack or playing state changes
      trailing: Selector<PlaybackManager, bool>(
        selector: (_, pm) => pm.currentTrack?.id == track.id && pm.isPlaying,
        builder: (_, isPlaying, __) {
          return IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_circle : Icons.play_circle,
              color: Colors.white,
              size: 30,
            ),
            onPressed: () async {
              if (isPlaying) {
                await playback.pause();
              } else {
                await playback.playTrack(track);
              }
            },
          );
        },
      ),
    );
  }
}

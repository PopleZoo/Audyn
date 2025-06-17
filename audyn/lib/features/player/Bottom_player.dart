import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../../../audio_handler.dart';
import '../../core/playback/playback_manager.dart';
import '../home/full_player_screen.dart';

class BottomPlayer extends StatefulWidget {
  const BottomPlayer({Key? key}) : super(key: key);

  @override
  State<BottomPlayer> createState() => _BottomPlayerState();
}

class _BottomPlayerState extends State<BottomPlayer> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();

    // Listen once we have context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioHandler = Provider.of<MyAudioHandler>(context, listen: false);
      audioHandler.playbackState.listen((state) {
        final shouldHide = state.processingState == AudioProcessingState.idle ||
            state.processingState == AudioProcessingState.completed;

        if (_visible != !shouldHide) {
          if (mounted) setState(() => _visible = !shouldHide);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final audioHandler = Provider.of<MyAudioHandler>(context, listen: false);
    final playbackManager = Provider.of<PlaybackManager>(context);
    final track = playbackManager.currentTrack;

    if (track == null) return const SizedBox.shrink();

    final position = playbackManager.currentPosition ?? Duration.zero;
    final duration = track.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    final isPlaying = playbackManager.isPlaying;
    final repeatMode = playbackManager.repeatMode;
    final shuffleModeEnabled = playbackManager.isShuffleEnabled;

    return Dismissible(
      key: const Key("bottom_player"),
      direction: DismissDirection.down,
      onDismissed: (_) {
        audioHandler.stop();
      },
      child: Hero(
        tag: 'full_player',
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const FullPlayerScreen(),
            ));
          },
          child: Container(
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[900],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                  minHeight: 3,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (track.coverFile != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          track.coverFile!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      const Icon(Icons.music_note, size: 50),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        shuffleModeEnabled ? Icons.shuffle_on : Icons.shuffle,
                        color: shuffleModeEnabled ? Colors.blueAccent : Colors.white,
                      ),
                      onPressed: () {
                        audioHandler.setShuffleMode(
                          shuffleModeEnabled
                              ? AudioServiceShuffleMode.none
                              : AudioServiceShuffleMode.all,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      onPressed: audioHandler.skipToPrevious,
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 36,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        isPlaying
                            ? audioHandler.pause()
                            : audioHandler.play();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      onPressed: audioHandler.skipToNext,
                    ),
                    IconButton(
                      icon: Icon(
                        repeatMode == RepeatMode.all
                            ? Icons.repeat_on
                            : repeatMode == RepeatMode.one
                            ? Icons.repeat_one_on
                            : Icons.repeat,
                        color: repeatMode == RepeatMode.off
                            ? Colors.white
                            : Colors.blueAccent,
                      ),
                      onPressed: () {
                        RepeatMode nextMode;
                        switch (repeatMode) {
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

                        // Update UI + audio service
                        AudioServiceRepeatMode serviceMode;
                        switch (nextMode) {
                          case RepeatMode.off:
                            serviceMode = AudioServiceRepeatMode.none;
                            break;
                          case RepeatMode.all:
                            serviceMode = AudioServiceRepeatMode.all;
                            break;
                          case RepeatMode.one:
                            serviceMode = AudioServiceRepeatMode.one;
                            break;
                          case RepeatMode.group:
                            throw UnimplementedError();
                        }

                        audioHandler.setRepeatMode(serviceMode);
                        // Optionally also update PlaybackManager repeatMode here
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

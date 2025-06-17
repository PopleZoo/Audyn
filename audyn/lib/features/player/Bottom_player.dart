import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/playback/playback_manager.dart';
import '../home/full_player_screen.dart';

class BottomPlayer extends StatefulWidget {
  const BottomPlayer({super.key});

  @override
  State<BottomPlayer> createState() => _BottomPlayerState();
}

class _BottomPlayerState extends State<BottomPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // starts below the screen
      end: Offset.zero,          // slides up to visible
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Start the animation immediately when widget appears
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = Provider.of<PlaybackManager>(context);
    final track = playbackManager.currentTrack;

    if (track == null) {
      // Animate slide down before removing the widget for smoother exit
      _controller.reverse();
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        color: Colors.grey[900],
        elevation: 12,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FullPlayerScreen()),
            );
          },
          child: Container(
            height: 100,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Hero(
                  tag: 'albumArtHero',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: track.coverFile != null
                        ? AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Image.file(
                        track.coverFile!,
                        key: ValueKey(track.coverFile!.path),
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[700],
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: IconButton(
                    key: ValueKey(playbackManager.isPlaying),
                    icon: Icon(
                      playbackManager.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      playbackManager.isPlaying ? playbackManager.pause() : playbackManager.play();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: playbackManager.next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

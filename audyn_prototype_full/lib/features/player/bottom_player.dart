import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marquee/marquee.dart';
import '../../core/playback/playback_manager.dart';
import '../home/now_playing_screen.dart';

class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playbackManager = Provider.of<PlaybackManager>(context);
    final track = playbackManager.currentTrack;

    if (track == null) return const SizedBox.shrink();

    Widget buildScrollingText(
        String text,
        TextStyle style,
        double height,
        double maxWidth, {
          double charWidth = 8.0, // rough average width per char
        }) {
      final threshold = (maxWidth / charWidth).floor();

      final shouldScroll = text.length > threshold;

      return SizedBox(
        height: height,
        child: shouldScroll
            ? Marquee(
          text: text,
          style: style,
          scrollAxis: Axis.horizontal,
          blankSpace: 30.0,
          velocity: 25.0,
          pauseAfterRound: const Duration(seconds: 5),
          startPadding: 0.0,
          accelerationDuration: const Duration(milliseconds: 500),
          accelerationCurve: Curves.easeIn,
          decelerationDuration: const Duration(milliseconds: 500),
          decelerationCurve: Curves.easeOut,
        )
            : Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: style,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate space used by artwork + padding + buttons
          final reservedWidth = 60 + 12 + (3 * 48); // cover image + spacing + 3 buttons
          final textWidth = constraints.maxWidth - reservedWidth - 48; // some padding

          return Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (context) => NowPlayingScreen()));;
                          },
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  track.coverFile!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: textWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    buildScrollingText(
                                      track.title,
                                      const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      20,
                                      textWidth,
                                    ),
                                    buildScrollingText(
                                      track.artist,
                                      const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                      16,
                                      textWidth,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous, color: Colors.white),
                              onPressed: () {
                                playbackManager.previous();
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                playbackManager.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                playbackManager.isPlaying
                                    ? playbackManager.pause()
                                    : playbackManager.play();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next, color: Colors.white),
                              onPressed: () {
                                playbackManager.next();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                ),
              ),
            ],
          );
        },
      )

    );
  }
}

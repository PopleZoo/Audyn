import 'dart:ui';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:marquee/marquee.dart';
import 'package:audyn/src/presentation/widgets/buttons/next_button.dart';
import 'package:audyn/src/presentation/widgets/buttons/play_pause_button.dart';
import 'package:audyn/src/presentation/widgets/buttons/previous_button.dart';
import 'package:audyn/src/presentation/widgets/buttons/repeat_button.dart';
import 'package:audyn/src/presentation/widgets/buttons/shuffle_button.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audyn/src/bloc/song/song_bloc.dart';
import 'package:audyn/src/core/di/service_locator.dart';
import 'package:audyn/src/data/repositories/player_repository.dart';
import 'package:audyn/src/data/repositories/song_repository.dart';
import 'package:audyn/src/presentation/widgets/animated_favorite_button.dart';
import 'package:audyn/src/presentation/widgets/seek_bar.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final player = sl<MusicPlayer>();

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          color: Colors.white,
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert_outlined),
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  onTap: () {
                    showSleepTimer(context);
                  },
                  child: const Text('Sleep timer'),
                ),
              ];
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: StreamBuilder<SequenceState?>(
        stream: player.sequenceState,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }
          final sequence = snapshot.data;
          MediaItem? mediaItem = sequence!.sequence[sequence.currentIndex].tag;
          return Stack(
            children: [
              QueryArtworkWidget(
                keepOldArtwork: true,
                artworkHeight: double.infinity,
                id: int.parse(mediaItem!.id),
                type: ArtworkType.AUDIO,
                size: 10000,
                artworkWidth: double.infinity,
                artworkBorder: BorderRadius.circular(0),
                nullArtworkWidget: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(0),
                  ),
                  child: const Icon(Icons.music_note_outlined, size: 100),
                ),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(0),
                  ),
                ),
              ),

              // Use Positioned to move the content higher on the screen:
              Positioned(
                top: MediaQuery.of(context).padding.top + 8, // adjust this value to move content up/down
                left: 32,
                right: 32,
                bottom: 16,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // large screen
                    if (constraints.maxWidth > 600) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // artwork
                          SizedBox(
                            width: MediaQuery.of(context).size.width / 3,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                QueryArtworkWidget(
                                  keepOldArtwork: true,
                                  id: int.parse(mediaItem.id),
                                  type: ArtworkType.AUDIO,
                                  size: 10000,
                                  artworkWidth: double.infinity,
                                  nullArtworkWidget: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    child: Icon(
                                      Icons.music_note_outlined,
                                      size: MediaQuery.of(context).size.height / 10,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: BlocBuilder<SongBloc, SongState>(
                                    builder: (context, state) {
                                      return AnimatedFavoriteButton(
                                        isFavorite: sl<SongRepository>().isFavorite(mediaItem.id),
                                        mediaItem: mediaItem,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 32),

                          // info
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                StreamBuilder<SequenceState?>(
                                  stream: player.sequenceState,
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const SizedBox.shrink();
                                    }
                                    final sequence = snapshot.data;
                                    MediaItem? mediaItem = sequence!.sequence[sequence.currentIndex].tag;
                                    return Column(
                                      children: [
                                        SizedBox(
                                          height: 30,
                                          child: AutoSizeText(
                                            mediaItem!.title,
                                            maxLines: 1,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            minFontSize: 20,
                                            overflowReplacement: Marquee(
                                              text: mediaItem.title,
                                              blankSpace: 100,
                                              startAfter: const Duration(seconds: 3),
                                              pauseAfterRound: const Duration(seconds: 3),
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 30,
                                          child: AutoSizeText(
                                            mediaItem.artist ?? 'Unknown',
                                            maxLines: 1,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.white,
                                            ),
                                            minFontSize: 16,
                                            overflowReplacement: Marquee(
                                              text: mediaItem.artist ?? 'Unknown',
                                              blankSpace: 100,
                                              startAfter: const Duration(seconds: 3),
                                              pauseAfterRound: const Duration(seconds: 3),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const Spacer(),
                                SeekBar(player: player),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    ShuffleButton(),
                                    PreviousButton(),
                                    PlayPauseButton(),
                                    NextButton(),
                                    RepeatButton(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    // small screen
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: (MediaQuery.of(context).size.width - 64) * 0.8, // reduced height here for better layout
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              QueryArtworkWidget(
                                keepOldArtwork: true,
                                id: int.parse(mediaItem.id),
                                type: ArtworkType.AUDIO,
                                size: 10000,
                                artworkWidth: double.infinity,
                                artworkBorder: BorderRadius.circular(0),
                                nullArtworkWidget: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(0),
                                  ),
                                  child: Icon(
                                    Icons.music_note_outlined,
                                    size: MediaQuery.of(context).size.height / 10,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: BlocBuilder<SongBloc, SongState>(
                                  builder: (context, state) {
                                    return AnimatedFavoriteButton(
                                      isFavorite: sl<SongRepository>().isFavorite(mediaItem.id),
                                      mediaItem: mediaItem,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<SequenceState?>(
                          stream: player.sequenceState,
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const SizedBox(height: 70);
                            }
                            final sequence = snapshot.data;
                            MediaItem? mediaItem = sequence!.sequence[sequence.currentIndex].tag;
                            return Center(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 40,
                                    child: AutoSizeText(
                                      mediaItem!.title,
                                      maxLines: 1,
                                      minFontSize: 24,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        color: Colors.white,
                                      ),
                                      overflowReplacement: Marquee(
                                        text: mediaItem.title,
                                        blankSpace: 100,
                                        startAfter: const Duration(seconds: 3),
                                        pauseAfterRound: const Duration(seconds: 3),
                                        style: const TextStyle(
                                          fontSize: 24,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 30,
                                    child: AutoSizeText(
                                      mediaItem.artist ?? 'Unknown',
                                      maxLines: 1,
                                      minFontSize: 18,
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 18,
                                      ),
                                      overflowReplacement: Marquee(
                                        text: mediaItem.artist ?? 'Unknown',
                                        blankSpace: 100,
                                        startAfter: const Duration(seconds: 3),
                                        pauseAfterRound: const Duration(seconds: 3),
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 64),
                        SeekBar(player: player),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ShuffleButton(),
                            PreviousButton(),
                            PlayPauseButton(),
                            NextButton(),
                            RepeatButton(),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void showSleepTimer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              ListTile(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                title: const Text('Off'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('5 minutes'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('10 minutes'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('15 minutes'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('30 minutes'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('45 minutes'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('1 hour'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

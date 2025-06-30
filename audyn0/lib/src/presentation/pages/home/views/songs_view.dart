import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:audyn/src/core/constants/assets.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:audyn/src/bloc/home/home_bloc.dart';
import 'package:audyn/src/bloc/player/player_bloc.dart';
import 'package:audyn/src/core/di/service_locator.dart';
import 'package:audyn/src/core/extensions/string_extensions.dart';
import 'package:audyn/src/data/repositories/player_repository.dart';
import 'package:audyn/src/data/services/hive_box.dart';
import 'package:audyn/src/presentation/widgets/song_list_tile.dart';

import '../../../../bloc/playlists/playlists_cubit.dart';
import '../../../../bloc/song/song_bloc.dart';

class SongsView extends StatefulWidget {
  const SongsView({super.key});

  @override
  State<SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends State<SongsView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final audioQuery = sl<OnAudioQuery>();
  final songs = <SongModel>[];
  bool isLoading = true;
  final _scrollController = ScrollController();

  /// Selection state
  late Set<int> selectedSongIds = {};
  bool selectionMode = false;

  @override
  void initState() {
    super.initState();
    context.read<HomeBloc>().add(GetSongsEvent());
  }

  void _showAddToPlaylistModal(BuildContext context, List<SongModel> selectedSongs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return BlocBuilder<PlaylistsCubit, PlaylistsState>(
          builder: (context, state) {
            List<PlaylistModel> playlists = [];
            if (state is PlaylistsLoaded) {
              playlists = state.playlists;
            }

            if (playlists.isEmpty) {
              final TextEditingController _nameController = TextEditingController();
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 16,
                  right: 16,
                  top: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No playlists available',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a new playlist to add selected songs.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Playlist Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final playlistName = _nameController.text.trim();
                              if (playlistName.isEmpty) {
                                Fluttertoast.showToast(msg: 'Playlist name cannot be empty');
                                return;
                              }

                              final playlistsCubit = context.read<PlaylistsCubit>();
                              await playlistsCubit.createPlaylist(playlistName);
                              await playlistsCubit.queryPlaylists();

                              final updatedState = playlistsCubit.state;
                              if (updatedState is PlaylistsLoaded) {
                                final newPlaylist = updatedState.playlists.firstWhereOrNull(
                                      (p) => p.playlist == playlistName,
                                );

                                if (newPlaylist != null) {
                                  for (final song in selectedSongs) {
                                    await playlistsCubit.addToPlaylist(newPlaylist.id, song);
                                  }

                                  Fluttertoast.showToast(
                                    msg: 'Added ${selectedSongs.length} songs to "$playlistName"',
                                  );
                                }
                              }

                              Navigator.of(context).pop();
                              _exitSelectionMode();
                            },
                            child: const Text('Create & Add'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            }

            // If playlists exist, show list to add songs to
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              itemCount: playlists.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return ListTile(
                  title: Text(playlist.playlist),
                  subtitle: Text(
                    '${playlist.numOfSongs} ${'song'.pluralize(playlist.numOfSongs)}',
                  ),
                  onTap: () async {
                    final playlistsCubit = context.read<PlaylistsCubit>();
                    for (final song in selectedSongs) {
                      await playlistsCubit.addToPlaylist(playlist.id, song);
                    }

                    Fluttertoast.showToast(
                      msg: 'Added ${selectedSongs.length} songs to "${playlist.playlist}"',
                    );
                    Navigator.of(context).pop();
                    _exitSelectionMode();
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _exitSelectionMode() {
    setState(() {
      selectionMode = false;
      selectedSongIds.clear();
    });
  }

  void _toggleSelection(int songId) {
    setState(() {
      if (selectedSongIds.contains(songId)) {
        selectedSongIds.remove(songId);
        if (selectedSongIds.isEmpty) selectionMode = false;
      } else {
        selectedSongIds.add(songId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Prepare only the selected songs to pass when adding to playlists
    final selectedSongs = songs.where((s) => selectedSongIds.contains(s.id)).toList();

    return BlocListener<HomeBloc, HomeState>(
      listener: (context, state) async {
        if (state is SongsLoaded) {
          setState(() {
            songs.clear();
            songs.addAll(state.songs);
            isLoading = false;
            selectionMode = false;
            selectedSongIds.clear();
          });

          Fluttertoast.showToast(msg: '${state.songs.length} songs found');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: selectionMode
              ? Text('${selectedSongIds.length} selected')
              : Text('${songs.length} Songs'),
          leading: selectionMode
              ? IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exitSelectionMode,
          )
              : null,
          actions: selectionMode
              ? [
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select All',
              onPressed: () {
                setState(() {
                  if (selectedSongIds.length == songs.length) {
                    selectedSongIds.clear();
                  } else {
                    selectedSongIds = songs.map((s) => s.id).toSet();
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.favorite_border),
              tooltip: 'Like Selected',
              onPressed: () {
                if (selectedSongIds.isEmpty) return;

                final songBloc = context.read<SongBloc>();
                for (final id in selectedSongIds) {
                  songBloc.add(ToggleFavorite(id.toString()));
                }

                Fluttertoast.showToast(
                  msg: 'Liked ${selectedSongIds.length} songs',
                );

                _exitSelectionMode();
                context.read<HomeBloc>().add(GetSongsEvent());
              },
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add to Playlist',
              onPressed: () {
                if (selectedSongIds.isEmpty) return;
                _showAddToPlaylistModal(context, selectedSongs);
              },
            ),
          ]
              : null,
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: () async {
            context.read<HomeBloc>().add(GetSongsEvent());
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      selectionMode
                          ? const SizedBox()
                          : Text(
                        '${songs.length} Songs',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      IconButton(
                        onPressed: selectionMode
                            ? null
                            : () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => const SortBottomSheet(),
                          );
                        },
                        icon: const Icon(Icons.swap_vert),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(32),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  Assets.shuffleSvg,
                                  width: 20,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(context).textTheme.bodyMedium!.color!,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Shuffle',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            onTap: selectionMode
                                ? null
                                : () {
                              context.read<PlayerBloc>().add(
                                PlayerSetShuffleModeEnabled(true),
                              );

                              final randomSong = songs[Random().nextInt(songs.length)];

                              context.read<PlayerBloc>().add(
                                PlayerLoadSongs(
                                  songs,
                                  sl<MusicPlayer>().getMediaItemFromSong(
                                    randomSong,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(32),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  Assets.playSvg,
                                  width: 20,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(context).textTheme.bodyMedium!.color!,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Play',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            onTap: selectionMode
                                ? null
                                : () {
                              context.read<PlayerBloc>().add(
                                PlayerSetShuffleModeEnabled(false),
                              );

                              context.read<PlayerBloc>().add(
                                PlayerLoadSongs(
                                  songs,
                                  sl<MusicPlayer>().getMediaItemFromSong(
                                    songs[0],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              AnimationLimiter(
                child: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final song = songs[index];
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 500),
                      child: FlipAnimation(
                        child: SongListTile(
                          song: song,
                          songs: songs,
                          isSelected: selectedSongIds.contains(song.id),
                          onTap: () {
                            if (selectionMode) {
                              _toggleSelection(song.id);
                            } else {
                              final player = sl<MusicPlayer>();
                              final mediaItem = player.getMediaItemFromSong(song);
                              context.read<PlayerBloc>().add(
                                PlayerLoadSongs(songs, mediaItem),
                              );
                            }
                          },
                          onLongPress: () {
                            if (!selectionMode) {
                              setState(() {
                                selectionMode = true;
                                selectedSongIds.add(song.id);
                              });
                            }
                          },
                        ),
                      ),
                    );
                  }, childCount: songs.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  void scrollToTop() {
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }
}

// SortBottomSheet remains unchanged from your original.
class SortBottomSheet extends StatefulWidget {
  const SortBottomSheet({super.key});

  @override
  State<SortBottomSheet> createState() => _SortBottomSheetState();
}

class _SortBottomSheetState extends State<SortBottomSheet> {
  int currentSortType = Hive.box(
    HiveBox.boxName,
  ).get(HiveBox.songSortTypeKey, defaultValue: SongSortType.TITLE.index);
  int currentOrderType = Hive.box(
    HiveBox.boxName,
  ).get(HiveBox.songOrderTypeKey, defaultValue: OrderType.ASC_OR_SMALLER.index);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Sort by',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          for (final songSortType in SongSortType.values)
            RadioListTile<int>(
              visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
              value: songSortType.index,
              groupValue: currentSortType,
              title: Text(songSortType.name.capitalize().replaceAll('_', ' ')),
              onChanged: (value) {
                setState(() {
                  currentSortType = value!;
                });
              },
            ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Order by',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          for (final orderType in OrderType.values)
            RadioListTile<int>(
              visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
              value: orderType.index,
              groupValue: currentOrderType,
              title: Text(orderType.name.capitalize().replaceAll('_', ' ')),
              onChanged: (value) {
                setState(() {
                  currentOrderType = value!;
                });
              },
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.read<HomeBloc>().add(
                        SortSongsEvent(currentSortType, currentOrderType),
                      );
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

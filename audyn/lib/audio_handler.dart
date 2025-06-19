import 'dart:io';
import 'dart:convert'; // << Add this import for base64 decoding
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  @override
  final BehaviorSubject<List<MediaItem>> queue = BehaviorSubject<List<MediaItem>>.seeded([]);

  @override
  final BehaviorSubject<MediaItem?> mediaItem = BehaviorSubject<MediaItem?>();

  MyAudioHandler() {
    // Listen to playback events to update playback state
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });

    // Listen to currentIndex changes and update mediaItem accordingly
    _player.currentIndexStream.listen((index) {
      final currentQueue = queue.valueOrNull;
      if (index != null && currentQueue != null && index >= 0 && index < currentQueue.length) {
        mediaItem.add(currentQueue[index]);
      } else {
        mediaItem.add(null);
      }
    });

    // Handle player idle state if needed
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.idle && !state.playing) {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ));
      }
    });
  }

  @override
  Future<void> setQueue(List<MediaItem> newQueue) async {
    queue.add(newQueue);

    final audioSources = newQueue
        .map((item) => AudioSource.uri(Uri.parse(item.id), tag: item))
        .toList();

    try {
      await _player.setAudioSource(ConcatenatingAudioSource(children: audioSources));
      if (newQueue.isNotEmpty) {
        mediaItem.add(newQueue.first);
        await _player.seek(Duration.zero, index: 0);
      } else {
        mediaItem.add(null);
      }
    } catch (e) {
      print('Error setting audio source queue: $e');
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: _mapJustAudioRepeatModeToAudioService(_player.loopMode),
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _mapJustAudioRepeatModeToAudioService(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  LoopMode _mapAudioServiceRepeatModeToJustAudio(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.none:
        return LoopMode.off;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
      case AudioServiceRepeatMode.all:
        return LoopMode.all;
      case AudioServiceRepeatMode.group:
        throw UnimplementedError('Group repeat mode is not supported');
    }
  }
  Future<Uri> _getDefaultArtUri() async {
    final byteData = await rootBundle.load('lib/assets/default_art.jpg');
    final file = File('${(await getTemporaryDirectory()).path}/default_art.jpg');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return Uri.file(file.path);
  }
  Future<Metadata?> extractMetadata(String filePath) async {
    try {
      final metadataRetriever = MetadataRetriever();
      Metadata metadata = await MetadataRetriever.fromFile(File(filePath));
      return metadata;
    } catch (e) {
      print('Error extracting metadata: $e');
      return null;
    }
  }
  Future<File> _saveAlbumArtToTempFile(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/album_art_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> playTrack(
      String uri, {
        String? title,
        String? artist,
        String? album,
        Uri? artUri,
      }) async {
    Metadata? meta;
    if (title == null || artist == null || album == null) {
      meta = await extractMetadata(uri);
    }

    final defaultArtUri = artUri ?? await _getDefaultArtUri();

    Uri finalArtUri;
    if (artUri != null) {
      finalArtUri = artUri;
    } else if (meta?.albumArt != null) {
      final artFile = await _saveAlbumArtToTempFile(meta!.albumArt!);
      finalArtUri = Uri.file(artFile.path);
    } else {
      finalArtUri = defaultArtUri;
    }

    final item = MediaItem(
      id: uri,
      title: title ?? meta?.trackName ?? 'Unknown Title',
      artist: artist ?? meta?.albumArtistName ?? 'Unknown Artist',
      album: album ?? meta?.albumName ?? 'Unknown Album',
      artUri: finalArtUri,
    );

    await setQueue([item]);
    await _player.play();
  }


  // Playback controls
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    final loopMode = _mapAudioServiceRepeatModeToJustAudio(mode);
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: mode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    final enableShuffle = mode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enableShuffle);
    if (enableShuffle) {
      await _player.shuffle();
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: mode));
  }

  // Expose streams for UI and others
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
}
Future<MyAudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.audyn.channel.audio',
      androidNotificationChannelName: 'Audio Playback',
      androidNotificationOngoing: true,
    ),
  );
}
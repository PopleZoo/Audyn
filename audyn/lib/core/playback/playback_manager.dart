import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../audio_handler.dart';
import '../models/music_track.dart';
import '../models/playlist.dart';

enum RepeatMode {
  off,
  one,
  all,
  group,
}

class PlaybackManager extends ChangeNotifier {
  final MyAudioHandler _audioHandler;

  List<MusicTrack> _playlist = [];
  List<MusicTrack>? _originalOrder;
  int _currentIndex = -1;
  bool _isShuffled = false;

  final Map<String, bool> _playlistShuffleStates = {};
  String? _currentPlaylistId;

  RepeatMode _repeatMode = RepeatMode.off;

  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;

  bool _showBottomPlayer = false;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  Timer? _throttleTimer;

  File? _currentCoverFile;
  File? get currentCover => _currentCoverFile;

  PlaybackManager(this._audioHandler) {
    _positionSubscription = _audioHandler.positionStream.listen((pos) {
      _currentPosition = pos;
      _throttleNotifyListeners();
    });

    _durationSubscription = _audioHandler.durationStream.listen((dur) {
      _currentDuration = dur ?? Duration.zero;
      notifyListeners();
    });

    _audioHandler.playbackState.listen((state) {
      _updateBottomPlayerVisibility(state.playing);
    });
  }

  void _throttleNotifyListeners() {
    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      notifyListeners();
      _throttleTimer = Timer(const Duration(milliseconds: 20), () {});
    }
  }

  bool get isPlaying => _audioHandler.playbackState.value.playing;

  MusicTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  bool get isShuffleEnabled => _isShuffled;
  String? get currentPlaylistId => _currentPlaylistId;
  int get currentIndex => _currentIndex;

  Duration get currentPosition => _currentPosition;
  Duration get currentDuration => _currentDuration;

  RepeatMode get repeatMode => _repeatMode;
  bool get showBottomPlayer => _showBottomPlayer;

  Stream playBackStateStream() => _audioHandler.playbackState;
  Stream<Duration> get positionStream => _audioHandler.positionStream;

  void _updateBottomPlayerVisibility(bool isPlaying) {
    final shouldShow = isPlaying || currentTrack != null;
    if (_showBottomPlayer != shouldShow) {
      _showBottomPlayer = shouldShow;
      notifyListeners();
    }
  }

  Future<File?> _loadCoverFile(MusicTrack track) async {
    final path = track.coverUrl;
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  Future<void> playIndex(int index) async {
    if (index < 0 || index >= _playlist.length) {
      debugPrint('[PlaybackManager] Invalid play index $index');
      return;
    }

    debugPrint('[PlaybackManager] Playing index $index');

    _currentIndex = index;

    final track = _playlist[_currentIndex];

    _currentCoverFile = await _loadCoverFile(track);

    _updateBottomPlayerVisibility(true);

    if (track.localPath != null) {
      await _audioHandler.playTrack(track.localPath!);
    } else {
      debugPrint('[PlaybackManager] Track path is null: ${track.id}');
    }

    notifyListeners();
  }



  Future<void> setPlaylist(
      List<MusicTrack> tracks, {
        bool shuffle = false,
        String? playlistId,
      }) async {
    if (_currentPlaylistId == playlistId && _playlist.isNotEmpty) {
      await _audioHandler.play();
      _updateBottomPlayerVisibility(true);
      notifyListeners();
      return;
    }

    await _audioHandler.stop();

    _playlist = List.of(tracks);
    _isShuffled = shuffle;
    _currentPlaylistId = playlistId;

    if (playlistId != null) {
      _playlistShuffleStates[playlistId] = shuffle;
    }

    if (_playlist.isEmpty) {
      debugPrint('[PlaybackManager] Attempted to set an empty playlist.');
      return;
    }

    if (shuffle) {
      _originalOrder = List.of(_playlist);
      _playlist.shuffle();
    } else {
      _originalOrder = null;
    }

    _currentIndex = 0;
    _currentCoverFile = await _loadCoverFile(_playlist[_currentIndex]);
    notifyListeners();

    await playIndex(_currentIndex);
  }

  Future<bool> playTrack(MusicTrack track) async {
    // Make sure playlist is not empty and contains the track
    if (_playlist.isEmpty) {
      debugPrint('[PlaybackManager] Playlist is empty. Cannot play track.');
      return false;
    }

    final index = _playlist.indexWhere((t) => t.id == track.id);
    if (index == -1) {
      debugPrint('[PlaybackManager] Track not found in current playlist: ${track.id}');
      return false;
    }

    // Update current index BEFORE playing
    _currentIndex = index;

    // Optional: preload cover, update UI
    _currentCoverFile = await _loadCoverFile(track);
    notifyListeners();

    await playIndex(_currentIndex);
    return true;
  }



  Future<void> pause() async {
    await _audioHandler.pause();
    _updateBottomPlayerVisibility(false);
    notifyListeners();
  }

  Future<void> play() async {
    await _audioHandler.play();
    _updateBottomPlayerVisibility(true);
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audioHandler.seek(position);
    notifyListeners();
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;

    switch (repeatMode) {
      case RepeatMode.one:
      // Replay current track
        await playIndex(_currentIndex);
        break;

      case RepeatMode.all:
      // Move to next or wrap to start
        _currentIndex = (_currentIndex + 1) % _playlist.length;
        _currentCoverFile = await _loadCoverFile(_playlist[_currentIndex]);
        await playIndex(_currentIndex);
        break;

      case RepeatMode.off:
      // Move next if possible, else stop playback or do nothing
        if (_currentIndex < _playlist.length - 1) {
          _currentIndex++;
          _currentCoverFile = await _loadCoverFile(_playlist[_currentIndex]);
          await playIndex(_currentIndex);
        } else {
          // Optionally: stop playback here if at end
          await stop();
        }
        break;

      case RepeatMode.group:
        throw UnimplementedError('Group repeat mode not supported.');
    }

    notifyListeners();
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;

    switch (repeatMode) {
      case RepeatMode.one:
      // Replay current track
        await playIndex(_currentIndex);
        break;

      case RepeatMode.all:
      // Move to previous or wrap to end
        _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
        _currentCoverFile = await _loadCoverFile(_playlist[_currentIndex]);
        await playIndex(_currentIndex);
        break;

      case RepeatMode.off:
      // Move previous if possible
        if (_currentIndex > 0) {
          _currentIndex--;
          _currentCoverFile = await _loadCoverFile(_playlist[_currentIndex]);
          await playIndex(_currentIndex);
        } else {
          // Optionally: restart current or do nothing
          await playIndex(_currentIndex);
        }
        break;

      case RepeatMode.group:
        throw UnimplementedError('Group repeat mode not supported.');
    }

    notifyListeners();
  }


  void toggleShuffle() {
    if (_playlist.isEmpty) return;

    _isShuffled = !_isShuffled;

    if (_isShuffled) {
      _originalOrder = List.of(_playlist);
      _playlist.shuffle();
    } else if (_originalOrder != null) {
      _playlist = List.of(_originalOrder!);
      _originalOrder = null;
    }

    if (_currentPlaylistId != null) {
      _playlistShuffleStates[_currentPlaylistId!] = _isShuffled;
    }

    notifyListeners();
  }

  void toggleShuffleForPlaylist(Playlist playlist) {
    final current = _playlistShuffleStates[playlist.id] ?? false;
    _playlistShuffleStates[playlist.id] = !current;
    notifyListeners();
  }

  Future<void> seekToStart() async {
    await _audioHandler.seek(Duration.zero);
    notifyListeners();
  }

  bool isPlaylistPlaying(Playlist playlist) =>
      _audioHandler.playbackState.value.playing &&
          _currentPlaylistId == playlist.id;

  bool isCurrentPlaylist(Playlist playlist) =>
      _currentPlaylistId == playlist.id;

  bool isPlaylistShuffled(Playlist playlist) =>
      _playlistShuffleStates[playlist.id] ?? false;

  Future<void> resume() async {
    await _audioHandler.play();
    _updateBottomPlayerVisibility(true);
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioHandler.stop();
    _updateBottomPlayerVisibility(false);
    notifyListeners();
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.group;
        break;
      case RepeatMode.group:
        _repeatMode = RepeatMode.off;
        break;
    }
    notifyListeners();
  }

  /// ✅ New Method to set playlist and play a specific track
  Future<void> setPlaylistAndPlayTrack(
      List<MusicTrack> tracks,
      MusicTrack track, {
        bool shuffle = false,
        String? playlistId,
      }) async {
    await setPlaylist(tracks, shuffle: shuffle, playlistId: playlistId);
    await playTrack(track);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    super.dispose();
  }

  void setRepeatMode(RepeatMode nextMode) {
    _repeatMode = nextMode;
    notifyListeners();
  }

  void setShuffleEnabled(bool newShuffleState) {
    _isShuffled = newShuffleState;
    notifyListeners();
  }

  bool canSkipPrevious() {
    return _playlist.isNotEmpty && _currentIndex > 0;
  }

  bool canSkipNext() {
    return _playlist.isNotEmpty && _currentIndex < _playlist.length - 1;
  }

}

import 'dart:async';

import 'package:flutter/material.dart';
import '../../audio_handler.dart';
import '../models/music_track.dart';
import '../models/playlist.dart';

enum RepeatMode {
  off,
  one,
  all, group,
}

class PlaybackManager extends ChangeNotifier {
  final MyAudioHandler _audioHandler;

  List<MusicTrack> _playlist = [];
  List<MusicTrack>? _originalOrder;
  int _currentIndex = -1;
  bool _isShuffled = false;

  final Map<String, bool> _playlistShuffleStates = {};
  String? _currentPlaylistId;

  // Repeat mode state
  RepeatMode _repeatMode = RepeatMode.off;

  // Position and duration tracking
  Duration? _currentPosition;
  Duration? _currentDuration;

  // Control visibility of the bottom player UI
  bool _showBottomPlayer = false;

  // Stream subscriptions for cleanup
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  PlaybackManager(this._audioHandler) {
    // Listen to playback position updates
    _positionSubscription = _audioHandler.positionStream.listen((pos) {
      _currentPosition = pos;
      notifyListeners();
    });

    // Listen to duration updates (some players may provide null sometimes)
    _durationSubscription = _audioHandler.durationStream.listen((dur) {
      _currentDuration = dur;
      notifyListeners();
    });

    // Optionally, listen to playback state changes to update bottom player visibility
    _audioHandler.playbackState.listen((state) {
      _updateBottomPlayerVisibility(state.playing);
    });
  }

  // === GETTERS ===

  bool get isPlaying => _audioHandler.playbackState.value.playing;

  MusicTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  bool get isShuffleEnabled => _isShuffled;
  String? get currentPlaylistId => _currentPlaylistId;
  int get currentIndex => _currentIndex;

  Duration? get currentPosition => _currentPosition;
  Duration? get currentDuration => _currentDuration;

  RepeatMode get repeatMode => _repeatMode;

  bool get showBottomPlayer => _showBottomPlayer;

  /// Expose playback state stream for UI listening if needed
  Stream playBackStateStream() => _audioHandler.playbackState;

  /// Expose current playback position stream
  Stream<Duration> get positionStream => _audioHandler.positionStream;

  // === PRIVATE METHODS ===

  /// Update bottom player visibility based on playing status or track availability
  void _updateBottomPlayerVisibility(bool isPlaying) {
    final shouldShow = isPlaying || currentTrack != null;
    if (_showBottomPlayer != shouldShow) {
      _showBottomPlayer = shouldShow;
      notifyListeners();
    }
  }

  /// Play the current track based on _currentIndex
  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _playlist.length) return;

    final track = _playlist[_currentIndex];
    if (track.localPath != null) {
      await _audioHandler.playTrack(track.localPath!);
      _updateBottomPlayerVisibility(true);
      notifyListeners();
    } else {
      debugPrint('[PlaybackManager] Track path is null: ${track.id}');
    }
  }

  // === PUBLIC METHODS ===

  /// Sets the current playlist and optionally shuffles it.
  /// If the same playlist is already loaded, resumes playing.
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

    _playlist = List.of(tracks);
    _isShuffled = shuffle;
    _currentPlaylistId = playlistId;
    _currentIndex = 0;

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

    await _playCurrent();
    notifyListeners();
  }

  /// Plays a specific track if it exists in the current playlist.
  Future<void> playTrack(MusicTrack track) async {
    final index = _playlist.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      _currentIndex = index;
      await _playCurrent();
      notifyListeners();
    }
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
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      await _playCurrent();
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await _playCurrent();
      notifyListeners();
    }
  }

  /// Toggles shuffle on/off for the current playlist in memory.
  void toggleShuffle() {
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

  /// Toggles shuffle state flag for a specific playlist (does not reorder tracks).
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

  bool isCurrentPlaylist(Playlist playlist) => _currentPlaylistId == playlist.id;

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

  /// Cycle repeat mode: off -> all -> one -> off
  void cycleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        break;
      case RepeatMode.group:
        _repeatMode = RepeatMode.group;

    }
    notifyListeners();
  }

  /// Dispose stream subscriptions properly to avoid leaks
  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    super.dispose();
  }
}

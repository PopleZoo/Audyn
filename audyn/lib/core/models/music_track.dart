import 'dart:io';

class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String album; // <-- add this
  final String coverUrl; // artwork URL or local path
  final String? localPath;

  MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.coverUrl = '',
    this.localPath,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
      localPath: json['localPath'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'localPath': localPath,
  };

  MusicTrack copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    String? localPath,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      localPath: localPath ?? this.localPath,
    );
  }

  File? get coverFile {
    if (coverUrl.isEmpty) return null;
    try {
      return File(coverUrl);
    } catch (_) {
      return null;
    }
  }

  File? get localFile {
    if (localPath == null || localPath!.isEmpty) return null;
    try {
      return File(localPath!);
    } catch (_) {
      return null;
    }
  }

  /// Add this getter for artUri used in playback_manager.dart (assumes coverUrl is a valid Uri string)
  Uri? get artUri {
    if (coverUrl.isEmpty) return null;
    try {
      return Uri.parse(coverUrl);
    } catch (_) {
      return null;
    }
  }
}

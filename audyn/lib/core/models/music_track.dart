import 'dart:io';

class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl; // Can be a local path or remote URL
  final String? localPath;
  final Duration duration;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.coverUrl = '',
    this.localPath,
    this.duration = Duration.zero,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
      localPath: json['localPath'],
      duration: Duration(milliseconds: json['duration'] ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'localPath': localPath,
    'duration': duration.inMilliseconds,
  };

  /// Returns a File for the cover if it's a local path
  File? get coverFile {
    if (coverUrl.isEmpty) return null;
    final isLocal = !coverUrl.startsWith(RegExp(r'^https?:'));
    if (isLocal) {
      final file = File(coverUrl);
      return file.existsSync() ? file : null;
    }
    return null;
  }

  /// Returns a File for the audio file
  File? get localFile {
    if (localPath == null || localPath!.isEmpty) return null;
    final file = File(localPath!);
    return file.existsSync() ? file : null;
  }

  /// Returns a Uri for the artwork (either local or remote)
  Uri? get artUri {
    if (coverUrl.isEmpty) return null;
    try {
      return Uri.parse(coverUrl);
    } catch (_) {
      return null;
    }
  }

  /// Helper: true if the cover is a local image file
  bool get hasLocalArtwork => coverFile != null;

  /// Helper: true if the cover is a remote image
  bool get hasRemoteArtwork => coverUrl.startsWith(RegExp(r'^https?://'));
}

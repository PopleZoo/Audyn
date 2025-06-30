import 'dart:typed_data';

class DownloadItem {
  final String infoHash;
  final String name;
  final String title;
  final String artist;
  final String album;
  final Uint8List? albumArt;
  final String status; // e.g., 'downloading', 'completed', 'failed'
  final double progress; // 0.0 to 1.0
  final String filePath; // full path if downloaded
  final int seeders;
  final int peers;

  DownloadItem({
    required this.infoHash,
    required this.name,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.albumArt,
    this.status = 'queued',
    this.progress = 0.0,
    this.filePath = '',
    this.seeders = 0,
    this.peers = 0,
  });

  DownloadItem copyWith({
    String? infoHash,
    String? name,
    String? title,
    String? artist,
    String? album,
    Uint8List? albumArt,
    String? status,
    double? progress,
    String? filePath,
    int? seeders,
    int? peers,
  }) {
    return DownloadItem(
      infoHash: infoHash ?? this.infoHash,
      name: name ?? this.name,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArt: albumArt ?? this.albumArt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      filePath: filePath ?? this.filePath,
      seeders: seeders ?? this.seeders,
      peers: peers ?? this.peers,
    );
  }
}

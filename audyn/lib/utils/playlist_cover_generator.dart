import 'dart:io';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:image/image.dart' as img;
import 'package:image_extensions/image_extensions.dart' show copyInto;

/// Generates a composite cover image for a playlist from embedded album art
/// in audio files located in [playlistFolderPath].
///
/// - Scans up to 4 audio files with valid artwork
/// - Saves a `cover.jpg` in the same directory
/// - Returns the full path to the cover image, or null if none found
Future<String?> generatePlaylistCover(String playlistFolderPath) async {
  final dir = Directory(playlistFolderPath);
  if (!await dir.exists()) {
    print('[CoverGen] Folder does not exist: $playlistFolderPath');
    return null;
  }

  final files = dir.listSync().whereType<File>().toList();
  final List<img.Image> thumbnails = [];

  for (final file in files) {
    final path = file.path.toLowerCase();

    if (path.endsWith('.mp3') ||
        path.endsWith('.m4a') ||
        path.endsWith('.flac') ||
        path.endsWith('.ogg')) {
      try {
        final metadata = await MetadataRetriever.fromFile(file);
        final albumArt = metadata.albumArt;

        if (albumArt != null) {
          final cover = img.decodeImage(albumArt);
          if (cover != null) {
            thumbnails.add(img.copyResizeCropSquare(cover, 256));
          }
        }
      } catch (e) {
        print('[CoverGen] Failed to extract metadata from ${file.path}: $e');
      }
    }

    if (thumbnails.length >= 4) break;
  }

  if (thumbnails.isEmpty) {
    print('[CoverGen] No album artwork found in folder: $playlistFolderPath');
    return null;
  }

  final img.Image finalImage;
  if (thumbnails.length == 1) {
    finalImage = thumbnails.first;
  } else {
    finalImage = img.Image(512, 512);
    for (int i = 0; i < thumbnails.length; i++) {
      final x = (i % 2) * 256;
      final y = (i ~/ 2) * 256;
      copyInto(finalImage, thumbnails[i], dstX: x, dstY: y);
    }
  }

  final outputPath = '${dir.path}${Platform.pathSeparator}cover.jpg';
  try {
    final encoded = img.encodeJpg(finalImage, quality: 85);
    await File(outputPath).writeAsBytes(encoded);
    print('[CoverGen] Saved playlist cover to: $outputPath');
    return outputPath;
  } catch (e) {
    print('[CoverGen] Failed to write cover image: $e');
    return null;
  }
}

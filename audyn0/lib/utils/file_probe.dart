// lib/utils/file_probe.dart
import 'dart:io';

/// This function checks whether a given directory contains any files (recursively).
bool probeFilePresence(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return false;
  return dir.listSync(recursive: true, followLinks: false).any((e) => e is File);
}

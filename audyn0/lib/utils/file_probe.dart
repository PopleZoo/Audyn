// lib/utils/file_probe.dart
import 'dart:io';

bool probeFilePresence(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return false;
  return dir.listSync(recursive: true, followLinks: false).any((e) => e is File);
}
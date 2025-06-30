// lib/utils/file_hasher.dart
import 'dart:io';
import 'package:crypto/crypto.dart';

class FileHasher {
  static Future<String> hashFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final digest = sha256.convert(bytes); // or use BLAKE2 if you want to match libtorrent
    return digest.toString();
  }
}

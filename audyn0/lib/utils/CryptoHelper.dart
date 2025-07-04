import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ************************************************************
/// 🔐 1. SIMPLE AES‑256 HELPER
/// ************************************************************
class CryptoHelper {
  CryptoHelper._();

  // This is a valid AES-256 key (32 bytes)
  static const _base64Key = 'MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0'; // 32-char decoded

  static enc.Key get _key {
    final decoded = base64Decode(_base64Key);
    debugPrint('[CryptoHelper] Decoded key bytes length: ${decoded.length}');
    debugPrint('[CryptoHelper] Decoded key (base64): ${base64Encode(decoded)}');
    return enc.Key(decoded); // Must be 32 bytes
  }

  static final enc.IV _iv = enc.IV.fromLength(16);

  static Uint8List encryptJson(Map<String, dynamic> json) {
    try {
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
      final plain = utf8.encode(jsonEncode(json));
      final encrypted = encrypter.encryptBytes(plain, iv: _iv);
      debugPrint('[CryptoHelper] Successfully encrypted ${plain.length} bytes');
      return Uint8List.fromList(encrypted.bytes);
    } catch (e, st) {
      debugPrint('[CryptoHelper] Encryption failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  static Map<String, dynamic>? decryptJson(Uint8List cipherBytes) {
    try {
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: _iv);
      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (e, st) {
      debugPrint('[CryptoHelper] Decryption failed: $e');
      debugPrint('$st');
      return null;
    }
  }
}

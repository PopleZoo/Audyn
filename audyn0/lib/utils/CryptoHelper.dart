import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

/// ************************************************************
/// 🔐 AES‑256 ENCRYPTION HELPER WITH PREFIX FOR JSON & RAW BYTES
/// Uses AES-CBC with a fixed IV (16 zero bytes) and a fixed prefix
/// to identify encrypted payloads.
/// ************************************************************
class CryptoHelper {
  CryptoHelper._();

  // 32-byte base64 key (256 bits)
  static const _base64Key = 'wC9Rnlr7k5jOEr5Aosz/uVgjJKANcXvR4Tpmyp0i1hA=';
  static const _prefix = 'AUDYN'; // Marker prefix for ciphertext

  static enc.Key get _key {
    final decoded = base64Decode(_base64Key);
    _debugLog('[CryptoHelper] Key bytes length: ${decoded.length}');
    return enc.Key(decoded); // 32 bytes → AES-256 key
  }

  // Fixed IV of 16 zero bytes for AES CBC mode
  static final enc.IV _iv = enc.IV.fromLength(16);

  /* ───────────── Public helpers ───────────── */

  /// Encrypts a JSON map, returns encrypted bytes with prefix
  static Uint8List encryptJson(Map<String, dynamic> json) {
    final plain = utf8.encode(jsonEncode(json));
    final cipher = _encrypt(plain);
    _debugLog('[CryptoHelper] Encrypted JSON (${plain.length} bytes)');
    return cipher;
  }

  /// Decrypts bytes previously encrypted with [encryptJson].
  /// Returns Map if valid JSON, else null.
  static Map<String, dynamic>? decryptJson(Uint8List cipherBytes) {
    final plain = _decrypt(cipherBytes);
    if (plain == null) return null;
    try {
      final obj = jsonDecode(utf8.decode(plain));
      return obj is Map<String, dynamic> ? obj : null;
    } catch (_) {
      return null;
    }
  }

  /// Encrypts raw bytes with prefix
  static Uint8List encryptBytes(Uint8List bytes) {
    final cipher = _encrypt(bytes);
    _debugLog('[CryptoHelper] Encrypted raw (${bytes.length} bytes)');
    return cipher;
  }


  /// Decrypts raw bytes previously encrypted with [encryptBytes].
  /// Returns null if prefix missing or decryption fails.
  static Uint8List? decryptBytes(Uint8List cipherBytes) => _decrypt(cipherBytes);

  /* ───────────── Internal core ───────────── */

  static Uint8List _encrypt(List<int> plainBytes) {
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: _iv);
    final prefix = utf8.encode(_prefix);
    return Uint8List.fromList(prefix + encrypted.bytes);
  }

  static Uint8List? _decrypt(Uint8List cipherBytes) {
    final prefix = utf8.encode(_prefix);

    if (!_hasPrefix(cipherBytes, prefix)) {
      _debugLog('[CryptoHelper] Missing or invalid prefix');
      return null;
    }

    final payload = cipherBytes.sublist(prefix.length);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));

    try {
      final plain = encrypter.decryptBytes(enc.Encrypted(payload), iv: _iv);
      return Uint8List.fromList(plain);
    } catch (e) {
      _debugLog('[CryptoHelper] Decryption failed: $e');
      return null;
    }
  }

  static bool _hasPrefix(Uint8List data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }

  static void _debugLog(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}

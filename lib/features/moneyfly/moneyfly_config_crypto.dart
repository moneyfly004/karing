import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:karing/features/moneyfly/moneyfly_secure_store.dart';

class MoneyflyConfigCrypto {
  static const marker = 'moneyfly_encrypted_v1';
  static final _algorithm = AesGcm.with256bits();
  static final _store = MoneyflySecureStore();

  static Future<String> encrypt(String content) async {
    final key = await _store.readOrCreateConfigEncryptionKey();
    final secretKey = SecretKey(base64.decode(key));
    final nonce = _nonce();
    final box = await _algorithm.encrypt(
      utf8.encode(content),
      secretKey: secretKey,
      nonce: nonce,
    );
    return jsonEncode({
      'format': marker,
      'nonce': base64UrlEncode(box.nonce),
      'mac': base64UrlEncode(box.mac.bytes),
      'payload': base64UrlEncode(box.cipherText),
    });
  }

  static Future<String> decryptIfNeeded(String content) async {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('{') || !trimmed.contains(marker)) {
      return content;
    }
    final json = jsonDecode(content);
    if (json is! Map || json['format'] != marker) {
      return content;
    }
    final key = await _store.readConfigEncryptionKey();
    if (key == null || key.isEmpty) {
      return '';
    }
    final box = SecretBox(
      base64Url.decode((json['payload'] ?? '').toString()),
      nonce: base64Url.decode((json['nonce'] ?? '').toString()),
      mac: Mac(base64Url.decode((json['mac'] ?? '').toString())),
    );
    final plain = await _algorithm.decrypt(
      box,
      secretKey: SecretKey(base64.decode(key)),
    );
    return utf8.decode(plain);
  }

  static List<int> _nonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );
  }
}

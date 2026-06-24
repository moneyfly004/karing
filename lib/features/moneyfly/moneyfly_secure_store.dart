import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class MoneyflySecureStore {
  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'moneyfly.access_token';
  static const _refreshTokenKey = 'moneyfly.refresh_token';
  static const _emailKey = 'moneyfly.email';
  static const _deviceIdKey = 'moneyfly.device_id';
  static const _managedGroupIdKey = 'moneyfly.managed_group_id';
  static const _configEncryptionKeyKey = 'moneyfly.config_encryption_key';

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String email,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _emailKey, value: email);
  }

  Future<String?> readAccessToken() {
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<String?> readEmail() {
    return _storage.read(key: _emailKey);
  }

  Future<String> readDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final deviceId = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: deviceId);
    return deviceId;
  }

  Future<String?> readManagedGroupId() {
    return _storage.read(key: _managedGroupIdKey);
  }

  Future<void> saveManagedGroupId(String groupId) async {
    await _storage.write(key: _managedGroupIdKey, value: groupId);
  }

  Future<String?> readConfigEncryptionKey() {
    return _storage.read(key: _configEncryptionKeyKey);
  }

  Future<String> readOrCreateConfigEncryptionKey() async {
    final existing = await readConfigEncryptionKey();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64Encode(bytes);
    await _storage.write(key: _configEncryptionKeyKey, value: key);
    return key;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _managedGroupIdKey);
    await _storage.delete(key: _configEncryptionKeyKey);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vpn_service_platform_interface.dart';

/// An implementation of [VpnServicePlatform] that uses method channels.
class MethodChannelVpnService extends VpnServicePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('vpn_service');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}

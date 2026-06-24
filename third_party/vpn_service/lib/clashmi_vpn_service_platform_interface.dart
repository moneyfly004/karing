import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'vpn_service_method_channel.dart';

abstract class VpnServicePlatform extends PlatformInterface {
  /// Constructs a VpnServicePlatform.
  VpnServicePlatform() : super(token: _token);

  static final Object _token = Object();

  static VpnServicePlatform _instance = MethodChannelVpnService();

  /// The default instance of [VpnServicePlatform] to use.
  ///
  /// Defaults to [MethodChannelVpnService].
  static VpnServicePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VpnServicePlatform] when
  /// they register themselves.
  static set instance(VpnServicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

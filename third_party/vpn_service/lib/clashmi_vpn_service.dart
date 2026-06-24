import 'vpn_service_platform_interface.dart';

export 'proxy_manager.dart';
export 'state.dart';
export 'vpn_service.dart';

class VpnService {
  Future<String?> getPlatformVersion() {
    return VpnServicePlatform.instance.getPlatformVersion();
  }
}

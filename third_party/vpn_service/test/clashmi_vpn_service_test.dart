import 'package:clashmi_vpn_service/state.dart';
import 'package:clashmi_vpn_service/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VpnServiceConfig round trips through json', () {
    final config = VpnServiceConfig()
      ..control_port = 9090
      ..base_dir = '/data/user/0/com.nebula.clashmi/files'
      ..core_path = '/profiles/current.yaml'
      ..secret = 'secret'
      ..prepare = true
      ..wake_lock = true
      ..enable_ipv6 = true;

    final restored = VpnServiceConfig()..fromJson(config.toJson());

    expect(restored.control_port, 9090);
    expect(restored.base_dir, config.base_dir);
    expect(restored.core_path, config.core_path);
    expect(restored.secret, config.secret);
    expect(restored.prepare, isTrue);
    expect(restored.wake_lock, isTrue);
    expect(restored.enable_ipv6, isTrue);
  });

  test('FlutterVpnServiceState parses known and unknown names', () {
    expect(
      FlutterVpnServiceState.fromName('connected'),
      FlutterVpnServiceState.connected,
    );
    expect(
      FlutterVpnServiceState.fromName('missing'),
      FlutterVpnServiceState.invalid,
    );
  });
}

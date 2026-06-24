import 'state.dart';
import 'vpn_service.dart';

abstract class VpnServicePlatformInterface {
  Future<VpnServiceWaitResult> start(Duration timeout);
  Future<void> stop();
  Future<VpnServiceWaitResult> restart(Duration timeout);
  Future<FlutterVpnServiceState> get currentState;
}

enum FlutterVpnServiceState {
  invalid,
  disconnected,
  connecting,
  connected,
  reasserting,
  disconnecting;

  static FlutterVpnServiceState fromName(String? name) {
    return FlutterVpnServiceState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => FlutterVpnServiceState.invalid,
    );
  }
}

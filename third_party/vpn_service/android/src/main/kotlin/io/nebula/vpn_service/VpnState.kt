package io.nebula.vpn_service

enum class VpnState {
    INVALID,
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    REASSERTING,
    DISCONNECTING,
}

# clashmi_vpn_service

Open VPN bridge for Clash Mi.

## Scope

This package is the replacement bridge for the previous closed VPN service
package. The current milestone is Android-only:

- keep Clash Mi's Dart-facing VPN API compatible;
- bind the `cyenxchen/mihomo` Go core with `gomobile`;
- implement Android `VpnService` startup, TUN open, traffic polling, and stop;
- keep iOS source layout available for a later `NEPacketTunnelProvider` port.

The current native Android `start` method opens an Android `VpnService` TUN fd
and runs the `cyenxchen/mihomo` gomobile core. Non-Android platforms are not
registered as working implementations yet.

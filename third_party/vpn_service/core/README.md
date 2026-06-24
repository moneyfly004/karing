# Clash Mi VPN Core Wrapper

This directory will hold the Android-first Go wrapper for `cyenxchen/mihomo`.

Planned MVP exports:

- `Setup(optionsJson string) string`
- `Start(optionsJson string, platform PlatformInterface) string`
- `Stop() string`
- `GetTraffic() string`
- `PlatformInterface.OpenTun(optionsJson string) (int32, error)`
- `PlatformInterface.ProtectFd(fd int32) bool`

The wrapper should be built into an Android AAR with `gomobile bind` and wired
into the Android plugin before the native `start` method reports success.

Android builds must include `-tags with_gvisor,cmfa`. The runtime defaults to
`tun.stack: system` when the profile/patch does not specify a stack, while the
same binary also supports profiles that explicitly request `tun.stack: gvisor`.

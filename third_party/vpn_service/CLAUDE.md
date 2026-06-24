# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

`clashmi_vpn_service` 是 Clash Mi 客户端使用的开源 Flutter 插件,通过 gomobile 把 mihomo (Meta 分支) 内核绑定到 Android `VpnService`,替代之前的闭源桥接包。

三层结构:
- `lib/` — Dart API(`FlutterVpnService.start/stop/currentState/clashiApiTraffic/clashiApiConnections`)
- `android/src/main/kotlin/` — Kotlin 插件、`ClashMiVpnService`、TUN 生命周期
- `core/mobile/` + `core/mihomo/`(submodule)— Go 包装层,gomobile 导出 `Start/Stop/...`

`ios/`、`macos/` 模板文件存在但**未实现**;插件目前在 pubspec.yaml 中声明仅 Android,非 Android 平台显式返回错误。

## 平台范围

- **Android-only,arm64-only**。修改时不要新增其他平台的实现声明,除非用户明确要求。
- `minSdk = 26`、`compileSdk = 36`、Kotlin 2.2.20、JVM 17。`-androidapi 26` 与 minSdk 必须保持一致。

## 构建链(关键)

修改 `core/mobile/*.go` 后必须重建 AAR 并重新解包,Kotlin 才能看到变化。完整链路:

```sh
# 1. gomobile bind —— tags 必须带 with_gvisor,cmfa
cd core/mobile
gomobile bind -target=android/arm64 -androidapi 26 -tags with_gvisor,cmfa \
  -javapkg=com.cyenx.clashmi.core -o ../../android/src/main/libs/clashmicore.aar .

# 2. 从 AAR 解包给 Gradle 用
cd ../..
unzip -p android/src/main/libs/clashmicore.aar classes.jar > android/libs/clashmicore.jar
unzip -p android/src/main/libs/clashmicore.aar jni/arm64-v8a/libgojni.so \
  > android/src/main/jniLibs/arm64-v8a/libgojni.so
```

**`-tags with_gvisor,cmfa` 不是可选的**:缺少它,gVisor profile 配置可解析但 listener 不会启动,表现为静默失败。

## 测试与静态检查

- Go: `cd core/mobile && go test -tags with_gvisor,cmfa ./...`
- Dart: `flutter analyze` + `flutter test`(根目录)
- 集成验证: `cd example && flutter build apk --debug`,在装机上跑通 prepare → start → 走流量 → stop,确认 logcat 无 fdsan abort

修改 Go 或 Kotlin 后,优先用 example 工程做端到端验证,而不是只跑 `flutter test`。

## 已知陷阱

1. **TUN 地址归一化**:Go wrapper 强制把 `dns.fake-ip-range` 设为 `172.19.0.1/16`,以匹配 Android 端硬编码的 `172.19.0.1/30`。修改时若动到任一边,另一边必须同步,否则触发 `bind: cannot assign requested address`。

2. **TUN fd 所有权移交**:Kotlin 打开 TUN fd 后调用 `Clashmicore.start(...)`,**调用后必须立刻把 `tunFd = -1`**。Go 拥有该 fd 的生命周期;若 Kotlin 这边继续 close,会触发 fdsan abort。

3. **TUN stack 默认值**:Android 运行时默认 `tun.stack: system`。要走 gVisor 必须 profile 中显式声明,**且** AAR 用 `with_gvisor` tag 构建。

4. **`core/mihomo` 是 submodule**(指向 `cyenxchen/mihomo` Meta 分支)。clone 后需要 `git submodule update --init --recursive`,升级时谨慎。

   本地开发时,同级目录通常并存一份独立工作副本 `../mihomo`,与该 submodule 同源(同一 `cyenxchen/mihomo` fork,fork 自 `MetaCubeX/mihomo` 上游)。改 mihomo 代码的常见流程:在 `../mihomo` 中开发并提交 → 推到 `cyenxchen/mihomo` Meta 分支 → 回到本仓库 `cd core/mihomo && git fetch && git checkout <commit>`(或 `git submodule update --remote core/mihomo`)→ 重新跑「构建链」段落里的 gomobile bind / 解包步骤 → 提交 submodule 指针与 AAR/JAR/SO 产物。

## 提交与发布

- 修改 Go 代码后,**生成的 `clashmicore.aar` / `clashmicore.jar` / `libgojni.so` 也需要一并提交**(Gradle 直接消费它们,Clash Mi app 通过 path 依赖引用本仓库)。
- 上游应用 Clash Mi 通过相对路径 `../clashmi-vpn-service` 引用本插件;改动 Dart API 时记得同步上游调用点。
- `.github/workflows/rebuild-android-core.yml` 会在本仓库 `main` 更新、收到 `mihomo-updated` dispatch、或手动触发时重建 gomobile Android 产物。若产物或 `core/mihomo` submodule 有变化,workflow 会提交回本仓库,随后 dispatch `cyenxchen/clashmi` 自动发布新版 APK。

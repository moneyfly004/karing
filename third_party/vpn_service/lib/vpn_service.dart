// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'proxy_manager.dart';
import 'state.dart';

class VpnServiceResultError {
  String message;
  final bool isCloseError;

  VpnServiceResultError(this.message, {this.isCloseError = false});

  factory VpnServiceResultError.fromJson(Map<String, Object?> json) {
    return VpnServiceResultError(
      json['message']?.toString() ?? '',
      isCloseError: json['is_close_error'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'message': message,
        'is_close_error': isCloseError,
      };
}

enum VpnServiceWaitType { done, error, timeout }

class VpnServiceWaitResult {
  final VpnServiceWaitType type;
  final VpnServiceResultError? err;

  const VpnServiceWaitResult(this.type, {this.err});

  factory VpnServiceWaitResult.done() {
    return const VpnServiceWaitResult(VpnServiceWaitType.done);
  }

  factory VpnServiceWaitResult.error(String message) {
    return VpnServiceWaitResult(
      VpnServiceWaitType.error,
      err: VpnServiceResultError(message),
    );
  }

  factory VpnServiceWaitResult.fromJson(Map<String, Object?> json) {
    final type = VpnServiceWaitType.values.firstWhere(
      (item) => item.name == json['type'],
      orElse: () => VpnServiceWaitType.error,
    );
    final errJson = json['err'];
    return VpnServiceWaitResult(
      type,
      err: errJson is Map
          ? VpnServiceResultError.fromJson(Map<String, Object?>.from(errJson))
          : null,
    );
  }
}

class VpnServiceConfig {
  int control_port = 0;
  String base_dir = '';
  String work_dir = '';
  String cache_dir = '';
  String core_path = '';
  String core_path_patch = '';
  String core_path_patch_final = '';
  String log_path = '';
  String err_path = '';
  String id = '';
  String version = '';
  String name = '';
  String secret = '';
  String install_refer = '';
  int expired_time = 0;
  String time_connect = '';
  String time_disconnect = '';
  String sentry_minversion = '';
  bool prepare = false;
  bool wake_lock = false;
  bool auto_connect_at_boot = false;
  bool enable_ipv6 = false;
  bool exclude_device_communication = false;

  void fromJson(Map<String, Object?> json) {
    control_port = (json['control_port'] as num?)?.toInt() ?? 0;
    base_dir = json['base_dir']?.toString() ?? '';
    work_dir = json['work_dir']?.toString() ?? '';
    cache_dir = json['cache_dir']?.toString() ?? '';
    core_path = json['core_path']?.toString() ?? '';
    core_path_patch = json['core_path_patch']?.toString() ?? '';
    core_path_patch_final = json['core_path_patch_final']?.toString() ?? '';
    log_path = json['log_path']?.toString() ?? '';
    err_path = json['err_path']?.toString() ?? '';
    id = json['id']?.toString() ?? '';
    version = json['version']?.toString() ?? '';
    name = json['name']?.toString() ?? '';
    secret = json['secret']?.toString() ?? '';
    install_refer = json['install_refer']?.toString() ?? '';
    expired_time = (json['expired_time'] as num?)?.toInt() ?? 0;
    time_connect = json['time_connect']?.toString() ?? '';
    time_disconnect = json['time_disconnect']?.toString() ?? '';
    sentry_minversion = json['sentry_minversion']?.toString() ?? '';
    prepare = json['prepare'] == true;
    wake_lock = json['wake_lock'] == true;
    auto_connect_at_boot = json['auto_connect_at_boot'] == true;
    enable_ipv6 = json['enable_ipv6'] == true;
    exclude_device_communication = json['exclude_device_communication'] == true;
  }

  Map<String, Object?> toJson() => {
        'control_port': control_port,
        'base_dir': base_dir,
        'work_dir': work_dir,
        'cache_dir': cache_dir,
        'core_path': core_path,
        'core_path_patch': core_path_patch,
        'core_path_patch_final': core_path_patch_final,
        'log_path': log_path,
        'err_path': err_path,
        'id': id,
        'version': version,
        'name': name,
        'secret': secret,
        'install_refer': install_refer,
        'expired_time': expired_time,
        'time_connect': time_connect,
        'time_disconnect': time_disconnect,
        'sentry_minversion': sentry_minversion,
        'prepare': prepare,
        'wake_lock': wake_lock,
        'auto_connect_at_boot': auto_connect_at_boot,
        'enable_ipv6': enable_ipv6,
        'exclude_device_communication': exclude_device_communication,
      };
}

class FlutterVpnService {
  static const MethodChannel _channel = MethodChannel('vpn_service');
  static final List<
      FutureOr<void> Function(
        FlutterVpnServiceState state,
        Map<String, String> params,
      )> _stateListeners = [];
  static bool _methodHandlerReady = false;
  static VpnServiceConfig? _desktopConfig;
  static String _desktopServicePath = '';
  static String _desktopConfigFilePath = '';
  static Process? _desktopProcess;
  static FlutterVpnServiceState _desktopState =
      FlutterVpnServiceState.disconnected;

  static void _ensureMethodHandler() {
    if (_methodHandlerReady) {
      return;
    }
    _methodHandlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'stateChanged') {
        return null;
      }
      final args = Map<String, Object?>.from(call.arguments as Map);
      final state = FlutterVpnServiceState.fromName(args['state']?.toString());
      final params = (args['params'] is Map)
          ? Map<String, String>.from(args['params'] as Map)
          : <String, String>{};
      for (final listener in List.of(_stateListeners)) {
        await listener(state, params);
      }
      return null;
    });
  }

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    _ensureMethodHandler();
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String> getABIs() async {
    return await _invoke<String>('getABIs') ?? '[]';
  }

  static Future<String> getSystemVersion() async {
    return await _invoke<String>('getSystemVersion') ?? '';
  }

  static Future<Directory?> getAppGroupDirectory(String groupId) async {
    final path = await _invoke<String>('getAppGroupDirectory', {
      'groupId': groupId,
    });
    return path == null || path.isEmpty ? null : Directory(path);
  }

  static void onStateChanged(
    FutureOr<void> Function(
      FlutterVpnServiceState state,
      Map<String, String> params,
    ) callback,
  ) {
    _ensureMethodHandler();
    _stateListeners.add(callback);
  }

  static Future<FlutterVpnServiceState> get currentState async {
    final state = await _invoke<String>('currentState');
    final nativeState = FlutterVpnServiceState.fromName(state);
    if (nativeState != FlutterVpnServiceState.invalid) {
      return nativeState;
    }
    if (_supportsDesktopProcessFallback) {
      return _desktopCurrentState();
    }
    return FlutterVpnServiceState.disconnected;
  }

  static Future<void> prepareConfig({
    required VpnServiceConfig config,
    required String tunnelServicePath,
    required String configFilePath,
    required bool systemExtension,
    required String bundleIdentifier,
    required String uiServerAddress,
    required String uiLocalizedDescription,
    required List<int> excludePorts,
  }) async {
    _desktopConfig = config;
    _desktopServicePath = tunnelServicePath;
    _desktopConfigFilePath = configFilePath;
    await _invoke<void>('prepareConfig', {
      'config': config.toJson(),
      'tunnelServicePath': tunnelServicePath,
      'configFilePath': configFilePath,
      'systemExtension': systemExtension,
      'bundleIdentifier': bundleIdentifier,
      'uiServerAddress': uiServerAddress,
      'uiLocalizedDescription': uiLocalizedDescription,
      'excludePorts': excludePorts,
    });
  }

  static Future<VpnServiceWaitResult> start(Duration timeout) async {
    return _waitResult('start', timeout);
  }

  static Future<VpnServiceWaitResult> restart(Duration timeout) async {
    return _waitResult('restart', timeout);
  }

  static Future<VpnServiceWaitResult> _waitResult(
    String method,
    Duration timeout,
  ) async {
    final result = await _invoke<Map>(method, {
      'timeoutMillis': timeout.inMilliseconds,
    });
    if (result != null) {
      return VpnServiceWaitResult.fromJson(Map<String, Object?>.from(result));
    }
    if (_supportsDesktopProcessFallback) {
      return _desktopWaitResult(method, timeout);
    }
    if (!Platform.isAndroid) {
      return VpnServiceWaitResult.error(
        'vpn_service does not have a native implementation on this platform',
      );
    }
    return VpnServiceWaitResult.error('$method is not implemented');
  }

  static Future<void> stop() async {
    await _invoke<void>('stop');
    if (_supportsDesktopProcessFallback) {
      await _desktopStop();
    }
  }

  static Future<String> clashiApiTraffic() async {
    final native = await _invoke<String>('clashiApiTraffic');
    if (native != null) {
      return native;
    }
    if (_supportsDesktopProcessFallback) {
      return await _desktopApiGet('/traffic') ?? '{"up":0,"down":0}';
    }
    return '{"up":0,"down":0}';
  }

  static Future<String> clashiApiConnections(bool withConnectionsList) async {
    final native = await _invoke<String>('clashiApiConnections', {
      'withConnectionsList': withConnectionsList,
    });
    if (native != null) {
      return native;
    }
    if (_supportsDesktopProcessFallback) {
      return await _desktopApiGet(
            '/connections?noConnections=${!withConnectionsList}',
          ) ??
          '{"uploadTotal":0,"downloadTotal":0,"memory":0,"connections":[]}';
    }
    return '{"uploadTotal":0,"downloadTotal":0,"memory":0,"connections":[]}';
  }

  static Future<VpnServiceResultError?> installService() async {
    return _nullableError(await _invoke<Map>('installService'));
  }

  static Future<VpnServiceResultError?> uninstallService() async {
    return _nullableError(await _invoke<Map>('uninstallService'));
  }

  static Future<bool> isRunAsAdmin() async {
    return await _invoke<bool>('isRunAsAdmin') ?? false;
  }

  static Future<bool> isServiceAuthorized(String servicePath) async {
    return await _invoke<bool>('isServiceAuthorized', {
          'servicePath': servicePath,
        }) ??
        false;
  }

  static Future<VpnServiceResultError?> authorizeService(
    String servicePath,
    String password,
  ) async {
    return _nullableError(
      await _invoke<Map>('authorizeService', {
        'servicePath': servicePath,
        'password': password,
      }),
    );
  }

  static Future<String?> setExcludeFromRecents(bool value) async {
    return _invoke<String>('setExcludeFromRecents', {'value': value});
  }

  static Future<void> setAlwaysOn(bool value) async {
    await _invoke<void>('setAlwaysOn', {'value': value});
  }

  static Future<void> setSystemProxy(ProxyOption option) async {
    await _invoke<void>('setSystemProxy', option.toJson());
    if (_supportsSystemProxyFallback) {
      await _setDesktopSystemProxy(option);
    }
  }

  static Future<void> cleanSystemProxy() async {
    await _invoke<void>('cleanSystemProxy');
    if (_supportsSystemProxyFallback) {
      await _cleanDesktopSystemProxy();
    }
  }

  static Future<bool> getSystemProxyEnable(ProxyOption option) async {
    final native = await _invoke<bool>('getSystemProxyEnable', option.toJson());
    if (native != null) {
      return native;
    }
    if (_supportsSystemProxyFallback) {
      return _getDesktopSystemProxyEnable(option);
    }
    return false;
  }

  static Future<void> firewallAddApp(String path, String name) async {
    await _invoke<void>('firewallAddApp', {'path': path, 'name': name});
  }

  static Future<void> firewallAddPorts(List<int> ports, String name) async {
    await _invoke<void>('firewallAddPorts', {'ports': ports, 'name': name});
  }

  static Future<String?> getProcessList() {
    return _invoke<String>('getProcessList');
  }

  static Future<Uint8List?> getProcessIcon(String identifier) {
    return _invoke<Uint8List>('getProcessIcon', {'identifier': identifier});
  }

  static Future<void> autoStartCreate(
    String taskName,
    String appPath, {
    String processArgs = '',
    bool runElevated = false,
  }) async {
    await _invoke<void>('autoStartCreate', {
      'taskName': taskName,
      'appPath': appPath,
      'processArgs': processArgs,
      'runElevated': runElevated,
    });
  }

  static Future<void> autoStartDelete(String taskName) async {
    await _invoke<void>('autoStartDelete', {'taskName': taskName});
  }

  static Future<bool> autoStartIsActive(String taskName) async {
    return await _invoke<bool>('autoStartIsActive', {'taskName': taskName}) ??
        false;
  }

  static Future<void> hideDockIcon(bool hide) async {
    await _invoke<void>('hideDockIcon', {'hide': hide});
  }

  static VpnServiceResultError? _nullableError(Map? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    return VpnServiceResultError.fromJson(Map<String, Object?>.from(json));
  }

  static bool get _supportsDesktopProcessFallback =>
      Platform.isWindows || Platform.isLinux;

  static bool get _supportsSystemProxyFallback =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<VpnServiceWaitResult> _desktopWaitResult(
    String method,
    Duration timeout,
  ) async {
    if (method == 'restart') {
      await _desktopStop();
    }
    if (method != 'start' && method != 'restart') {
      return VpnServiceWaitResult.error('$method is not implemented');
    }
    final config = _desktopConfig;
    if (config == null) {
      return VpnServiceWaitResult.error('desktop service config is not ready');
    }
    final servicePath = _desktopServicePath;
    if (servicePath.isEmpty || !await File(servicePath).exists()) {
      return VpnServiceWaitResult.error(
          'service binary not found: $servicePath');
    }
    final coreConfigPath =
        config.core_path.isNotEmpty ? config.core_path : _desktopConfigFilePath;
    if (coreConfigPath.isEmpty || !await File(coreConfigPath).exists()) {
      return VpnServiceWaitResult.error(
          'service config not found: $coreConfigPath');
    }

    await _desktopStop();
    _desktopState = FlutterVpnServiceState.connecting;
    _notifyState(_desktopState);

    try {
      final workDir = config.base_dir.isNotEmpty
          ? config.base_dir
          : File(servicePath).parent.path;
      _desktopProcess = await Process.start(
        servicePath,
        ['run', '-c', coreConfigPath],
        workingDirectory: workDir,
        mode: ProcessStartMode.normal,
      );
      _desktopProcess!.stdout.transform(utf8.decoder).listen((_) {});
      _desktopProcess!.stderr.transform(utf8.decoder).listen((_) {});
      _desktopProcess!.exitCode.then((exitCode) {
        if (_desktopProcess != null) {
          _desktopProcess = null;
          _desktopState = FlutterVpnServiceState.disconnected;
          _notifyState(_desktopState, {'exitCode': exitCode.toString()});
        }
      });
    } catch (err) {
      _desktopProcess = null;
      _desktopState = FlutterVpnServiceState.disconnected;
      _notifyState(_desktopState);
      return VpnServiceWaitResult.error(err.toString());
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _desktopApiReachable()) {
        _desktopState = FlutterVpnServiceState.connected;
        _notifyState(_desktopState);
        return VpnServiceWaitResult.done();
      }
      if (_desktopProcess == null) {
        _desktopState = FlutterVpnServiceState.disconnected;
        _notifyState(_desktopState);
        return VpnServiceWaitResult.error('service exited before ready');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    _desktopState = FlutterVpnServiceState.disconnected;
    _notifyState(_desktopState);
    return VpnServiceWaitResult(
      VpnServiceWaitType.timeout,
      err: VpnServiceResultError('service start timeout'),
    );
  }

  static Future<void> _desktopStop() async {
    final apiReachable = await _desktopApiReachable();
    final process = _desktopProcess;
    _desktopProcess = null;
    if (process == null) {
      if (apiReachable) {
        await _desktopKillResidualProcess();
      }
      _desktopState = FlutterVpnServiceState.disconnected;
      _notifyState(_desktopState);
      return;
    }
    _desktopState = FlutterVpnServiceState.disconnecting;
    _notifyState(_desktopState);
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      if (Platform.isWindows) {
        await _runProcess('taskkill', [
          '/PID',
          process.pid.toString(),
          '/T',
          '/F',
        ]);
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }
    _desktopState = FlutterVpnServiceState.disconnected;
    _notifyState(_desktopState);
  }

  static Future<void> _desktopKillResidualProcess() async {
    if (_desktopServicePath.isEmpty) {
      return;
    }
    if (Platform.isWindows) {
      await _runProcess('taskkill', [
        '/IM',
        _basename(_desktopServicePath),
        '/T',
        '/F',
      ]);
    } else if (Platform.isLinux) {
      await _runProcess('pkill', ['-f', _desktopServicePath]);
    }
  }

  static Future<FlutterVpnServiceState> _desktopCurrentState() async {
    if (await _desktopApiReachable()) {
      _desktopState = FlutterVpnServiceState.connected;
      return _desktopState;
    }
    if (_desktopProcess == null) {
      _desktopState = FlutterVpnServiceState.disconnected;
      return _desktopState;
    }
    return _desktopState == FlutterVpnServiceState.invalid
        ? FlutterVpnServiceState.disconnected
        : _desktopState;
  }

  static Future<bool> _desktopApiReachable() async {
    final version = await _desktopApiGet('/version');
    if (version != null) {
      return true;
    }
    return await _desktopApiGet('/configs') != null;
  }

  static Future<String?> _desktopApiGet(String path) async {
    final config = _desktopConfig;
    if (config == null || config.control_port <= 0) {
      return null;
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 1);
    try {
      final uri = Uri.parse('http://127.0.0.1:${config.control_port}$path');
      final request = await client.getUrl(uri);
      if (config.secret.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${config.secret}');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
  }

  static Future<void> _notifyState(
    FlutterVpnServiceState state, [
    Map<String, String> params = const {},
  ]) async {
    for (final listener in List.of(_stateListeners)) {
      await listener(state, params);
    }
  }

  static Future<void> _setDesktopSystemProxy(ProxyOption option) async {
    if (Platform.isWindows) {
      await _runProcess('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '1',
        '/f',
      ]);
      await _runProcess('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        '${option.host}:${option.port}',
        '/f',
      ]);
      await _runProcess('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyOverride',
        '/t',
        'REG_SZ',
        '/d',
        option.bypassDomain.join(';'),
        '/f',
      ]);
    } else if (Platform.isLinux) {
      await _runProcess('gsettings', [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'manual',
      ]);
      await _runProcess('gsettings', [
        'set',
        'org.gnome.system.proxy.http',
        'host',
        option.host,
      ]);
      await _runProcess('gsettings', [
        'set',
        'org.gnome.system.proxy.http',
        'port',
        option.port.toString(),
      ]);
      await _runProcess('gsettings', [
        'set',
        'org.gnome.system.proxy.https',
        'host',
        option.host,
      ]);
      await _runProcess('gsettings', [
        'set',
        'org.gnome.system.proxy.https',
        'port',
        option.port.toString(),
      ]);
    } else if (Platform.isMacOS) {
      for (final service in await _macNetworkServices()) {
        await _runProcess('networksetup', [
          '-setwebproxy',
          service,
          option.host,
          option.port.toString(),
        ]);
        await _runProcess('networksetup', [
          '-setsecurewebproxy',
          service,
          option.host,
          option.port.toString(),
        ]);
      }
    }
  }

  static Future<void> _cleanDesktopSystemProxy() async {
    if (Platform.isWindows) {
      await _runProcess('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f',
      ]);
    } else if (Platform.isLinux) {
      await _runProcess('gsettings', [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'none',
      ]);
    } else if (Platform.isMacOS) {
      for (final service in await _macNetworkServices()) {
        await _runProcess('networksetup', [
          '-setwebproxystate',
          service,
          'off',
        ]);
        await _runProcess(
          'networksetup',
          ['-setsecurewebproxystate', service, 'off'],
        );
      }
    }
  }

  static Future<bool> _getDesktopSystemProxyEnable(ProxyOption option) async {
    if (Platform.isWindows) {
      final result = await _runProcess('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ]);
      if (result == null) {
        return false;
      }
      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      return output.contains('0x1');
    }
    if (Platform.isLinux) {
      final result = await _runProcess('gsettings', [
        'get',
        'org.gnome.system.proxy',
        'mode',
      ]);
      if (result == null) {
        return false;
      }
      return result.stdout.toString().contains('manual');
    }
    if (Platform.isMacOS) {
      for (final service in await _macNetworkServices()) {
        final result = await _runProcess('networksetup', [
          '-getwebproxy',
          service,
        ]);
        if (result == null) {
          continue;
        }
        final output = result.stdout.toString();
        if (output.contains('Enabled: Yes') &&
            output.contains('Server: ${option.host}') &&
            output.contains('Port: ${option.port}')) {
          return true;
        }
      }
    }
    return false;
  }

  static Future<List<String>> _macNetworkServices() async {
    final result = await _runProcess('networksetup', [
      '-listallnetworkservices',
    ]);
    if (result == null) {
      return const [];
    }
    if (result.exitCode != 0) {
      return const [];
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('*'))
        .where((line) => !line.startsWith('An asterisk'))
        .toList();
  }

  static Future<ProcessResult?> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return await Process.run(executable, arguments);
    } catch (_) {
      return null;
    }
  }

  static String _basename(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index == -1) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }
}

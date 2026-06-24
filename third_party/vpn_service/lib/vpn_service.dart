// ignore_for_file: non_constant_identifier_names

import 'dart:async';
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
    return FlutterVpnServiceState.fromName(state ?? 'disconnected');
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
    if (!Platform.isAndroid) {
      return VpnServiceWaitResult.error(
        'vpn_service currently supports Android only',
      );
    }
    final result = await _invoke<Map>(method, {
      'timeoutMillis': timeout.inMilliseconds,
    });
    if (result == null) {
      return VpnServiceWaitResult.error('$method is not implemented');
    }
    return VpnServiceWaitResult.fromJson(Map<String, Object?>.from(result));
  }

  static Future<void> stop() async {
    await _invoke<void>('stop');
  }

  static Future<String> clashiApiTraffic() async {
    return await _invoke<String>('clashiApiTraffic') ?? '{"up":0,"down":0}';
  }

  static Future<String> clashiApiConnections(bool withConnectionsList) async {
    return await _invoke<String>('clashiApiConnections', {
          'withConnectionsList': withConnectionsList,
        }) ??
        '{"uploadTotal":0,"downloadTotal":0,"memory":0,"connections":[]}';
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
  }

  static Future<void> cleanSystemProxy() async {
    await _invoke<void>('cleanSystemProxy');
  }

  static Future<bool> getSystemProxyEnable(ProxyOption option) async {
    return await _invoke<bool>('getSystemProxyEnable', option.toJson()) ??
        false;
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
}

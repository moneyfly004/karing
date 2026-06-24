// ignore_for_file: constant_identifier_names

import 'package:flutter/services.dart';

const List<String> ProxyBypassDoaminsDefault = [
  'localhost',
  '127.0.0.1',
  '::1',
];

class ProxyOption {
  final String host;
  final int port;
  final List<String> bypassDomain;

  const ProxyOption(this.host, this.port, this.bypassDomain);

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'bypassDomain': bypassDomain,
  };
}

class ProxyManager {
  static const MethodChannel _channel = MethodChannel('vpn_service');

  Future<void> setExcludeDevices(Set<String> devices) async {
    try {
      await _channel.invokeMethod<void>('proxy.setExcludeDevices', {
        'devices': devices.toList(),
      });
    } on MissingPluginException {
      return;
    }
  }
}

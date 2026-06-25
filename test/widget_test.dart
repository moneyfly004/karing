import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';
import 'package:karing/app/utils/version_compare_utils.dart';
import 'package:karing/features/moneyfly/moneyfly_models.dart';

void main() {
  group('Moneyfly models', () {
    test('parses active subscription availability', () {
      const universalUrl =
          'https://new.moneyfly.top/api/v1/client/subscribe?token=example-token';
      final subscription = MoneyflySubscription.fromJson({
        'id': '12',
        'status': 'active',
        'is_active': true,
        'device_limit': '3',
        'current_devices': 1,
        'expire_at': '2026-12-31',
        'days_remaining': '30',
        'token_url': universalUrl,
        'token_singbox_url': 'https://example.com/sing-box.json',
        'package_name': 'Pro',
      });

      expect(subscription.id, 12);
      expect(subscription.available, isTrue);
      expect(subscription.subscriptionUrl, universalUrl);
      expect(subscription.singboxUrl, 'https://example.com/sing-box.json');
      expect(subscription.deviceLimit, 3);
      expect(subscription.packageName, 'Pro');
    });

    test('formats known payment method names', () {
      expect(
        MoneyflyPaymentMethod(id: 1, payType: 'codepay_alipay').displayName,
        '支付宝',
      );
      expect(
        MoneyflyPaymentMethod(id: 2, payType: 'unknown_gateway').displayName,
        'unknown_gateway',
      );
    });

    test('uses order amount as fallback final amount', () {
      final order = MoneyflyOrder.fromJson({
        'id': 9,
        'order_no': 'MF20260624001',
        'status': 'pending',
        'amount': '19.9',
      });

      expect(order.finalAmount, 19.9);
      expect(order.orderNo, 'MF20260624001');
    });

    test('shows direct Alipay precreate URL as QR content', () {
      final payment = MoneyflyPayment.fromJson({
        'order_no': 'MF20260624002',
        'transaction_id': 'PAY123',
        'pay_type': 'alipay',
        'payment_url': 'https://qr.alipay.com/bax012345678901234567890',
      });

      expect(payment.paymentUrl, isEmpty);
      expect(payment.qrCode, 'https://qr.alipay.com/bax012345678901234567890');
      expect(payment.hasOpenablePayment, isFalse);
      expect(payment.hasQrContent, isTrue);
    });
  });

  group('VPN service config', () {
    test('drops empty DNS addresses before building core config', () {
      final dns = SettingConfigItemDNS.fromJsonStatic({
        'resolver_addresses': ['', '   '],
        'outbound_addresses': ['', '   '],
        'direct_addresses': ['', '   '],
        'proxy_addresses': ['', '   '],
      });

      final lists = [
        dns.getResolverDns('us', true),
        dns.getOutboundDns('us', true),
        dns.getDirectDns('us', true),
        dns.getProxyDns('us', true),
      ];

      for (final list in lists) {
        expect(list, isNotEmpty);
        expect(list.any((address) => address.trim().isEmpty), isFalse);
      }
    });

    test('migrates legacy inbound fields to route actions', () {
      final setting = SettingManager.getConfig();
      setting.clear();
      setting.novice = false;
      setting.sniff.enable = true;
      setting.dns.enableInboundDomainResolve = true;
      setting.ipStrategy = IPStrategy.preferIPv4;

      final inbounds = SingboxConfigBuilder.inbounds(
        false,
        false,
        [],
        SingboxExportType.karing,
        null,
      );
      final dns = SingboxConfigBuilder.dns(
        false,
        SingboxExportType.karing,
        null,
      );
      final route = SingboxConfigBuilder.route(
        '',
        '',
        '',
        [],
        [],
        [],
        false,
        [],
        {},
        null,
        [],
        inbounds,
        dns,
        {},
        '',
        SingboxExportType.karing,
      );

      for (final inbound in inbounds) {
        expect(_containsKeyDeep(inbound, 'sniff'), isFalse);
        expect(
            _containsKeyDeep(inbound, 'sniff_override_destination'), isFalse);
        expect(_containsKeyDeep(inbound, 'sniff_timeout'), isFalse);
        expect(_containsKeyDeep(inbound, 'domain_strategy'), isFalse);
      }

      expect(
        route.rules,
        contains(
          isA<Map>().having((rule) => rule['action'], 'action', 'sniff').having(
                (rule) => rule['inbound'],
                'inbound',
                containsAll([
                  kInboundTagMixedDirect,
                  kInboundTagMixedProxy,
                  kInboundTagMixedRule,
                ]),
              ),
        ),
      );
      expect(
        route.rules,
        contains(
          isA<Map>()
              .having((rule) => rule['action'], 'action', 'resolve')
              .having((rule) => rule['inbound'], 'inbound', [
            kInboundTagMixedRule
          ]).having((rule) => rule['strategy'], 'strategy', 'prefer_ipv4'),
        ),
      );
    });

    test('repairs legacy inbound fields in existing service config', () {
      final repaired = SingboxConfigSanitizer.sanitizeConfigMap({
        'inbounds': [
          {
            'type': 'mixed',
            'tag': 'legacy_in',
            'sniff': true,
            'sniff_timeout': '1s',
            'sniff_override_destination': true,
            'domain_strategy': 'prefer_ipv4',
          }
        ],
        'route': {
          'final': kOutboundTagDirect,
          'rules': [
            {'inbound': 'legacy_in', 'outbound': kOutboundTagDirect}
          ],
        },
      });

      final inbound = (repaired['inbounds'] as List).single;
      expect(_containsKeyDeep(inbound, 'sniff'), isFalse);
      expect(_containsKeyDeep(inbound, 'sniff_override_destination'), isFalse);
      expect(_containsKeyDeep(inbound, 'sniff_timeout'), isFalse);
      expect(_containsKeyDeep(inbound, 'domain_strategy'), isFalse);

      final rules = (repaired['route'] as Map)['rules'] as List;
      expect(
        rules[0],
        {
          'inbound': 'legacy_in',
          'action': 'resolve',
          'strategy': 'prefer_ipv4',
        },
      );
      expect(
        rules[1],
        {
          'inbound': 'legacy_in',
          'action': 'sniff',
          'timeout': '1s',
        },
      );
    });

    test('final config encoding cannot write legacy inbound fields', () {
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'inbounds': [
          {
            'type': 'mixed',
            'tag': 'mixed_in_rule',
            'sniff': true,
            'sniff_timeout': '2s',
            'sniff_override_destination': true,
            'domain_strategy': 'prefer_ipv4',
          }
        ],
        'route': {'rules': []},
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(_containsKeyDeep(decoded, 'sniff'), isFalse);
      expect(_containsKeyDeep(decoded, 'sniff_override_destination'), isFalse);
      expect(_containsKeyDeep(decoded, 'sniff_timeout'), isFalse);
      expect(_containsKeyDeep(decoded, 'domain_strategy'), isFalse);

      final rules = (decoded['route'] as Map)['rules'] as List;
      expect(
        rules,
        containsAllInOrder([
          {
            'inbound': 'mixed_in_rule',
            'action': 'resolve',
            'strategy': 'prefer_ipv4',
          },
          {
            'inbound': 'mixed_in_rule',
            'action': 'sniff',
            'timeout': '2s',
          },
        ]),
      );
    });

    test('migrates deprecated DNS outbound to route action', () {
      final repaired = SingboxConfigSanitizer.sanitizeConfigMap({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'Proxy',
            'outbounds': ['direct']
          },
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'dns', 'tag': 'dns-out'},
        ],
        'route': {
          'final': 'Proxy',
          'rules': [
            {'protocol': 'dns', 'outbound': 'dns-out'},
            {
              'domain_suffix': ['example.com'],
              'outbound': 'direct'
            },
          ],
        },
      });

      final outbounds = repaired['outbounds'] as List;
      expect(
        outbounds.where((outbound) {
          return outbound is Map && outbound['type'] == kOutboundTypeDns;
        }),
        isEmpty,
      );

      final rules = (repaired['route'] as Map)['rules'] as List;
      expect(rules[0], {'protocol': 'dns', 'action': 'hijack-dns'});
      expect(rules[1], {
        'domain_suffix': ['example.com'],
        'action': 'route',
        'outbound': 'direct',
      });
    });

    test('migrates deprecated block outbound to reject action', () {
      final repaired = SingboxConfigSanitizer.sanitizeConfigMap({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'Proxy',
            'outbounds': ['block-out', 'direct'],
            'default': 'block-out',
          },
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'block', 'tag': 'block-out'},
        ],
        'route': {
          'final': 'Proxy',
          'rules': [
            {
              'domain_suffix': ['ads.example.com'],
              'outbound': 'block-out',
            },
            {
              'domain_suffix': ['example.com'],
              'outbound': 'direct',
            },
          ],
        },
      });

      final outbounds = repaired['outbounds'] as List;
      expect(
        outbounds.where((outbound) {
          return outbound is Map && outbound['type'] == kOutboundTypeBlock;
        }),
        isEmpty,
      );
      expect(
        outbounds,
        contains(
          isA<Map>()
              .having(
                  (outbound) => outbound['type'], 'type', kOutboundTypeSelector)
              .having((outbound) => outbound['outbounds'], 'outbounds', [
            'direct'
          ]).having((outbound) => outbound.containsKey('default'),
                  'default removed', false),
        ),
      );

      final rules = (repaired['route'] as Map)['rules'] as List;
      expect(rules[0], {
        'domain_suffix': ['ads.example.com'],
        'action': 'reject',
      });
      expect(rules[1], {
        'domain_suffix': ['example.com'],
        'action': 'route',
        'outbound': 'direct',
      });
    });

    test('final config encoding cannot write deprecated DNS outbound', () {
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'outbounds': [
          {'type': 'direct', 'tag': kOutboundTagDirect},
          {'type': kOutboundTypeDns, 'tag': kOutboundTagDns},
        ],
        'route': {
          'rules': [
            {'protocol': kOutboundTypeDns, 'outbound': kOutboundTagDns},
          ],
        },
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      final outbounds = decoded['outbounds'] as List;
      expect(
        outbounds.where((outbound) {
          return outbound is Map && outbound['type'] == kOutboundTypeDns;
        }),
        isEmpty,
      );

      final rules = (decoded['route'] as Map)['rules'] as List;
      expect(
        rules,
        contains(
          isA<Map>()
              .having((rule) => rule['protocol'], 'protocol', kOutboundTypeDns)
              .having((rule) => rule['action'], 'action', 'hijack-dns')
              .having(
                  (rule) => rule.containsKey('outbound'), 'outbound', false),
        ),
      );
    });

    test('final config encoding cannot write deprecated block outbound', () {
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'outbounds': [
          {'type': 'direct', 'tag': kOutboundTagDirect},
          {'type': kOutboundTypeBlock, 'tag': kOutboundTagBlock},
        ],
        'route': {
          'rules': [
            {
              'domain_suffix': ['ads.example.com'],
              'outbound': kOutboundTagBlock,
            },
          ],
        },
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      final outbounds = decoded['outbounds'] as List;
      expect(
        outbounds.where((outbound) {
          return outbound is Map && outbound['type'] == kOutboundTypeBlock;
        }),
        isEmpty,
      );

      final rules = (decoded['route'] as Map)['rules'] as List;
      expect(
        rules,
        contains(
          isA<Map>()
              .having((rule) => rule['domain_suffix'], 'domain_suffix',
                  ['ads.example.com'])
              .having((rule) => rule['action'], 'action', 'reject')
              .having(
                  (rule) => rule.containsKey('outbound'), 'outbound', false),
        ),
      );
    });

    test('dns rules use explicit route action', () {
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'dns': {
          'servers': [
            {'tag': kDnsTagDirect, 'address': '223.5.5.5'},
          ],
          'rules': [
            {
              'domain_suffix': ['example.com'],
              'server': kDnsTagDirect,
              'rewrite_ttl': 60,
            },
          ],
        },
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      final rules = (decoded['dns'] as Map<String, dynamic>)['rules'] as List;
      expect(rules.single, {
        'domain_suffix': ['example.com'],
        'server': kDnsTagDirect,
        'rewrite_ttl': 60,
        'action': 'route',
      });
    });

    test('migrates legacy DNS servers to sing-box 1.13 format', () {
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'dns': {
          'servers': [
            {'tag': 'udp', 'address': '223.5.5.5'},
            {
              'tag': 'doh',
              'address': 'https://1.1.1.1/dns-query',
              'address_resolver': 'udp',
              'detour': kOutboundTagDirect,
            },
            {'tag': 'fakeip', 'address': 'fakeip'},
            {'tag': 'blocked', 'address': 'rcode://success'},
          ],
          'rules': [
            {
              'domain_suffix': ['ads.example.com'],
              'server': 'blocked',
              'disable_cache': true,
            },
          ],
          'fakeip': {
            'enabled': true,
            'inet4_range': '198.20.0.0/15',
          },
        },
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final dns = decoded['dns'] as Map<String, dynamic>;
      final servers = dns['servers'] as List;

      expect(dns.containsKey('fakeip'), isFalse);
      expect(
        servers,
        containsAll([
          {'tag': 'udp', 'type': 'udp', 'server': '223.5.5.5'},
          {
            'tag': 'doh',
            'type': 'https',
            'server': '1.1.1.1',
            'path': '/dns-query',
            'domain_resolver': 'udp',
            'detour': kOutboundTagDirect,
          },
          {
            'tag': 'fakeip',
            'type': 'fakeip',
            'inet4_range': '198.20.0.0/15',
          },
        ]),
      );
      expect(
        servers.where((server) {
          return server is Map && server['tag'] == 'blocked';
        }),
        isEmpty,
      );

      final rules = dns['rules'] as List;
      expect(rules.single, {
        'domain_suffix': ['ads.example.com'],
        'action': 'predefined',
        'rcode': 'NOERROR',
      });
    });

    test('adds default domain resolver for outbound server domains', () {
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'dns': {
          'servers': [
            {'tag': kDnsTagDirect, 'address': '223.5.5.5'},
          ],
        },
        'outbounds': [
          {
            'type': 'direct',
            'tag': kOutboundTagDirect,
          },
        ],
        'route': {
          'rules': [],
          'final': kOutboundTagDirect,
        },
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final route = decoded['route'] as Map<String, dynamic>;

      expect(route['default_domain_resolver'], kDnsTagDirect);
    });

    test('default startup config encoding removes legacy special outbounds',
        () {
      final config = SingboxConfig();
      config.log = SingboxConfigBuilder.log('service_core.log');
      config.ntp = SingboxConfigBuilder.ntp();
      config.dns =
          SingboxConfigBuilder.dns(false, SingboxExportType.karing, null);
      config.inbounds = SingboxConfigBuilder.inbounds(
        false,
        false,
        [],
        SingboxExportType.karing,
        null,
      );
      config.outbounds = SingboxConfigBuilder.outbounds(
        false,
        {},
        null,
        null,
        [],
        null,
        {},
        [],
        SingboxExportType.karing,
      );

      final decoded = jsonDecode(SingboxConfigSanitizer.encodeConfig(config))
          as Map<String, dynamic>;
      expect(_containsMapWith(decoded, 'type', kOutboundTypeDns), isFalse);
      expect(_containsMapWith(decoded, 'type', kOutboundTypeBlock), isFalse);
      expect(_containsKeyDeep(decoded, 'sniff'), isFalse);
      expect(_containsKeyDeep(decoded, 'domain_strategy'), isFalse);
    });

    test('sanitized legacy config passes sing-box 1.13.13 check', () async {
      const singBoxPath =
          '/private/tmp/karing-singbox-1.13.13/sing-box-1.13.13-darwin-arm64/sing-box';
      final singBox = File(singBoxPath);
      if (!await singBox.exists()) {
        return;
      }

      final configFile = File('/private/tmp/karing-singbox-compat.json');
      final encoded = SingboxConfigSanitizer.encodeConfig({
        'log': {'disabled': true},
        'dns': {
          'final': kDnsTagDirect,
          'strategy': 'prefer_ipv4',
          'servers': [
            {'tag': kDnsTagDirect, 'address': '223.5.5.5'},
            {'tag': kDnsTagProxy, 'address': 'https://1.1.1.1/dns-query'},
            {'tag': kDnsTagBlock, 'address': 'rcode://success'},
          ],
          'rules': [
            {
              'domain_suffix': ['example.com'],
              'server': kDnsTagDirect,
            },
          ],
        },
        'inbounds': [
          {
            'type': 'mixed',
            'tag': 'mixed_in',
            'listen': '127.0.0.1',
            'listen_port': 2080,
            'sniff': true,
            'sniff_timeout': '1s',
            'domain_strategy': 'prefer_ipv4',
          },
        ],
        'outbounds': [
          {'type': 'direct', 'tag': kOutboundTagDirect},
          {'type': 'dns', 'tag': kOutboundTagDns},
          {'type': 'block', 'tag': kOutboundTagBlock},
          {
            'type': 'selector',
            'tag': 'Proxy',
            'outbounds': [kOutboundTagDirect, kOutboundTagBlock],
            'default': kOutboundTagBlock,
          },
        ],
        'route': {
          'final': 'Proxy',
          'rules': [
            {'protocol': 'dns', 'outbound': kOutboundTagDns},
            {
              'domain_suffix': ['ads.example.com'],
              'outbound': kOutboundTagBlock,
            },
            {
              'domain_suffix': ['example.com'],
              'outbound': kOutboundTagDirect,
            },
          ],
        },
      });
      await configFile.writeAsString(encoded, flush: true);

      final result = await Process.run(
        singBox.path,
        ['check', '-c', configFile.path],
      );
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
    });

    test('generated route uses DNS hijack action', () {
      final setting = SettingManager.getConfig();
      setting.clear();
      setting.novice = false;

      final allOutboundsTags = <String>{};
      final outbounds = SingboxConfigBuilder.outbounds(
        false,
        {},
        null,
        null,
        [],
        null,
        allOutboundsTags,
        [],
        SingboxExportType.karing,
      );
      final dns = SingboxConfigBuilder.dns(
        false,
        SingboxExportType.karing,
        null,
      );
      final route = SingboxConfigBuilder.route(
        '',
        '',
        '',
        [],
        [],
        [],
        false,
        [],
        allOutboundsTags,
        null,
        [],
        [],
        dns,
        {},
        '',
        SingboxExportType.karing,
      );

      expect(
        outbounds.where((outbound) {
          return outbound is Map &&
              (outbound['type'] == kOutboundTypeDns ||
                  outbound['type'] == kOutboundTypeBlock);
        }),
        isEmpty,
      );
      expect(allOutboundsTags.contains(kOutboundTagDns), isFalse);
      expect(
        route.rules,
        contains(
          isA<Map>()
              .having((rule) => rule['protocol'], 'protocol', kOutboundTypeDns)
              .having((rule) => rule['action'], 'action', 'hijack-dns')
              .having(
                  (rule) => rule.containsKey('outbound'), 'outbound', false),
        ),
      );
      expect(
        route.rules.where((rule) {
          return rule is Map &&
              rule['protocol'] == kOutboundTypeDns &&
              rule['outbound'] == kOutboundTagDns;
        }),
        isEmpty,
      );
    });
  });

  group('Version comparison', () {
    test('treats Flutter build suffix as packaging metadata', () {
      expect(VersionCompareUtils.compareVersion('1.0.0', '1.0.0+1'), 0);
      expect(VersionCompareUtils.compareVersion('1.0.0+1', '1.0.0'), 0);
    });

    test('compares uneven version segments numerically', () {
      expect(VersionCompareUtils.compareVersion('1.0.0', '1.0.1'), -1);
      expect(VersionCompareUtils.compareVersion('1.0.0', '1.2.20.2308'), -1);
      expect(VersionCompareUtils.compareVersion('1.2.20.2308', '1.0.0'), 1);
    });
  });

  group('Current server selection', () {
    test('keeps global urltest as valid startup selection', () {
      final current =
          ServerManager.resolveCurrentServer(ServerManager.getUrltest());

      expect(current, isNotNull);
      expect(current!.groupid, ServerManager.getUrltestGroupId());
      expect(current.tag, kOutboundTagUrltest);
    });

    test('rejects stale concrete server selections', () {
      final stale = ProxyConfig()
        ..groupid = 'removed-group'
        ..type = 'vless'
        ..tag = 'removed-server';

      expect(ServerManager.resolveCurrentServer(stale), isNull);
    });
  });
}

bool _containsKeyDeep(Object? value, String key) {
  if (value is Map) {
    if (value.containsKey(key)) {
      return true;
    }
    return value.values.any((item) => _containsKeyDeep(item, key));
  }
  if (value is Iterable) {
    return value.any((item) => _containsKeyDeep(item, key));
  }
  return false;
}

bool _containsMapWith(Object? value, String key, Object? expected) {
  if (value is Map) {
    if (value[key] == expected) {
      return true;
    }
    return value.values.any((item) => _containsMapWith(item, key, expected));
  }
  if (value is Iterable) {
    return value.any((item) => _containsMapWith(item, key, expected));
  }
  return false;
}

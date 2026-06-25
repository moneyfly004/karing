import 'dart:convert';

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

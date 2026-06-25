import 'package:flutter_test/flutter_test.dart';

import 'package:karing/app/modules/setting_manager.dart';
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
  });
}

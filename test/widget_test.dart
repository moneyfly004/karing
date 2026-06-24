import 'package:flutter_test/flutter_test.dart';

import 'package:karing/features/moneyfly/moneyfly_models.dart';

void main() {
  group('Moneyfly models', () {
    test('parses active subscription availability', () {
      final subscription = MoneyflySubscription.fromJson({
        'id': '12',
        'status': 'active',
        'is_active': true,
        'device_limit': '3',
        'current_devices': 1,
        'expire_at': '2026-12-31',
        'days_remaining': '30',
        'token_singbox_url': 'https://example.com/sub.json',
        'package_name': 'Pro',
      });

      expect(subscription.id, 12);
      expect(subscription.available, isTrue);
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
}

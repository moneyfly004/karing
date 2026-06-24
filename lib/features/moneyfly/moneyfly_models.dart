import 'dart:convert';

class MoneyflyUser {
  MoneyflyUser({
    required this.id,
    required this.username,
    required this.email,
    this.balance = 0,
  });

  final int id;
  final String username;
  final String email;
  final double balance;

  factory MoneyflyUser.fromJson(Map<String, dynamic> json) {
    return MoneyflyUser(
      id: _asInt(json['id']),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      balance: _asDouble(json['balance']),
    );
  }
}

class MoneyflySubscription {
  MoneyflySubscription({
    required this.id,
    required this.status,
    required this.isActive,
    required this.deviceLimit,
    required this.currentDevices,
    required this.expireAt,
    required this.daysRemaining,
    required this.subscriptionUrl,
    this.singboxUrl = '',
    this.packageName = '',
  });

  final int id;
  final String status;
  final bool isActive;
  final int deviceLimit;
  final int currentDevices;
  final String expireAt;
  final int daysRemaining;
  final String subscriptionUrl;
  final String singboxUrl;
  final String packageName;

  bool get available =>
      isActive && status == 'active' && subscriptionUrl.isNotEmpty;

  factory MoneyflySubscription.fromJson(Map<String, dynamic> json) {
    final subscriptionUrl = _normalizeSubscriptionUrl(
      (json['token_url'] ?? json['universal_url'] ?? '').toString(),
      (json['subscription_url'] ?? '').toString(),
    );
    return MoneyflySubscription(
      id: _asInt(json['id']),
      status: (json['status'] ?? '').toString(),
      isActive: json['is_active'] == true,
      deviceLimit: _asInt(json['device_limit']),
      currentDevices: _asInt(json['current_devices']),
      expireAt: (json['expire_at'] ?? '').toString(),
      daysRemaining: _asInt(json['days_remaining']),
      subscriptionUrl: subscriptionUrl,
      singboxUrl: (json['token_singbox_url'] ?? '').toString(),
      packageName: (json['package_name'] ?? '').toString(),
    );
  }

  static String _normalizeSubscriptionUrl(String url, String token) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
      return trimmedUrl;
    }
    final rawToken = trimmedUrl.isNotEmpty ? trimmedUrl : token.trim();
    if (rawToken.isEmpty) {
      return '';
    }
    if (rawToken.startsWith('http://') || rawToken.startsWith('https://')) {
      return rawToken;
    }
    return 'https://new.moneyfly.top/api/v1/client/subscribe?token=${Uri.encodeQueryComponent(rawToken)}';
  }
}

class MoneyflyDashboard {
  MoneyflyDashboard({
    this.balance = 0,
    this.deviceCount = 0,
    this.nodeTotal = 0,
    this.nodeOnline = 0,
  });

  final double balance;
  final int deviceCount;
  final int nodeTotal;
  final int nodeOnline;

  factory MoneyflyDashboard.fromJson(Map<String, dynamic> json) {
    return MoneyflyDashboard(
      balance: _asDouble(json['balance']),
      deviceCount: _asInt(json['device_count']),
      nodeTotal: _asInt(json['node_total']),
      nodeOnline: _asInt(json['node_online']),
    );
  }
}

class MoneyflyPackage {
  MoneyflyPackage({
    required this.id,
    required this.name,
    required this.price,
    required this.durationDays,
    required this.deviceLimit,
    this.description = '',
    this.features = '',
    this.isFeatured = false,
  });

  final int id;
  final String name;
  final double price;
  final int durationDays;
  final int deviceLimit;
  final String description;
  final String features;
  final bool isFeatured;

  factory MoneyflyPackage.fromJson(Map<String, dynamic> json) {
    return MoneyflyPackage(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      price: _asDouble(json['price']),
      durationDays: _asInt(json['duration_days']),
      deviceLimit: _asInt(json['device_limit']),
      description: (json['description'] ?? '').toString(),
      features: (json['features'] ?? '').toString(),
      isFeatured: json['is_featured'] == true,
    );
  }
}

class MoneyflyPaymentMethod {
  MoneyflyPaymentMethod({required this.id, required this.payType});

  final int id;
  final String payType;

  String get displayName {
    switch (payType) {
      case 'alipay':
      case 'codepay_alipay':
        return '支付宝';
      case 'wxpay':
      case 'codepay_wxpay':
        return '微信支付';
      case 'stripe':
        return '银行卡';
      case 'crypto':
        return 'USDT';
      case 'epay':
        return '易支付';
      default:
        return payType;
    }
  }

  factory MoneyflyPaymentMethod.fromJson(Map<String, dynamic> json) {
    return MoneyflyPaymentMethod(
      id: _asInt(json['id']),
      payType: _firstString(json, const [
        'pay_type',
        'payType',
        'type',
        'code',
        'name',
      ]),
    );
  }
}

class MoneyflyOrder {
  MoneyflyOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.amount,
    required this.finalAmount,
  });

  final int id;
  final String orderNo;
  final String status;
  final double amount;
  final double finalAmount;

  factory MoneyflyOrder.fromJson(Map<String, dynamic> json) {
    final amount = _asDouble(json['amount']);
    return MoneyflyOrder(
      id: _asInt(json['id']),
      orderNo: (json['order_no'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      amount: amount,
      finalAmount: json['final_amount'] == null
          ? amount
          : _asDouble(json['final_amount']),
    );
  }
}

class MoneyflyPayment {
  MoneyflyPayment({
    required this.orderNo,
    required this.paymentUrl,
    this.qrCode = '',
    this.qrCodeUrl = '',
    this.paymentHtml = '',
    this.paymentMode = '',
    this.payType = '',
    this.transactionId = '',
  });

  final String orderNo;
  final String paymentUrl;
  final String qrCode;
  final String qrCodeUrl;
  final String paymentHtml;
  final String paymentMode;
  final String payType;
  final String transactionId;

  bool get hasQrContent => qrCode.isNotEmpty || qrCodeUrl.isNotEmpty;

  bool get hasPaymentContent =>
      paymentUrl.isNotEmpty || paymentHtml.isNotEmpty || hasQrContent;

  bool get hasOpenablePayment =>
      paymentUrl.isNotEmpty || paymentHtml.isNotEmpty;

  String get scannableContent {
    if (qrCode.isNotEmpty) {
      return qrCode;
    }
    if (qrCodeUrl.isNotEmpty) {
      return qrCodeUrl;
    }
    return paymentUrl;
  }

  factory MoneyflyPayment.fromResponse(dynamic value) {
    if (value is Map) {
      return MoneyflyPayment.fromJson(value.cast<String, dynamic>());
    }
    if (value is List) {
      for (final item in value) {
        final payment = MoneyflyPayment.fromResponse(item);
        if (payment.hasPaymentContent) {
          return payment;
        }
      }
      return MoneyflyPayment(orderNo: '', paymentUrl: '');
    }
    final text = (value ?? '').toString().trim();
    if (text.isEmpty || text == 'null') {
      return MoneyflyPayment(orderNo: '', paymentUrl: '');
    }
    final decoded = _tryDecodeJson(text);
    if (decoded != null) {
      return MoneyflyPayment.fromResponse(decoded);
    }
    if (_looksLikeHtml(text)) {
      return MoneyflyPayment(orderNo: '', paymentUrl: '', paymentHtml: text);
    }
    if (_looksLikeAlipayPreCreateQr(text)) {
      return MoneyflyPayment(orderNo: '', paymentUrl: '', qrCode: text);
    }
    if (_looksLikeUrl(text) || _looksLikePaymentScheme(text)) {
      return MoneyflyPayment(orderNo: '', paymentUrl: text);
    }
    return MoneyflyPayment(orderNo: '', paymentUrl: '', qrCode: text);
  }

  factory MoneyflyPayment.fromJson(Map<String, dynamic> json) {
    final maps = _nestedMaps(json, const [
      'data',
      'payment',
      'pay',
      'order',
      'result',
      'alipay',
      'codepay',
      'params',
      'payload',
    ]);
    final payType = _firstStringInMaps(maps, const [
      'pay_type',
      'payType',
      'payment_type',
      'paymentType',
    ]);
    final paymentMode = _firstStringInMaps(maps, const [
      'payment_mode',
      'paymentMode',
      'mode',
    ]);
    final rawPaymentUrl = _firstStringInMaps(maps, const [
      'payment_url',
      'paymentUrl',
      'pay_url',
      'payUrl',
      'url',
      'checkout_url',
      'checkoutUrl',
      'redirect_url',
      'redirectUrl',
      'gateway_url',
      'gatewayUrl',
      'cashier_url',
      'cashierUrl',
      'pay_link',
      'payLink',
      'payurl',
      'link',
      'jump_url',
      'jumpUrl',
      'redirect',
      'deeplink',
      'deep_link',
      'scheme',
    ]);
    final classified = _classifyBackendPaymentValue(
      rawPaymentUrl,
      payType: payType,
      paymentMode: paymentMode,
    );
    return MoneyflyPayment(
      orderNo: _firstStringInMaps(maps, const [
        'order_no',
        'orderNo',
        'trade_no',
        'tradeNo',
      ]),
      paymentUrl: classified.paymentUrl,
      qrCode: classified.qrCode.isNotEmpty
          ? classified.qrCode
          : _firstQrStringInMaps(maps, const [
              'qr_code',
              'qrCode',
              'qrcode',
              'qr',
              'code_url',
              'codeUrl',
              'pay_info',
              'payInfo',
              'pay_params',
              'payParams',
              'alipay_qr',
              'alipayQr',
              'alipay_qrcode',
              'alipayQrcode',
              'qr_content',
              'qrContent',
              'pay_qrcode',
              'payQrcode',
              'pay_qr_code',
              'payQrCode',
            ]),
      qrCodeUrl: classified.qrCodeUrl.isNotEmpty
          ? classified.qrCodeUrl
          : _firstQrUrlInMaps(maps, const [
              'qr_code_url',
              'qrCodeUrl',
              'qrcode_url',
              'qrcodeUrl',
              'qr_url',
              'qrUrl',
              'pay_qrcode_url',
              'payQrcodeUrl',
              'pay_qr_url',
              'payQrUrl',
              'alipay_qrcode_url',
              'alipayQrcodeUrl',
              'alipay_qr_url',
              'alipayQrUrl',
            ]),
      paymentHtml: classified.paymentHtml.isNotEmpty
          ? classified.paymentHtml
          : _firstHtmlInMaps(maps, const [
              'payment_url',
              'paymentUrl',
              'pay_url',
              'payUrl',
              'url',
              'html',
              'form',
              'form_html',
              'formHtml',
              'pay_form',
              'payForm',
              'payment_form',
              'paymentForm',
              'alipay_form',
              'alipayForm',
              'pay_info',
              'payInfo',
              'pay_params',
              'payParams',
              'content',
              'body',
            ]),
      transactionId: _firstStringInMaps(maps, const [
        'transaction_id',
        'transactionId',
        'payment_id',
        'paymentId',
      ]),
      paymentMode: paymentMode,
      payType: payType,
    );
  }
}

class _PaymentValue {
  const _PaymentValue({
    this.paymentUrl = '',
    this.qrCode = '',
    this.qrCodeUrl = '',
    this.paymentHtml = '',
  });

  final String paymentUrl;
  final String qrCode;
  final String qrCodeUrl;
  final String paymentHtml;
}

_PaymentValue _classifyBackendPaymentValue(
  String value, {
  required String payType,
  required String paymentMode,
}) {
  if (value.isEmpty) {
    return const _PaymentValue();
  }
  if (_looksLikeHtml(value)) {
    return _PaymentValue(paymentHtml: value);
  }

  final mode = paymentMode.toLowerCase();
  if (mode == 'qrcode') {
    if (_looksLikeAlipayPreCreateQr(value)) {
      return _PaymentValue(qrCode: value);
    }
    final imageUrl = _imageLikeUrl(value, allowQrKeyword: true);
    return _PaymentValue(
      qrCode: imageUrl == null ? value : '',
      qrCodeUrl: imageUrl ?? '',
    );
  }
  if (mode == 'redirect' || mode == 'page') {
    return _PaymentValue(paymentUrl: value);
  }

  final lowerPayType = payType.toLowerCase();
  if ((lowerPayType == 'alipay' || lowerPayType == 'codepay_alipay') &&
      _looksLikeAlipayPreCreateQr(value)) {
    return _PaymentValue(qrCode: value);
  }

  if (_looksLikePaymentScheme(value)) {
    return _PaymentValue(paymentUrl: value);
  }

  final imageUrl = _imageLikeUrl(value);
  if (imageUrl != null) {
    return _PaymentValue(qrCodeUrl: imageUrl);
  }

  if (_looksLikeUrl(value)) {
    return _PaymentValue(paymentUrl: value);
  }

  return _PaymentValue(qrCode: value);
}

bool _looksLikeUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.isScheme('http') ||
          uri.isScheme('https') ||
          uri.isScheme('alipays'));
}

bool _looksLikePaymentScheme(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.isEmpty) {
    return false;
  }
  return const {
    'alipay',
    'alipays',
    'weixin',
    'wechat',
    'wxp',
  }.contains(uri.scheme.toLowerCase());
}

bool _looksLikeHtml(String value) {
  final text = value.toLowerCase();
  return text.contains('<form') ||
      text.contains('<html') ||
      text.contains('<body') ||
      text.contains('<script') ||
      text.contains('<!doctype html');
}

bool _looksLikeAlipayPreCreateQr(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  return (host == 'qr.alipay.com' || host.endsWith('.qr.alipay.com')) ||
      (host.contains('alipay') &&
          (path.contains('/qr/') ||
              path.contains('qrcode') ||
              uri.query.toLowerCase().contains('qrcode')));
}

dynamic _tryDecodeJson(String value) {
  if ((!value.startsWith('{') || !value.endsWith('}')) &&
      (!value.startsWith('[') || !value.endsWith(']'))) {
    return null;
  }
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

class MoneyflyDevice {
  MoneyflyDevice({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.osName,
    required this.ipAddress,
    required this.region,
    required this.lastAccess,
    required this.accessCount,
    this.remark = '',
  });

  final String id;
  final String deviceName;
  final String deviceType;
  final String osName;
  final String ipAddress;
  final String region;
  final String lastAccess;
  final int accessCount;
  final String remark;

  factory MoneyflyDevice.fromJson(Map<String, dynamic> json) {
    return MoneyflyDevice(
      id: _firstString(json, const [
        'id',
        'device_id',
        'deviceId',
        'uuid',
        'token',
        'fingerprint',
      ]),
      deviceName: _firstString(json, const [
        'device_name',
        'deviceName',
        'name',
        'hostname',
        'model',
        'device',
      ]),
      deviceType: _firstString(json, const [
        'device_type',
        'deviceType',
        'type',
        'platform',
      ]),
      osName: _firstString(json, const [
        'os_name',
        'osName',
        'os',
        'system',
        'platform_name',
        'platformName',
      ]),
      ipAddress: _firstString(json, const [
        'ip_address',
        'ipAddress',
        'ip',
        'last_ip',
        'lastIp',
      ]),
      region: _firstString(json, const [
        'region',
        'location',
        'country',
        'city',
      ]),
      lastAccess: _firstString(json, const [
        'last_access',
        'lastAccess',
        'last_seen',
        'lastSeen',
        'last_login',
        'lastLogin',
        'updated_at',
        'updatedAt',
        'created_at',
        'createdAt',
      ]),
      accessCount: _asInt(
        json['access_count'] ?? json['accessCount'] ?? json['login_count'],
      ),
      remark: _firstString(json, const [
        'remark',
        'remarks',
        'note',
        'alias',
      ]),
    );
  }
}

String _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty && text != 'null') {
      return text;
    }
  }
  return '';
}

String _firstStringInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    final value = _firstString(map, keys);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _firstHtmlInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    final value = _firstString(map, keys);
    if (value.isNotEmpty && _looksLikeHtml(value)) {
      return value;
    }
  }
  return '';
}

String _firstQrStringInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    final value = _firstString(map, keys);
    if (value.isEmpty || _looksLikeHtml(value)) {
      continue;
    }
    if (_looksLikeAlipayPreCreateQr(value)) {
      return value;
    }
    if (_looksLikeUrl(value) && _imageLikeUrl(value) == null) {
      continue;
    }
    return value;
  }
  return '';
}

String _firstQrUrlInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    final value = _firstString(map, keys);
    if (value.isEmpty || _looksLikeHtml(value)) {
      continue;
    }
    final imageUrl = _imageLikeUrl(value, allowQrKeyword: true);
    if (imageUrl != null) {
      return imageUrl;
    }
  }
  return '';
}

String? _imageLikeUrl(String value, {bool allowQrKeyword = false}) {
  final uri = Uri.tryParse(value);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return null;
  }
  final path = uri.path.toLowerCase();
  if (path.endsWith('.png') ||
      path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.webp') ||
      path.endsWith('.gif')) {
    return value;
  }
  if (allowQrKeyword && !_looksLikeAlipayPreCreateQr(value)) {
    final query = uri.query.toLowerCase();
    if (path.contains('qrcode') ||
        path.contains('qr_code') ||
        path.contains('/qr') ||
        query.contains('qrcode') ||
        query.contains('qr_code') ||
        query.contains('qr=')) {
      return value;
    }
  }
  return null;
}

List<Map<String, dynamic>> _nestedMaps(
  Map<String, dynamic> json,
  List<String> keys,
) {
  final maps = <Map<String, dynamic>>[json];
  final visited = <Map<String, dynamic>>{json};
  var cursor = 0;
  while (cursor < maps.length) {
    final map = maps[cursor];
    cursor += 1;
    for (final key in keys) {
      final value = map[key];
      if (value is Map) {
        final nested = value.cast<String, dynamic>();
        if (visited.add(nested)) {
          maps.add(nested);
        }
      }
    }
  }
  return maps;
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  return int.tryParse((value ?? '').toString()) ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  return double.tryParse((value ?? '').toString()) ?? 0;
}

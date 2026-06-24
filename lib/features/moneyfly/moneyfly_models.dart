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
    required this.singboxUrl,
    this.packageName = '',
  });

  final int id;
  final String status;
  final bool isActive;
  final int deviceLimit;
  final int currentDevices;
  final String expireAt;
  final int daysRemaining;
  final String singboxUrl;
  final String packageName;

  bool get available => isActive && status == 'active' && singboxUrl.isNotEmpty;

  factory MoneyflySubscription.fromJson(Map<String, dynamic> json) {
    return MoneyflySubscription(
      id: _asInt(json['id']),
      status: (json['status'] ?? '').toString(),
      isActive: json['is_active'] == true,
      deviceLimit: _asInt(json['device_limit']),
      currentDevices: _asInt(json['current_devices']),
      expireAt: (json['expire_at'] ?? '').toString(),
      daysRemaining: _asInt(json['days_remaining']),
      singboxUrl: (json['token_singbox_url'] ?? '').toString(),
      packageName: (json['package_name'] ?? '').toString(),
    );
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
      payType: (json['pay_type'] ?? '').toString(),
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
    this.transactionId = '',
  });

  final String orderNo;
  final String paymentUrl;
  final String transactionId;

  factory MoneyflyPayment.fromJson(Map<String, dynamic> json) {
    return MoneyflyPayment(
      orderNo: (json['order_no'] ?? '').toString(),
      paymentUrl: (json['payment_url'] ?? json['url'] ?? '').toString(),
      transactionId: (json['transaction_id'] ?? '').toString(),
    );
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

  final int id;
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
      id: _asInt(json['id']),
      deviceName: (json['device_name'] ?? '').toString(),
      deviceType: (json['device_type'] ?? '').toString(),
      osName: (json['os_name'] ?? '').toString(),
      ipAddress: (json['ip_address'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      lastAccess: (json['last_access'] ?? '').toString(),
      accessCount: _asInt(json['access_count']),
      remark: (json['remark'] ?? '').toString(),
    );
  }
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

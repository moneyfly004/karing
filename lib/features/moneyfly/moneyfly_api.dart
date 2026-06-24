import 'dart:io';

import 'package:dio/dio.dart';
import 'package:karing/app/utils/app_utils.dart';
import 'package:karing/app/utils/platform_utils.dart';
import 'package:karing/features/moneyfly/moneyfly_models.dart';

class MoneyflyApiException implements Exception {
  MoneyflyApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MoneyflyApi {
  MoneyflyApi({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    );
  }

  static const String baseUrl = 'https://new.moneyfly.top/api/v1';

  final Dio _dio;
  String? _accessToken;
  String? _csrfToken;
  String? _deviceId;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  void setDeviceId(String? deviceId) {
    _deviceId = deviceId;
  }

  void clearCsrf() {
    _csrfToken = null;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _request<Map<String, dynamic>>(
      'POST',
      '/auth/login',
      data: {'email': email, 'password': password},
      auth: false,
      csrf: false,
    );
    return data;
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final data = await _request<Map<String, dynamic>>(
      'POST',
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
      auth: false,
      csrf: false,
    );
    return data;
  }

  Future<void> logout(String refreshToken) async {
    await _request<dynamic>(
      'POST',
      '/auth/logout',
      data: {'refresh_token': refreshToken},
      csrf: true,
    );
  }

  Future<void> sendVerificationCode(String email, String purpose) async {
    await _request<dynamic>(
      'POST',
      '/auth/verification/send',
      data: {'email': email, 'purpose': purpose},
      auth: false,
      csrf: false,
    );
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String verificationCode,
    String inviteCode = '',
  }) async {
    return _request<Map<String, dynamic>>(
      'POST',
      '/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        'verification_code': verificationCode,
        if (inviteCode.isNotEmpty) 'invite_code': inviteCode,
      },
      auth: false,
      csrf: false,
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await _request<dynamic>(
      'POST',
      '/auth/forgot-password',
      data: {'email': email},
      auth: false,
      csrf: false,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    await _request<dynamic>(
      'POST',
      '/auth/reset-password',
      data: {'email': email, 'code': code, 'password': password},
      auth: false,
      csrf: false,
    );
  }

  Future<MoneyflyUser> me() async {
    final data = await _request<Map<String, dynamic>>('GET', '/users/me');
    return MoneyflyUser.fromJson(data);
  }

  Future<MoneyflyDashboard> dashboard() async {
    final data = await _request<Map<String, dynamic>>(
      'GET',
      '/users/dashboard-info',
    );
    return MoneyflyDashboard.fromJson(data);
  }

  Future<MoneyflySubscription?> subscription() async {
    final data = await _request<dynamic>(
      'GET',
      '/subscriptions/user-subscription',
    );
    if (data is Map<String, dynamic>) {
      return MoneyflySubscription.fromJson(data);
    }
    return null;
  }

  Future<List<MoneyflyPackage>> packages() async {
    final data = await _request<dynamic>(
      'GET',
      '/packages',
      auth: false,
      csrf: false,
    );
    return _asList(data).map((e) => MoneyflyPackage.fromJson(e)).toList();
  }

  Future<List<MoneyflyPaymentMethod>> paymentMethods() async {
    final data = await _request<dynamic>(
      'GET',
      '/payment/methods',
      auth: false,
      csrf: false,
    );
    return _asList(data).map((e) => MoneyflyPaymentMethod.fromJson(e)).toList();
  }

  Future<MoneyflyOrder> createOrder(int packageId) async {
    final data = await _request<Map<String, dynamic>>(
      'POST',
      '/orders',
      data: {'package_id': packageId},
      csrf: true,
    );
    return MoneyflyOrder.fromJson(data);
  }

  Future<MoneyflyPayment> createPayment({
    required int orderId,
    required int paymentMethodId,
  }) async {
    final data = await _request<dynamic>(
      'POST',
      '/payment',
      data: {
        'order_id': orderId,
        'payment_method_id': paymentMethodId,
        'is_mobile': PlatformUtils.isMobile(),
        'return_url': AppUtils.officialWebsiteUrl,
        'cancel_url': AppUtils.officialWebsiteUrl,
      },
      csrf: true,
    );
    return MoneyflyPayment.fromResponse(data);
  }

  Future<Map<String, dynamic>> orderStatus(String orderNo) async {
    return _request<Map<String, dynamic>>('GET', '/orders/$orderNo/status');
  }

  Future<List<MoneyflyDevice>> devices() async {
    final data = await _request<dynamic>('GET', '/subscriptions/devices');
    return _asList(data).map((e) => MoneyflyDevice.fromJson(e)).toList();
  }

  Future<void> deleteDevice(String id) async {
    final encoded = Uri.encodeComponent(id);
    await _request<dynamic>(
      'DELETE',
      '/subscriptions/devices/$encoded',
      csrf: true,
    );
  }

  Future<void> updateDeviceRemark(String id, String remark) async {
    final encoded = Uri.encodeComponent(id);
    await _request<dynamic>(
      'PUT',
      '/subscriptions/devices/$encoded/remark',
      data: {'remark': remark},
      csrf: true,
    );
  }

  Future<T> _request<T>(
    String method,
    String path, {
    Object? data,
    bool auth = true,
    bool csrf = false,
  }) async {
    try {
      final headers = <String, dynamic>{
        'User-Agent': _userAgent(),
        if (_deviceId != null && _deviceId!.isNotEmpty)
          'X-App-Device-Id': _deviceId,
      };
      if (auth && _accessToken != null && _accessToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_accessToken';
      }
      if (csrf) {
        headers['X-CSRF-Token'] = await _getCsrfToken();
      }
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        options: Options(method: method, headers: headers),
      );
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final code = body['code'];
        final success = body['success'];
        final status = body['status']?.toString().toLowerCase();
        final hasData = body.containsKey('data');
        if (code == null &&
            success == null &&
            !hasData &&
            status != 'success' &&
            status != 'ok' &&
            status != 'error' &&
            status != 'failed') {
          return body as T;
        }
        if (code == 0 ||
            code == '0' ||
            success == true ||
            status == 'success' ||
            status == 'ok') {
          final data = hasData ? body['data'] : body;
          return _castResponse<T>(data);
        }
        if (code == null && success == null && hasData) {
          return _castResponse<T>(body['data']);
        }
        if (code == null && success == null && status != null) {
          return body as T;
        }
        throw MoneyflyApiException(_messageFromMap(body, '请求失败'));
      }
      return body as T;
    } on DioException catch (err) {
      final response = err.response;
      final data = response?.data;
      if (data is Map<String, dynamic>) {
        throw MoneyflyApiException(
          _messageFromMap(data, err.message ?? '网络请求失败'),
          statusCode: response?.statusCode,
        );
      }
      throw MoneyflyApiException(
        err.message ?? '网络请求失败',
        statusCode: response?.statusCode,
      );
    } finally {
      if (csrf) {
        clearCsrf();
      }
    }
  }

  Future<String> _getCsrfToken() async {
    if (_csrfToken != null && _csrfToken!.isNotEmpty) {
      return _csrfToken!;
    }
    final data = await _request<Map<String, dynamic>>(
      'GET',
      '/csrf-token',
      csrf: false,
    );
    _csrfToken = (data['csrf_token'] ?? '').toString();
    return _csrfToken!;
  }

  String _userAgent() {
    final platform = Platform.operatingSystem;
    return 'MoneyFly/${AppUtils.getBuildinVersion()} ($platform)';
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      var sawListKey = false;
      for (final key in const [
        'devices',
        'methods',
        'packages',
        'orders',
        'list',
        'items',
        'records',
        'rows',
        'data',
        'result',
      ]) {
        final nested = map[key];
        if (nested == null || identical(nested, value)) {
          continue;
        }
        if (nested is List) {
          sawListKey = true;
        }
        final list = _asList(nested);
        if (list.isNotEmpty) {
          return list;
        }
      }
      if (sawListKey) {
        return [];
      }
      if (map.isNotEmpty) {
        return [map];
      }
    }
    return [];
  }

  String _messageFromMap(Map<String, dynamic> data, String fallback) {
    for (final key in const ['message', 'msg', 'error', 'detail', 'reason']) {
      final value = data[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return fallback;
  }

  T _castResponse<T>(dynamic data) {
    if (data == null && T == dynamic) {
      return data as T;
    }
    if (data == null) {
      return <String, dynamic>{} as T;
    }
    return data as T;
  }
}

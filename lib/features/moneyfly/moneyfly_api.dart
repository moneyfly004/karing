import 'dart:io';

import 'package:dio/dio.dart';
import 'package:karing/app/utils/app_utils.dart';
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
    final data = await _request<Map<String, dynamic>>(
      'GET',
      '/payment/methods',
      auth: false,
      csrf: false,
    );
    return _asList(
      data['methods'],
    ).map((e) => MoneyflyPaymentMethod.fromJson(e)).toList();
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
    final data = await _request<Map<String, dynamic>>(
      'POST',
      '/payment',
      data: {
        'order_id': orderId,
        'payment_method_id': paymentMethodId,
        'is_mobile': Platform.isAndroid || Platform.isIOS,
      },
      csrf: true,
    );
    return MoneyflyPayment.fromJson(data);
  }

  Future<Map<String, dynamic>> orderStatus(String orderNo) async {
    return _request<Map<String, dynamic>>('GET', '/orders/$orderNo/status');
  }

  Future<List<MoneyflyDevice>> devices() async {
    final data = await _request<dynamic>('GET', '/subscriptions/devices');
    return _asList(data).map((e) => MoneyflyDevice.fromJson(e)).toList();
  }

  Future<void> deleteDevice(int id) async {
    await _request<dynamic>('DELETE', '/subscriptions/devices/$id', csrf: true);
  }

  Future<void> updateDeviceRemark(int id, String remark) async {
    await _request<dynamic>(
      'PUT',
      '/subscriptions/devices/$id/remark',
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
        if (code == 0) {
          return body['data'] as T;
        }
        throw MoneyflyApiException((body['message'] ?? '请求失败').toString());
      }
      return body as T;
    } on DioException catch (err) {
      final response = err.response;
      final data = response?.data;
      if (data is Map<String, dynamic>) {
        throw MoneyflyApiException(
          (data['message'] ?? err.message ?? '网络请求失败').toString(),
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
    return [];
  }
}

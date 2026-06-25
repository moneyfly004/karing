import 'package:flutter/foundation.dart';
import 'package:karing/app/modules/server_manager.dart';
import 'package:karing/app/local_services/vpn_service.dart';
import 'package:karing/app/utils/auto_conf_utils.dart';
import 'package:karing/app/utils/proxy_conf_utils.dart';
import 'package:karing/features/moneyfly/moneyfly_api.dart';
import 'package:karing/features/moneyfly/moneyfly_models.dart';
import 'package:karing/features/moneyfly/moneyfly_secure_store.dart';

enum MoneyflySessionState { checking, signedOut, signedIn }

class MoneyflyAccountController extends ChangeNotifier {
  MoneyflyAccountController({MoneyflyApi? api, MoneyflySecureStore? store})
      : _api = api ?? MoneyflyApi(),
        _store = store ?? MoneyflySecureStore();

  static const managedRemark = 'MoneyFly';

  final MoneyflyApi _api;
  final MoneyflySecureStore _store;

  MoneyflySessionState state = MoneyflySessionState.checking;
  MoneyflyUser? user;
  MoneyflySubscription? subscription;
  MoneyflyDashboard? dashboard;
  String? lastEmail;
  String? errorMessage;
  bool syncing = false;

  bool get signedIn => state == MoneyflySessionState.signedIn;

  Future<void> init() async {
    state = MoneyflySessionState.checking;
    notifyListeners();

    final deviceId = await _store.readDeviceId();
    _api.setDeviceId(deviceId);
    lastEmail = await _store.readEmail();

    final accessToken = await _store.readAccessToken();
    final refreshToken = await _store.readRefreshToken();
    if (accessToken == null || refreshToken == null) {
      state = MoneyflySessionState.signedOut;
      notifyListeners();
      return;
    }

    _api.setAccessToken(accessToken);
    try {
      await refreshSession(refreshToken);
      await refreshAccount(syncConfig: true);
      state = MoneyflySessionState.signedIn;
    } catch (err) {
      await _clearLocalSession(removeManagedConfig: true);
      errorMessage = _messageFrom(err);
      state = MoneyflySessionState.signedOut;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    errorMessage = null;
    notifyListeners();
    final data = await _api.login(email, password);
    await _saveSession(data, email);
    await refreshAccount(syncConfig: true);
    state = MoneyflySessionState.signedIn;
    notifyListeners();
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String verificationCode,
    String inviteCode = '',
  }) async {
    errorMessage = null;
    notifyListeners();
    final data = await _api.register(
      username: username,
      email: email,
      password: password,
      verificationCode: verificationCode,
      inviteCode: inviteCode,
    );
    await _saveSession(data, email);
    await refreshAccount(syncConfig: true);
    state = MoneyflySessionState.signedIn;
    notifyListeners();
  }

  Future<void> refreshSession(String refreshToken) async {
    final data = await _api.refresh(refreshToken);
    final accessToken = (data['access_token'] ?? '').toString();
    final nextRefreshToken = (data['refresh_token'] ?? '').toString();
    if (accessToken.isEmpty || nextRefreshToken.isEmpty) {
      throw MoneyflyApiException('登录状态已过期');
    }
    final email = lastEmail ?? '';
    await _store.saveSession(
      accessToken: accessToken,
      refreshToken: nextRefreshToken,
      email: email,
    );
    _api.setAccessToken(accessToken);
    _api.clearCsrf();
  }

  Future<void> refreshAccount({bool syncConfig = false}) async {
    syncing = syncConfig;
    errorMessage = null;
    notifyListeners();
    try {
      user = await _api.me();
      dashboard = await _api.dashboard();
      try {
        subscription = await _api.subscription();
      } on MoneyflyApiException catch (err) {
        if (err.statusCode == 404 && err.message.contains('暂无订阅')) {
          subscription = null;
        } else {
          rethrow;
        }
      }
      if (syncConfig) {
        await syncManagedConfig();
      }
    } catch (err) {
      errorMessage = _messageFrom(err);
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> sendRegisterCode(String email) {
    return _api.sendVerificationCode(email, 'register');
  }

  Future<void> sendResetCode(String email) {
    return _api.requestPasswordReset(email);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) {
    return _api.resetPassword(email: email, code: code, password: password);
  }

  Future<List<MoneyflyPackage>> loadPackages() {
    return _api.packages();
  }

  Future<List<MoneyflyPaymentMethod>> loadPaymentMethods() {
    return _api.paymentMethods();
  }

  Future<MoneyflyOrder> createOrder(int packageId) {
    return _api.createOrder(packageId);
  }

  Future<MoneyflyPayment> createPayment({
    required int orderId,
    required int paymentMethodId,
  }) {
    return _api.createPayment(
      orderId: orderId,
      paymentMethodId: paymentMethodId,
    );
  }

  Future<Map<String, dynamic>> orderStatus(String orderNo) {
    return _api.orderStatus(orderNo);
  }

  Future<List<MoneyflyDevice>> loadDevices() {
    return _api.devices();
  }

  Future<void> deleteDevice(String id) async {
    await _api.deleteDevice(id);
    await refreshAccount(syncConfig: true);
  }

  Future<void> updateDeviceRemark(String id, String remark) {
    return _api.updateDeviceRemark(id, remark);
  }

  Future<void> syncManagedConfig() async {
    final sub = subscription;
    final storedGroupId = await _store.readManagedGroupId();
    if (sub == null || sub.subscriptionUrl.isEmpty) {
      if (storedGroupId != null && storedGroupId.isNotEmpty) {
        await ServerManager.removeGroup(storedGroupId, true);
      }
      return;
    }

    final managedUrl = await _managedSubscriptionUrl(sub.subscriptionUrl);
    final error = await ServerManager.addRemoteConfig(
      storedGroupId ?? '',
      managedRemark,
      managedUrl,
      SubscriptionLinkType.unknown,
      '',
      ProxyFilter(),
      const [],
      false,
      false,
      true,
      ProxyStrategy.preferProxy,
      const Duration(hours: 12),
    );
    if (error != null) {
      throw MoneyflyApiException(error.message);
    }

    final group = ServerManager.getGroupByUrlOrPath(managedUrl) ??
        (storedGroupId == null
            ? null
            : ServerManager.getByGroupId(storedGroupId));
    if (group != null) {
      group.enable = true;
      group.editAble = false;
      await _store.saveManagedGroupId(group.groupid);
      ServerManager.getUse().selectDefault = '';
      ServerManager.addRecent(ServerManager.getUrltest());
      ServerManager.setDirty(true);
      await ServerManager.saveUse();
      await ServerManager.saveServerConfig();
    }
  }

  Future<void> logout() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {}
    }
    await _clearLocalSession(removeManagedConfig: true);
    state = MoneyflySessionState.signedOut;
    notifyListeners();
  }

  Future<String> _managedSubscriptionUrl(String url) async {
    final deviceId = await _store.readDeviceId();
    if (deviceId.isEmpty) {
      return url;
    }
    try {
      final uri = Uri.parse(url);
      final query = Map<String, String>.from(uri.queryParameters);
      query['app_device_id'] = deviceId;
      return uri.replace(queryParameters: query).toString();
    } catch (_) {
      return url;
    }
  }

  Future<void> _saveSession(
    Map<String, dynamic> data,
    String fallbackEmail,
  ) async {
    final accessToken = (data['access_token'] ?? '').toString();
    final refreshToken = (data['refresh_token'] ?? '').toString();
    final userJson = data['user'];
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw MoneyflyApiException('登录返回缺少 token');
    }
    if (userJson is Map<String, dynamic>) {
      user = MoneyflyUser.fromJson(userJson);
    }
    lastEmail = user?.email.isNotEmpty == true ? user!.email : fallbackEmail;
    await _store.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      email: lastEmail ?? fallbackEmail,
    );
    _api.setAccessToken(accessToken);
    _api.clearCsrf();
  }

  Future<void> _clearLocalSession({required bool removeManagedConfig}) async {
    if (removeManagedConfig) {
      try {
        await VPNService.stop();
      } catch (_) {}
      final groupId = await _store.readManagedGroupId();
      if (groupId != null && groupId.isNotEmpty) {
        await ServerManager.removeGroup(groupId, true);
      }
    }
    await _store.clearSession();
    _api.setAccessToken(null);
    _api.clearCsrf();
    user = null;
    subscription = null;
    dashboard = null;
  }

  String _messageFrom(Object err) {
    if (err is MoneyflyApiException) {
      return err.message;
    }
    return err.toString();
  }
}

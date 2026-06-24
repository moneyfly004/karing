import 'package:flutter/material.dart';
import 'package:karing/features/moneyfly/moneyfly_account_controller.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:provider/provider.dart';

enum _AuthMode { login, register, forgot }

class MoneyflyAuthScreen extends StatefulWidget {
  const MoneyflyAuthScreen({super.key});

  @override
  State<MoneyflyAuthScreen> createState() => _MoneyflyAuthScreenState();
}

class _MoneyflyAuthScreenState extends State<MoneyflyAuthScreen> {
  _AuthMode _mode = _AuthMode.login;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _codeController = TextEditingController();
  final _inviteController = TextEditingController();
  bool _obscure = true;
  bool _working = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _codeController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<MoneyflyAccountController>();
    if (_emailController.text.isEmpty && account.lastEmail != null) {
      _emailController.text = account.lastEmail!;
    }

    return Scaffold(
      backgroundColor: const Color(0xfffbfcfd),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _mode == _AuthMode.login
                    ? _loginView(account)
                    : _secondaryView(account),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData get _primaryIcon {
    switch (_mode) {
      case _AuthMode.login:
        return Icons.login_rounded;
      case _AuthMode.register:
        return Icons.person_add_alt_rounded;
      case _AuthMode.forgot:
        return Icons.check_rounded;
    }
  }

  String get _primaryText {
    switch (_mode) {
      case _AuthMode.login:
        return '登录';
      case _AuthMode.register:
        return '注册并登录';
      case _AuthMode.forgot:
        return '重置密码';
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xfff1f5f8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _loginView(MoneyflyAccountController account) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 34),
        Center(child: _brandMark(68)),
        const SizedBox(height: 28),
        const Text(
          'MoneyFly',
          style: TextStyle(
            color: Color(0xff121820),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '登录后自动同步订阅与安全配置',
          style: TextStyle(color: Color(0xff657282), fontSize: 15),
        ),
        const SizedBox(height: 34),
        _field(
          controller: _emailController,
          label: '邮箱 / 用户名',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        _passwordField(label: '密码'),
        const SizedBox(height: 24),
        _primaryButton(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _working
                  ? null
                  : () => setState(() => _mode = _AuthMode.register),
              child: const Text('注册账号'),
            ),
            const SizedBox(width: 36),
            TextButton(
              onPressed: _working
                  ? null
                  : () => setState(() => _mode = _AuthMode.forgot),
              child: const Text('忘记密码'),
            ),
          ],
        ),
        const SizedBox(height: 54),
        _infoPanel(
          color: const Color(0xffeef7f2),
          borderColor: const Color(0xffc9ead9),
          icon: Icons.verified_user_outlined,
          title: '自动登录',
          lines: const ['打开软件自动登录并同步配置。', '退出账号后删除本机配置和登录状态。'],
        ),
        if (account.errorMessage != null) _errorText(account.errorMessage!),
      ],
    );
  }

  Widget _secondaryView(MoneyflyAccountController account) {
    final register = _mode == _AuthMode.register;
    return Column(
      key: ValueKey(_mode),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回登录',
              onPressed: _working
                  ? null
                  : () => setState(() => _mode = _AuthMode.login),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            const SizedBox(width: 4),
            Text(
              register ? '创建账号' : '重置密码',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (register)
          const Text(
            '邮箱验证码必填，邀请码可选。',
            style: TextStyle(color: Color(0xff657282), fontSize: 15),
          )
        else
          _infoPanel(
            color: const Color(0xffeef4ff),
            borderColor: const Color(0xffc9dcff),
            icon: Icons.mark_email_read_outlined,
            title: '邮箱验证',
            lines: const ['输入注册邮箱，获取一次性验证码后设置新密码。', '验证码过期后需要重新发送。'],
          ),
        const SizedBox(height: 24),
        if (register) ...[
          _field(
            controller: _usernameController,
            label: '用户名',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
        ],
        _field(
          controller: _emailController,
          label: '邮箱',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                controller: _codeController,
                label: '邮箱验证码',
                icon: Icons.verified_outlined,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff1d2733),
                  shape: const StadiumBorder(),
                ),
                onPressed: _working ? null : _sendCode,
                child: const Text('发送'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _passwordField(label: register ? '密码' : '新密码'),
        if (register) ...[
          const SizedBox(height: 12),
          _field(
            controller: _inviteController,
            label: '邀请码（选填）',
            icon: Icons.card_giftcard_rounded,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
        const SizedBox(height: 28),
        _primaryButton(),
        const SizedBox(height: 18),
        TextButton(
          onPressed:
              _working ? null : () => setState(() => _mode = _AuthMode.login),
          child: const Text('返回登录'),
        ),
        if (register) ...[
          const SizedBox(height: 34),
          _infoPanel(
            color: const Color(0xfffff7e8),
            borderColor: const Color(0xffefd6a9),
            icon: Icons.pin_outlined,
            title: '验证码流程',
            lines: const ['验证码发送到邮箱后，请在有效期内完成注册。'],
          ),
        ],
        if (account.errorMessage != null) _errorText(account.errorMessage!),
      ],
    );
  }

  Widget _passwordField({required String label}) {
    return _field(
      controller: _passwordController,
      label: label,
      icon: Icons.lock_outline_rounded,
      obscureText: _obscure,
      suffix: IconButton(
        tooltip: _obscure ? '显示密码' : '隐藏密码',
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _primaryButton() {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: const Color(0xff1769d4),
        shape: const StadiumBorder(),
      ),
      onPressed: _working ? null : _submit,
      icon: _working
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(_primaryIcon),
      label: Text(
        _primaryText,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _brandMark(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xff1769d4),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.flight_takeoff_rounded, color: Colors.white),
    );
  }

  Widget _infoPanel({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required String title,
    required List<String> lines,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xff1769d4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff121820),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xff657282),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        text,
        style: const TextStyle(color: Colors.red),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      await DialogUtils.showAlertDialog(context, '请输入邮箱');
      return;
    }
    setState(() => _working = true);
    try {
      final account = context.read<MoneyflyAccountController>();
      if (_mode == _AuthMode.register) {
        await account.sendRegisterCode(email);
      } else {
        await account.sendResetCode(email);
      }
      if (mounted) {
        await DialogUtils.showAlertDialog(context, '验证码已发送');
      }
    } catch (err) {
      if (mounted) {
        await DialogUtils.showAlertDialog(context, err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      await DialogUtils.showAlertDialog(context, '请输入邮箱和密码');
      return;
    }

    setState(() => _working = true);
    try {
      final account = context.read<MoneyflyAccountController>();
      switch (_mode) {
        case _AuthMode.login:
          await account.login(email, password);
          break;
        case _AuthMode.register:
          final username = _usernameController.text.trim();
          final code = _codeController.text.trim();
          if (username.isEmpty || code.isEmpty) {
            throw Exception('请输入用户名和邮箱验证码');
          }
          await account.register(
            username: username,
            email: email,
            password: password,
            verificationCode: code,
            inviteCode: _inviteController.text.trim(),
          );
          break;
        case _AuthMode.forgot:
          final code = _codeController.text.trim();
          if (code.isEmpty) {
            throw Exception('请输入邮箱验证码');
          }
          await account.resetPassword(
            email: email,
            code: code,
            password: password,
          );
          if (mounted) {
            await DialogUtils.showAlertDialog(context, '密码已重置，请重新登录');
            setState(() => _mode = _AuthMode.login);
          }
          break;
      }
    } catch (err) {
      if (mounted) {
        await DialogUtils.showAlertDialog(
          context,
          err.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }
}

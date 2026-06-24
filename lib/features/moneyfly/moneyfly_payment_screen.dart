import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:karing/app/utils/qrcode_utils.dart';
import 'package:karing/features/moneyfly/moneyfly_account_controller.dart';
import 'package:karing/features/moneyfly/moneyfly_models.dart';
import 'package:karing/features/moneyfly/moneyfly_theme.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/webview_helper.dart';
import 'package:provider/provider.dart';

class MoneyflyPaymentScreen extends StatefulWidget {
  const MoneyflyPaymentScreen({
    super.key,
    required this.order,
    required this.payment,
    this.paymentMethodName = '',
    this.packageName = '',
  });

  final MoneyflyOrder order;
  final MoneyflyPayment payment;
  final String paymentMethodName;
  final String packageName;

  @override
  State<MoneyflyPaymentScreen> createState() => _MoneyflyPaymentScreenState();
}

class _MoneyflyPaymentScreenState extends State<MoneyflyPaymentScreen> {
  Timer? _timer;
  String _status = 'pending';
  bool _opened = false;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _status = widget.order.status.isEmpty ? 'pending' : widget.order.status;
    if (widget.payment.paymentUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPayment());
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _successStatus
        ? MoneyflyColors.green
        : _terminalStatus
            ? MoneyflyColors.red
            : MoneyflyColors.amber;

    return MoneyflyPage(
      title: '订单支付',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          MoneyflyPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.order.orderNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MoneyflyColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (widget.packageName.isNotEmpty)
                                widget.packageName,
                              '¥${widget.order.finalAmount.toStringAsFixed(2)}',
                              if (widget.paymentMethodName.isNotEmpty)
                                widget.paymentMethodName,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: MoneyflyColors.muted),
                          ),
                        ],
                      ),
                    ),
                    MoneyflyStatusPill(
                      label: _statusLabel,
                      color: statusColor,
                      icon: _successStatus
                          ? Icons.check_circle_outline_rounded
                          : Icons.schedule_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          MoneyflyPanel(
            child: Column(
              children: [
                Container(
                  width: 226,
                  height: 226,
                  decoration: BoxDecoration(
                    color: MoneyflyColors.soft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MoneyflyColors.line),
                  ),
                  child: Center(
                    child: _paymentQrCode(),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _successStatus ? '支付已完成' : '请完成支付',
                  style: const TextStyle(
                    color: MoneyflyColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _terminalStatus ? '订单已结束，可返回重新创建订单。' : 'App 正在自动轮询订单状态。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: MoneyflyColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: moneyflyPrimaryButtonStyle(),
            onPressed: widget.payment.paymentUrl.isEmpty
                ? (_polling ? null : _poll)
                : (_opened ? _poll : _openPayment),
            icon: _polling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(widget.payment.paymentUrl.isEmpty || _opened
                    ? Icons.refresh_rounded
                    : Icons.payment_rounded),
            label: Text(widget.payment.paymentUrl.isEmpty || _opened
                ? '刷新支付状态'
                : '打开支付页面'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: MoneyflyColors.blue,
              side: const BorderSide(color: Color(0xffc9dcff)),
              shape: const StadiumBorder(),
            ),
            onPressed: _polling ? null : _poll,
            icon: const Icon(Icons.done_all_rounded),
            label: const Text('我已完成支付'),
          ),
          const SizedBox(height: 18),
          const MoneyflyPanel(
            color: MoneyflyColors.soft,
            borderColor: Color(0xffe2e7ed),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '支付说明',
                  style: TextStyle(
                    color: MoneyflyColors.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '支付成功后自动刷新套餐与配置。失败或取消不会修改当前订阅。',
                  style: TextStyle(color: MoneyflyColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _successStatus {
    return _status == 'paid' || _status == 'success' || _status == 'completed';
  }

  bool get _terminalStatus {
    return _successStatus || _status == 'cancelled' || _status == 'expired';
  }

  String get _statusLabel {
    switch (_status) {
      case 'paid':
      case 'success':
      case 'completed':
        return '已支付';
      case 'cancelled':
        return '已取消';
      case 'expired':
        return '已过期';
      case 'pending':
      default:
        return '待支付';
    }
  }

  Widget _paymentQrCode() {
    final content = widget.payment.scannableContent;
    final imageUrl = _imageUrl;
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          imageUrl,
          width: 184,
          height: 184,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _generatedQr(content),
        ),
      );
    }
    final dataImage = _dataImageBytes(content);
    if (dataImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          dataImage,
          width: 184,
          height: 184,
          fit: BoxFit.contain,
        ),
      );
    }
    return _generatedQr(content);
  }

  Widget _generatedQr(String content) {
    if (content.isEmpty) {
      return const Icon(
        Icons.qr_code_2_rounded,
        color: MoneyflyColors.ink,
        size: 112,
      );
    }
    final result = QrcodeUtils.toImage(content);
    final image = result.data;
    if (image == null) {
      return const Icon(
        Icons.qr_code_2_rounded,
        color: MoneyflyColors.ink,
        size: 112,
      );
    }
    return Container(
      width: 184,
      height: 184,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MoneyflyColors.line),
      ),
      child: FittedBox(child: image),
    );
  }

  String? get _imageUrl {
    for (final value in [widget.payment.qrCodeUrl, widget.payment.qrCode]) {
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
        final path = uri.path.toLowerCase();
        if (path.endsWith('.png') ||
            path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.webp') ||
            path.endsWith('.gif') ||
            value.contains('qr')) {
          return value;
        }
      }
    }
    return null;
  }

  Uint8List? _dataImageBytes(String content) {
    final marker = 'base64,';
    if (!content.toLowerCase().startsWith('data:image/') ||
        !content.toLowerCase().contains(marker)) {
      return null;
    }
    try {
      final index = content.toLowerCase().indexOf(marker);
      return base64Decode(content.substring(index + marker.length));
    } catch (_) {
      return null;
    }
  }

  Future<void> _openPayment() async {
    if (_opened || widget.payment.paymentUrl.isEmpty) {
      return;
    }
    _opened = true;
    await WebviewHelper.loadUrl(
      context,
      widget.payment.paymentUrl,
      'moneyfly_payment',
      title: '支付订单',
      useInappWebViewForPC: true,
      inappWebViewOpenExternal: true,
    );
    await _poll();
  }

  Future<void> _poll() async {
    if (_polling) {
      return;
    }
    setState(() => _polling = true);
    try {
      final account = context.read<MoneyflyAccountController>();
      final status = await account.orderStatus(widget.order.orderNo);
      final next = (status['status'] ?? '').toString();
      if (!mounted) {
        return;
      }
      if (next.isNotEmpty) {
        setState(() => _status = next);
      }
      if (_successStatus) {
        _timer?.cancel();
        await account.refreshAccount(syncConfig: true);
        if (!mounted) {
          return;
        }
        await DialogUtils.showAlertDialog(context, '支付成功，套餐已同步');
        if (!mounted) {
          return;
        }
        Navigator.pop(context, true);
      } else if (_status == 'cancelled' || _status == 'expired') {
        _timer?.cancel();
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _polling = false);
      }
    }
  }
}

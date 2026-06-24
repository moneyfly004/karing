import 'package:flutter/material.dart';
import 'package:karing/features/moneyfly/moneyfly_account_controller.dart';
import 'package:karing/features/moneyfly/moneyfly_models.dart';
import 'package:karing/features/moneyfly/moneyfly_payment_screen.dart';
import 'package:karing/features/moneyfly/moneyfly_theme.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:provider/provider.dart';

class MoneyflyPurchaseScreen extends StatefulWidget {
  const MoneyflyPurchaseScreen({super.key});

  @override
  State<MoneyflyPurchaseScreen> createState() => _MoneyflyPurchaseScreenState();
}

class _MoneyflyPurchaseScreenState extends State<MoneyflyPurchaseScreen> {
  late Future<List<MoneyflyPackage>> _packagesFuture;
  List<MoneyflyPaymentMethod> _methods = [];
  MoneyflyPaymentMethod? _selectedMethod;
  MoneyflyPackage? _selectedPackage;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final account = context.read<MoneyflyAccountController>();
    _packagesFuture = account.loadPackages();
    account.loadPaymentMethods().then((methods) {
      if (!mounted) {
        return;
      }
      setState(() {
        _methods = methods;
        _selectedMethod = methods.isNotEmpty ? methods.first : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<MoneyflyAccountController>();
    final sub = account.subscription;

    return MoneyflyPage(
      title: '套餐购买',
      child: FutureBuilder<List<MoneyflyPackage>>(
        future: _packagesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final packages = snapshot.data!;
          if (packages.isEmpty) {
            return const MoneyflyEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: '暂无可购买套餐',
              message: '套餐上架后会显示在这里。',
            );
          }

          final selected = _selectedPackage ?? _defaultPackage(packages);
          if (_selectedPackage == null && selected != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedPackage == null) {
                setState(() => _selectedPackage = selected);
              }
            });
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              _currentPlanPanel(sub),
              const SizedBox(height: 18),
              MoneyflySectionTitle(
                '选择套餐',
                trailing: selected == null
                    ? null
                    : Text(
                        '¥${selected.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: MoneyflyColors.blue,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              for (final item in packages) ...[
                _packageCard(item, selected?.id == item.id),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 6),
              _paymentMethods(),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: moneyflyPrimaryButtonStyle(),
                onPressed:
                    _working || selected == null ? null : () => _buy(selected),
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: const Text('创建订单并支付'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _currentPlanPanel(MoneyflySubscription? sub) {
    return MoneyflyPanel(
      color: MoneyflyColors.soft,
      borderColor: const Color(0xffe2e7ed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当前套餐',
            style: TextStyle(color: MoneyflyColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            sub?.packageName.isNotEmpty == true
                ? sub!.packageName
                : sub?.status ?? '未开通',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MoneyflyColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MoneyflyStatusPill(
                label: sub == null
                    ? '需要购买'
                    : sub.available
                        ? '可用'
                        : '需处理',
                color: sub?.available == true
                    ? MoneyflyColors.green
                    : MoneyflyColors.amber,
                icon: Icons.verified_outlined,
              ),
              MoneyflyStatusPill(
                label: sub?.expireAt.isNotEmpty == true
                    ? '到期 ${sub!.expireAt}'
                    : '暂无到期时间',
                color: MoneyflyColors.blue,
                icon: Icons.event_available_outlined,
              ),
              MoneyflyStatusPill(
                label: sub == null
                    ? '设备 --'
                    : '设备 ${sub.currentDevices}/${sub.deviceLimit}',
                color: MoneyflyColors.green,
                icon: Icons.devices_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  MoneyflyPackage? _defaultPackage(List<MoneyflyPackage> packages) {
    if (packages.isEmpty) {
      return null;
    }
    for (final item in packages) {
      if (item.isFeatured) {
        return item;
      }
    }
    return packages.first;
  }

  Widget _packageCard(MoneyflyPackage item, bool selected) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _working ? null : () => setState(() => _selectedPackage = item),
      child: MoneyflyPanel(
        borderColor: selected ? MoneyflyColors.blue : MoneyflyColors.line,
        color: selected ? const Color(0xfff2f7ff) : Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MoneyflyColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (item.isFeatured)
                  const MoneyflyStatusPill(
                    label: '推荐',
                    color: MoneyflyColors.green,
                    icon: Icons.star_border_rounded,
                  )
                else if (selected)
                  const MoneyflyStatusPill(
                    label: '已选',
                    color: MoneyflyColors.blue,
                    icon: Icons.check_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '¥${item.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: MoneyflyColors.blue,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '/ ${item.durationDays} 天',
                    style: const TextStyle(color: MoneyflyColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MoneyflyStatusPill(
                  label: '${item.deviceLimit} 台设备',
                  color: MoneyflyColors.blue,
                  icon: Icons.devices_rounded,
                ),
                MoneyflyStatusPill(
                  label: '${item.durationDays} 天',
                  color: MoneyflyColors.green,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
            if (item.description.isNotEmpty || item.features.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                item.description.isNotEmpty ? item.description : item.features,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MoneyflyColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentMethods() {
    return MoneyflyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MoneyflySectionTitle('支付方式'),
          const SizedBox(height: 12),
          if (_methods.isEmpty)
            const Text(
              '暂无可用支付方式',
              style: TextStyle(color: MoneyflyColors.muted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in _methods)
                  ChoiceChip(
                    label: Text(method.displayName),
                    selected: _selectedMethod?.id == method.id,
                    avatar: Icon(_paymentIcon(method), size: 18),
                    selectedColor: const Color(0xffe7f6ed),
                    backgroundColor: MoneyflyColors.soft,
                    side: BorderSide(
                      color: _selectedMethod?.id == method.id
                          ? MoneyflyColors.green
                          : const Color(0xffe2e7ed),
                    ),
                    labelStyle: TextStyle(
                      color: _selectedMethod?.id == method.id
                          ? MoneyflyColors.green
                          : MoneyflyColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: _working
                        ? null
                        : (_) => setState(() => _selectedMethod = method),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _paymentIcon(MoneyflyPaymentMethod method) {
    switch (method.payType) {
      case 'alipay':
      case 'codepay_alipay':
        return Icons.account_balance_wallet_outlined;
      case 'wxpay':
      case 'codepay_wxpay':
        return Icons.chat_bubble_outline_rounded;
      case 'stripe':
        return Icons.credit_card_rounded;
      case 'crypto':
        return Icons.currency_bitcoin_rounded;
      default:
        return Icons.payments_outlined;
    }
  }

  Future<void> _buy(MoneyflyPackage item) async {
    final method = _selectedMethod;
    if (method == null) {
      await DialogUtils.showAlertDialog(context, '暂无可用支付方式');
      return;
    }
    setState(() => _working = true);
    try {
      final account = context.read<MoneyflyAccountController>();
      final order = await account.createOrder(item.id);
      final payment = await account.createPayment(
        orderId: order.id,
        paymentMethodId: method.id,
      );
      if (!mounted) {
        return;
      }
      if (!payment.hasPaymentContent) {
        await DialogUtils.showAlertDialog(context, '支付方式未返回支付链接或二维码');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoneyflyPaymentScreen(
            order: order,
            payment: payment,
            paymentMethodName: method.displayName,
            packageName: item.name,
          ),
        ),
      );
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

import 'package:flutter/material.dart';
import 'package:karing/features/moneyfly/moneyfly_account_controller.dart';
import 'package:karing/features/moneyfly/moneyfly_devices_screen.dart';
import 'package:karing/features/moneyfly/moneyfly_purchase_screen.dart';
import 'package:karing/features/moneyfly/moneyfly_theme.dart';
import 'package:provider/provider.dart';

class MoneyflyHomeHeader extends StatelessWidget {
  const MoneyflyHomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<MoneyflyAccountController>();
    final user = account.user;
    final sub = account.subscription;
    final dashboard = account.dashboard;
    final statusColor =
        sub?.available == true ? MoneyflyColors.green : MoneyflyColors.red;
    final packageName = sub?.packageName.isNotEmpty == true
        ? sub!.packageName
        : sub?.status ?? '未开通';
    final expireText = sub?.expireAt.isNotEmpty == true ? sub!.expireAt : '未开通';
    final remainingText = sub == null
        ? '请购买套餐'
        : sub.daysRemaining > 0
            ? '剩余 ${sub.daysRemaining} 天'
            : '已到期';
    final deviceText =
        sub == null ? '--' : '${sub.currentDevices}/${sub.deviceLimit}';
    final nodeText = dashboard == null
        ? '--'
        : '${dashboard.nodeOnline}/${dashboard.nodeTotal}';

    return MoneyflyPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: MoneyflyColors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flight_takeoff_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.username.isNotEmpty == true
                          ? user!.username
                          : 'MoneyFly',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MoneyflyColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user?.email ?? '自动同步订阅与配置',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MoneyflyColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '同步订阅',
                onPressed: account.syncing
                    ? null
                    : () => account.refreshAccount(syncConfig: true),
                icon: account.syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MoneyflyColors.soft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffe2e7ed)),
            ),
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
                          const Text(
                            '当前套餐',
                            style: TextStyle(
                              color: MoneyflyColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            packageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MoneyflyStatusPill(
                      label: sub?.available == true ? '可用' : '需处理',
                      color: statusColor,
                      icon: sub?.available == true
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360;
                    final columns = compact ? 2 : 4;
                    final spacing = compact ? 10.0 : 8.0;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 10,
                      children: [
                        _Metric(label: '到期', value: expireText, width: width),
                        _Metric(
                          label: '状态',
                          value: remainingText,
                          width: width,
                          color: statusColor,
                        ),
                        _Metric(label: '设备', value: deviceText, width: width),
                        _Metric(label: '节点', value: nodeText, width: width),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: moneyflyPrimaryButtonStyle(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MoneyflyPurchaseScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('套餐购买'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: MoneyflyColors.blue,
                    side: const BorderSide(color: Color(0xffc9dcff)),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MoneyflyDevicesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.devices_rounded),
                  label: const Text('设备管理'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.width,
    this.color,
  });

  final String label;
  final String value;
  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: MoneyflyColors.muted),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? MoneyflyColors.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:karing/features/moneyfly/moneyfly_account_controller.dart';
import 'package:karing/features/moneyfly/moneyfly_models.dart';
import 'package:karing/features/moneyfly/moneyfly_theme.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:provider/provider.dart';

class MoneyflyDevicesScreen extends StatefulWidget {
  const MoneyflyDevicesScreen({super.key});

  @override
  State<MoneyflyDevicesScreen> createState() => _MoneyflyDevicesScreenState();
}

class _MoneyflyDevicesScreenState extends State<MoneyflyDevicesScreen> {
  late Future<List<MoneyflyDevice>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<MoneyflyAccountController>();
    final sub = account.subscription;
    final current = sub?.currentDevices ?? 0;
    final limit = sub?.deviceLimit ?? 0;
    final progress =
        limit <= 0 ? 0.0 : (current / limit).clamp(0.0, 1.0).toDouble();
    final overLimit = limit > 0 && current > limit;

    return MoneyflyPage(
      title: '设备管理',
      actions: [
        IconButton(
          tooltip: '刷新设备',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: FutureBuilder<List<MoneyflyDevice>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final devices = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              _deviceQuotaCard(
                current: current,
                limit: limit,
                progress: progress,
                overLimit: overLimit,
              ),
              const SizedBox(height: 18),
              MoneyflySectionTitle(
                '已登录设备',
                trailing: Text(
                  '${devices.length} 台',
                  style: const TextStyle(
                    color: MoneyflyColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (devices.isEmpty)
                const MoneyflyEmptyState(
                  icon: Icons.devices_other_rounded,
                  title: '暂无设备',
                  message: '登录并同步订阅后，本机会自动显示在这里。',
                )
              else
                for (final item in devices) ...[
                  _deviceCard(item),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 6),
              _limitHelpCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _deviceQuotaCard({
    required int current,
    required int limit,
    required double progress,
    required bool overLimit,
  }) {
    return MoneyflyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '设备数量',
                  style: TextStyle(
                    color: MoneyflyColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              MoneyflyStatusPill(
                label: overLimit ? '已超限' : '正常',
                color: overLimit ? MoneyflyColors.red : MoneyflyColors.green,
                icon: overLimit
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            limit <= 0 ? '$current / --' : '$current / $limit',
            style: TextStyle(
              color: overLimit ? MoneyflyColors.red : MoneyflyColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              color: overLimit ? MoneyflyColors.red : MoneyflyColors.green,
              backgroundColor: const Color(0xffe1e8ef),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(MoneyflyDevice item) {
    final title = item.remark.isNotEmpty
        ? item.remark
        : (item.deviceName.isNotEmpty ? item.deviceName : '未命名设备');
    final details = [
      if (item.osName.isNotEmpty) item.osName,
      if (item.deviceType.isNotEmpty) item.deviceType,
      if (item.region.isNotEmpty) item.region,
      if (item.ipAddress.isNotEmpty) item.ipAddress,
    ].join(' · ');
    final lastAccess =
        item.lastAccess.isNotEmpty ? '最近访问：${item.lastAccess}' : '最近访问：--';

    return MoneyflyPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xffeef4ff),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.devices_rounded,
              color: MoneyflyColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MoneyflyColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                if (details.isNotEmpty)
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MoneyflyColors.muted),
                  ),
                const SizedBox(height: 6),
                Text(
                  lastAccess,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MoneyflyColors.muted,
                    fontSize: 12,
                  ),
                ),
                if (item.remark.isNotEmpty &&
                    item.deviceName.isNotEmpty &&
                    item.remark != item.deviceName) ...[
                  const SizedBox(height: 4),
                  Text(
                    '设备名：${item.deviceName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MoneyflyColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '设备操作',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'remark') {
                _remark(item);
              } else if (value == 'delete') {
                _delete(item);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'remark',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('修改备注'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('删除设备'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _limitHelpCard() {
    return const MoneyflyPanel(
      color: Color(0xfffff7e8),
      borderColor: Color(0xffefd6a9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设备超限处理',
            style: TextStyle(
              color: MoneyflyColors.amber,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 10),
          Text(
            '超过套餐限制时，订阅会返回失效节点。删除不用的设备后，重新连接会自动更新配置。',
            style: TextStyle(color: MoneyflyColors.muted),
          ),
          SizedBox(height: 12),
          MoneyflyStatusPill(
            label: '固定设备识别',
            color: MoneyflyColors.amber,
            icon: Icons.phonelink_lock_outlined,
          ),
          SizedBox(height: 12),
          Text(
            'App 使用固定设备 ID，避免换网络重复占用设备。',
            style: TextStyle(color: MoneyflyColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _reload() {
    _future = context.read<MoneyflyAccountController>().loadDevices();
  }

  Future<void> _remark(MoneyflyDevice item) async {
    final text = await DialogUtils.showTextInputDialog(
      context,
      '设备备注',
      item.remark,
      '备注',
      null,
      (_) => true,
    );
    if (text == null) {
      return;
    }
    await context.read<MoneyflyAccountController>().updateDeviceRemark(
          item.id,
          text.trim(),
        );
    if (mounted) {
      setState(_reload);
    }
  }

  Future<void> _delete(MoneyflyDevice item) async {
    final ok = await DialogUtils.showConfirmDialog(context, '确认删除这台设备？');
    if (ok != true || !mounted) {
      return;
    }
    await context.read<MoneyflyAccountController>().deleteDevice(item.id);
    if (mounted) {
      setState(_reload);
    }
  }
}

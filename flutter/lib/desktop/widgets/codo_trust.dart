import 'package:flutter/material.dart';

import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import '../../utils/codo_trust.dart';

class CodoTrustButton extends StatelessWidget {
  final Client client;
  const CodoTrustButton({super.key, required this.client});

  Future<void> _toggle(BuildContext context) async {
    final trusted = client.codoTrust == 2;
    if (!trusted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('信任此设备？'),
          content: Text('「${client.name}」（${client.peerId}）以后无需输入密码、'
              '也无需你点击接受，就能直接连接并控制这台电脑。\n'
              '可随时在 设置 → 安全 → 免密信任设备 中撤销。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('信任')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    bind.cmSwitchPermission(
        connId: client.id, name: kCodoTrustPermission, enabled: !trusted);
  }

  @override
  Widget build(BuildContext context) {
    final trusted = client.codoTrust == 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(
                trusted ? Icons.verified_user : Icons.shield_outlined,
                size: 16),
            label: Text(trusted ? '已信任此设备 · 点击撤销' : '信任此设备，以后免密连接',
                overflow: TextOverflow.ellipsis),
            onPressed: () => _toggle(context),
          ),
        ),
      ]),
    );
  }
}

class CodoTrustHint extends StatelessWidget {
  const CodoTrustHint({super.key});
  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Text('勾选后，被控电脑可在连接窗口点击「信任此设备」；获得信任后，即使对方密码变了也能直接连接。',
            style: TextStyle(fontSize: 12)),
      );
}

class CodoTrustedControllers extends StatefulWidget {
  const CodoTrustedControllers({super.key});
  @override
  State<CodoTrustedControllers> createState() => _CodoTrustedControllersState();
}

class _CodoTrustedControllersState extends State<CodoTrustedControllers> {
  late String _option =
      bind.mainGetOptionSync(key: kOptionCodoTrustedControllers);

  Future<void> _save(String option) async {
    await bind.mainSetOption(key: kOptionCodoTrustedControllers, value: option);
    if (mounted) setState(() => _option = option);
  }

  @override
  Widget build(BuildContext context) {
    final controllers = parseCodoTrustedControllers(_option);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              controllers.isEmpty
                  ? '暂无。控制端登录时勾选「记住密码」，再由本机在连接窗口点击「信任此设备」后，会显示在这里。'
                  : '以下设备无需密码即可连接并控制本机：',
              style: const TextStyle(fontSize: 12)),
          for (final controller in controllers)
            Row(children: [
              Expanded(
                  child: Text(
                      '${controller.name.isEmpty ? "未命名" : controller.name}（${controller.id}）'
                      ' · ${DateTime.fromMillisecondsSinceEpoch(controller.time).toString().split(".").first}',
                      overflow: TextOverflow.ellipsis)),
              TextButton(
                  onPressed: () => _save(removeCodoTrustedController(
                      _option, controller.verifier)),
                  child: const Text('撤销')),
            ]),
          Row(children: [
            if (controllers.isNotEmpty)
              TextButton(
                  onPressed: () => _save(''), child: const Text('全部撤销')),
            TextButton(
                onPressed: () => setState(() => _option = bind
                    .mainGetOptionSync(key: kOptionCodoTrustedControllers)),
                child: const Text('刷新')),
          ]),
        ],
      ),
    );
  }
}

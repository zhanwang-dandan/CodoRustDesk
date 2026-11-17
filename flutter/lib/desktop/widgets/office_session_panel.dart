import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../utils/office_profile.dart';

void showOfficeSessionPanel(FFI ffi) {
  ffi.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: const Text('CodoRustDesk · 美区办公与诊断'),
        content: SizedBox(
          width: 500,
          height: 480,
          child: SingleChildScrollView(child: OfficeSessionPanel(ffi: ffi)),
        ),
        actions: [dialogButton('Close', onPressed: close)],
        onCancel: close,
      ));
}

class OfficeSessionPanel extends StatefulWidget {
  final FFI ffi;
  const OfficeSessionPanel({super.key, required this.ffi});
  @override
  State<OfficeSessionPanel> createState() => _OfficeSessionPanelState();
}

class _OfficeSessionPanelState extends State<OfficeSessionPanel> {
  bool _busy = false;
  String _message = '';
  String _current = '正在读取当前配置…';

  @override
  void initState() {
    super.initState();
    _readCurrent();
  }

  Future<void> _readCurrent() async {
    try {
      final session = widget.ffi.sessionId;
      final quality = await bind.sessionGetImageQuality(sessionId: session);
      final custom =
          await bind.sessionGetCustomImageQuality(sessionId: session);
      final fps =
          await bind.sessionGetOption(sessionId: session, arg: 'custom-fps');
      if (!mounted) return;
      setState(() => _current = quality == 'custom'
          ? '当前画质 ${custom != null && custom.isNotEmpty ? custom.first : "自动"} · 帧率上限 ${fps == null || fps.isEmpty ? "自动" : fps}'
          : '当前使用原版预设：${quality ?? "自动"}');
    } catch (error) {
      if (mounted) setState(() => _current = '当前配置暂不可读：$error');
    }
  }

  Future<void> _apply(OfficeProfile? profile) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final ffi = widget.ffi;
      final publicServer = await bind.mainIsUsingPublicServer();
      final allowFps = (!publicServer || ffi.ffiModel.direct == true) &&
          versionCmp(ffi.ffiModel.pi.version, '1.2.0') >= 0;
      if (profile != null) {
        await bind.sessionSetImageQuality(
            sessionId: ffi.sessionId, value: 'custom');
        await bind.sessionSetCustomImageQuality(
            sessionId: ffi.sessionId, value: profile.quality);
      }
      if (allowFps) {
        await bind.sessionSetCustomFps(
            sessionId: ffi.sessionId, fps: profile?.fps ?? 30);
      }
      if (profile == null) {
        await bind.sessionSetImageQuality(
            sessionId: ffi.sessionId, value: kRemoteImageQualityBalanced);
      }
      final wantTrueColor = profile?.trueColor ?? false;
      final allowTrueColor = versionCmp(ffi.ffiModel.pi.version, '1.2.4') >=
              0 &&
          officeTrueColorSupported(ffi.qualityMonitorModel.data.codecFormat);
      if (allowTrueColor &&
          bind.sessionGetToggleOptionSync(
                  sessionId: ffi.sessionId, arg: kOptionI444) !=
              wantTrueColor) {
        await bind.sessionToggleOption(
            sessionId: ffi.sessionId, value: kOptionI444);
        bind.sessionChangePreferCodec(sessionId: ffi.sessionId);
      }
      await _readCurrent();
      if (mounted) {
        setState(() => _message = '${profile?.title ?? "原版均衡"}配置已发送并按设备保存。'
            '${allowFps ? "帧率为上限，实际帧率由会话调整。" : "当前公共中继或远端版本不支持自定义帧率，已保持其帧率策略。"}'
            '${wantTrueColor && !allowTrueColor ? "当前编码不支持 4:4:4 真彩色，文字边缘清晰度未提升。" : ""}');
      }
    } catch (error) {
      if (mounted) setState(() => _message = '配置未完成，请重试：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _punchEnabled =>
      mainGetLocalBoolOptionSync(kOptionEnableUdpPunch) &&
      mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);

  Future<void> _enablePunch() async {
    await mainSetLocalBoolOption(kOptionEnableUdpPunch, true);
    await mainSetLocalBoolOption(kOptionEnableIpv6Punch, true);
    if (mounted) {
      setState(() => _message = '已在本机开启 UDP 打洞和 IPv6 直连。'
          '被控电脑也需在 设置 → 常规 → 其他 中开启这两项，重新连接后生效；能否直连取决于两端网络。');
    }
  }

  String _report() {
    final ffi = widget.ffi, data = ffi.qualityMonitorModel.data;
    return 'CodoRustDesk Office 试用诊断\n'
        '连接：${ffi.ffiModel.direct == null ? "尚未确认" : ffi.ffiModel.direct! ? "直连" : "中继"}\n'
        '会话延迟：${data.delay ?? "--"} ms\n'
        '帧率：${data.fps ?? "--"}\n'
        '传输速度：${data.speed ?? "--"}\n'
        '目标码率：${data.targetBitrate ?? "--"}\n'
        '编码：${data.codecFormat ?? "--"} · 色度：${data.chroma ?? "--"}\n$_current\n'
        '${officeConnectionAdvice(direct: ffi.ffiModel.direct, delay: data.delay, fps: data.fps)}';
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('面向浏览器、办公和代码编辑的画质／帧率预设。先测试均衡办公，再持续滚动页面比较效果。'),
          const SizedBox(height: 12),
          for (final profile in officeProfiles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: _busy ? null : () => _apply(profile),
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${profile.title} · 画质 ${profile.quality} / ${profile.fps} FPS 上限'),
                        Text(profile.description,
                            style: const TextStyle(fontSize: 12))
                      ],
                    )),
              ),
            ),
          Text(_current, style: const TextStyle(fontSize: 12)),
          if (widget.ffi.ffiModel.direct == false && !_punchEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _busy ? null : _enablePunch,
                child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开启直连优化 · UDP 打洞 + IPv6 直连'),
                        Text('当前经过中继。两端直连可绕开中继，通常是降低键鼠延迟最有效的办法。',
                            style: TextStyle(fontSize: 12))
                      ],
                    )),
              ),
            ),
          if (_message.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message)),
          AnimatedBuilder(
            animation: Listenable.merge(
                [widget.ffi.qualityMonitorModel, widget.ffi.ffiModel]),
            builder: (context, _) => SelectableText(_report(),
                style: const TextStyle(fontSize: 12, height: 1.7)),
          ),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: _busy ? null : () => _apply(null),
                child: const Text('恢复原版均衡')),
            TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _report()));
                  if (mounted) {
                    setState(() => _message = '诊断已复制，不包含设备 ID、密码或地址。');
                  }
                },
                child: const Text('复制诊断')),
          ]),
          const Text('画面静止时，低帧率不代表连接缓慢。跨国线路、远端上传和编码性能仍会影响体验。',
              style: TextStyle(fontSize: 11)),
        ],
      );
}

class OfficeWelcomeBanner extends StatelessWidget {
  const OfficeWelcomeBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12, right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(.07),
            borderRadius: BorderRadius.circular(8)),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CodoRustDesk Office · 自用试用版',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text('连接美国电脑后，在顶部「显示」菜单打开「美区办公与诊断」，可切换文字／办公配置并复制连接指标。',
                  style: TextStyle(fontSize: 12, height: 1.6)),
            ]),
      );
}

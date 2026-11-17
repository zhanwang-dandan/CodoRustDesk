class OfficeProfile {
  final String title;
  final String description;
  final int quality;
  final int fps;
  // 4:4:4 chroma keeps coloured text edges sharp, at the cost of more data.
  final bool trueColor;
  const OfficeProfile(this.title, this.description, this.quality, this.fps,
      {this.trueColor = false});
}

const officeProfiles = [
  OfficeProfile('均衡办公', '浏览器、邮件与日常操作，先从这个配置开始。', 60, 30),
  OfficeProfile('文字与代码', '提高文字画质并启用 4:4:4 真彩色，降低帧率上限，为编辑器保留传输空间。', 80, 20,
      trueColor: true),
  OfficeProfile('低带宽办公', '减少画面数据，适合网络拥挤时对照测试。', 40, 15),
  OfficeProfile('流畅操作', '保持帧率、压低画质，减少排队的画面数据，键鼠跟手优先。', 45, 30),
];

bool officeTrueColorSupported(String? codecFormat) =>
    codecFormat == 'AV1' || codecFormat == 'VP9';

String officeConnectionAdvice({bool? direct, String? delay, String? fps}) {
  final latency = double.tryParse(delay ?? '');
  final frames = double.tryParse(fps ?? '');
  final messages = <String>[
    if (direct == null)
      '连接方式尚未确认。'
    else if (direct)
      '当前为直连。'
    else
      '当前经过中继。中继位置和两端线路会影响体验，可与直连或自建中继对照。',
    if (latency != null && latency.isFinite && latency >= 180)
      '会话延迟较高；降低画质可减少传输负担，但不能消除跨国线路的往返延迟。',
    if (frames != null && frames.isFinite && frames > 0 && frames < 12)
      '画面更新较少，可在持续滚动页面时比较低带宽配置；静态页面低帧率本身不代表卡顿。',
  ];
  return messages.join('\n');
}

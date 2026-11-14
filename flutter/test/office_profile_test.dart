import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/utils/office_profile.dart';

void main() {
  test('代码模式优先清晰文字，低带宽模式降低传输负担，预设落在标准可调范围', () {
    final office = officeProfiles[0],
        code = officeProfiles[1],
        low = officeProfiles[2];
    expect(code.quality, greaterThan(office.quality));
    expect(code.fps, lessThan(office.fps));
    expect(low.quality, lessThan(office.quality));
    expect(low.fps, lessThan(office.fps));
    for (final profile in officeProfiles) {
      expect(profile.quality, inInclusiveRange(10, 100));
      expect(profile.fps, inInclusiveRange(5, 120));
    }
  });
  test('未建立连接或无有效指标时不虚构延迟、吞吐或限速结论', () {
    final pending = officeConnectionAdvice(delay: 'NaN', fps: '--');
    expect(pending, '连接方式尚未确认。');
    expect(officeConnectionAdvice(direct: true, delay: '220', fps: '30'),
        contains('往返延迟'));
  });
  test('静止画面零帧率不误判卡顿，中继说明与低帧率建议保持可区分', () {
    final idle = officeConnectionAdvice(direct: false, delay: '80', fps: '0');
    expect(idle, contains('中继'));
    expect(idle, isNot(contains('画面更新较少')));
    expect(officeConnectionAdvice(direct: true, delay: '80', fps: '8'),
        contains('静态页面'));
  });
}

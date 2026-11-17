import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/utils/codo_trust.dart';

void main() {
  const option = '[{"verifier":"aa","id":"111","name":"Office","time":1},'
      '{"verifier":"bb","id":"222","name":"Home","time":2}]';

  test('列出被控端保存的免密信任设备，损坏或为空的配置视为没有设备', () {
    final controllers = parseCodoTrustedControllers(option);
    expect(controllers.map((c) => c.id), ['111', '222']);
    expect(controllers.first.name, 'Office');
    expect(parseCodoTrustedControllers(''), isEmpty);
    expect(parseCodoTrustedControllers('{"verifier":"aa"}'), isEmpty);
  });

  test('撤销一台设备后其余设备保留，全部撤销后配置清空', () {
    final rest = removeCodoTrustedController(option, 'aa');
    expect(parseCodoTrustedControllers(rest).map((c) => c.id), ['222']);
    expect(removeCodoTrustedController(rest, 'bb'), '');
  });
}

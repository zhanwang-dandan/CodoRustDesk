import 'dart:convert';

const kCodoTrustPermission = 'codo_trust';
const kOptionCodoTrustedControllers = 'codo-trusted-controllers';

class CodoTrustedController {
  final String verifier;
  final String id;
  final String name;
  final int time;
  const CodoTrustedController(this.verifier, this.id, this.name, this.time);

  Map<String, dynamic> toJson() =>
      {'verifier': verifier, 'id': id, 'name': name, 'time': time};
}

List<CodoTrustedController> parseCodoTrustedControllers(String option) {
  try {
    final decoded = jsonDecode(option);
    if (decoded is! List) return [];
    return [
      for (final item in decoded)
        if (item is Map && item['verifier'] is String)
          CodoTrustedController(item['verifier'], '${item['id'] ?? ''}',
              '${item['name'] ?? ''}', item['time'] is int ? item['time'] : 0),
    ];
  } catch (_) {
    return [];
  }
}

String removeCodoTrustedController(String option, String verifier) {
  final rest = parseCodoTrustedControllers(option)
      .where((controller) => controller.verifier != verifier)
      .toList();
  return rest.isEmpty ? '' : jsonEncode(rest);
}

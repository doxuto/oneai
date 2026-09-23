import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/config/app_config.dart';

void main() {
  test('legalUrl points at the legal function in the user language, en for anything else', () {
    final c = AppConfig.fromEnvironment(projectId: 'oneai-dev');
    expect(c.legalUrl('privacy', 'vi'), 'https://asia-southeast1-oneai-dev.cloudfunctions.net/legal?doc=privacy&lang=vi');
    expect(c.legalUrl('terms', 'es'), 'https://asia-southeast1-oneai-dev.cloudfunctions.net/legal?doc=terms&lang=en');
  });
  test('without a project id it falls back to the website URLs', () {
    final c = AppConfig.fromEnvironment();
    expect(c.legalUrl('privacy', 'vi'), c.privacyUrl);
    expect(c.legalUrl('terms', 'en'), c.termsUrl);
  });
}

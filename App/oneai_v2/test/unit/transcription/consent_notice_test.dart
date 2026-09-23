import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/transcription/consent_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shown until acknowledged once, then never again on this device', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ConsentNotice.isAcknowledged(), isFalse);
    await ConsentNotice.acknowledge();
    expect(await ConsentNotice.isAcknowledged(), isTrue);
  });
}

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/transcription/battery_check.dart';

void main() {
  test('warns only when low and not charging', () {
    expect(isBatteryTooLow(10, BatteryState.discharging), isTrue);
    expect(isBatteryTooLow(15, BatteryState.unknown), isTrue);
    expect(isBatteryTooLow(10, BatteryState.charging), isFalse);
    expect(isBatteryTooLow(16, BatteryState.discharging), isFalse);
    expect(isBatteryTooLow(null, BatteryState.discharging), isFalse);
  });
}

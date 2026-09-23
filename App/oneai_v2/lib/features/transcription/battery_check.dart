import 'package:battery_plus/battery_plus.dart';

/// S11-09b — a long recording on an almost-empty battery ends in a lost
/// meeting. Below this level and not charging, the record screen warns once
/// (it never blocks: the user may know better).
const lowBatteryPercent = 15;

/// Pure decision, testable without the plugin.
bool isBatteryTooLow(int? level, BatteryState? state) =>
    level != null && level <= lowBatteryPercent && state != BatteryState.charging && state != BatteryState.full;

Future<bool> batteryTooLow([Battery? battery]) async {
  try {
    final b = battery ?? Battery();
    return isBatteryTooLow(await b.batteryLevel, await b.batteryState);
  } on Object catch (_) {
    return false; // unsupported platform / plugin missing → no warning
  }
}

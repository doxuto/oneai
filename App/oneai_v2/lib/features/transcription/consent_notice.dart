import 'package:shared_preferences/shared_preferences.dart';

/// S11-12 — one-time reminder before the first recording: many places require
/// telling the other people they are being recorded. Shown once per device;
/// the share-a-notice button on the record screen stays for every later time.
class ConsentNotice {
  static const key = 'RECORDING_CONSENT_ACK_V2';

  static Future<bool> isAcknowledged() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } on Object catch (_) {
      return true; // never block a recording on a preferences failure
    }
  }

  static Future<void> acknowledge() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, true);
    } on Object catch (_) {}
  }
}

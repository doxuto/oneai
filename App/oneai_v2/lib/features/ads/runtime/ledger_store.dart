import 'package:one_ai/features/ads/ad_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the pure ledger between launches (per device).
class LedgerStore {
  static const key = 'AD_LEDGER_V2';

  Future<AdLedger> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return AdLedger.decode(p.getString(key));
    } on Object catch (_) {
      return AdLedger();
    }
  }

  Future<void> save(AdLedger l) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, l.encode());
    } on Object catch (_) {}
  }
}

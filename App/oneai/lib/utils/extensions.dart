import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/data/services/admob/interstitial_ad_service.dart';
import 'package:codebase_ai/data/services/admob/open_app_ad_service.dart';
import 'package:codebase_ai/data/services/admob/reward_ad_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

final _log = Logger('Extensions');

Future<bool> isPremium() async {
  try {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey(Constants.entitlementId);
  } catch (e) {
    // Handle any errors that might occur while fetching customer info
    return false;
  }
}

// Check internet connectivity using Dio
Future<bool> hasInternetConnection() async {
  try {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    final dio = Dio();
    final response = await dio.get(
      'https://www.google.com',
      options: Options(sendTimeout: const Duration(seconds: 3), receiveTimeout: const Duration(seconds: 3)),
    );
    return response.statusCode == 200;
  } catch (e) {
    _log.warning('Internet check failed: $e');
    return false;
  }
}

extension ContextExtension on BuildContext {
  bool isFullscreenAdInProgress() =>
      read<OpenAppAdService>().isLocked() ||
      read<InterstitialAdService>().isLocked() ||
      read<RewardAdService>().isLocked();
}

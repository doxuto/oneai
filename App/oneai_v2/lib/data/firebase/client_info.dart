import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';

/// Every callable request carries this block. The server's parse() uses it for
/// the min-version gate, which is the only force-update mechanism available.
class ClientInfo {
  const ClientInfo({
    required this.appVersion,
    required this.build,
    required this.platform,
  });

  static Future<ClientInfo> current() async {
    final info = await PackageInfo.fromPlatform();
    return ClientInfo(
      appVersion: info.version,
      build: int.tryParse(info.buildNumber) ?? 0,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
  }

  final String appVersion;
  final int build;
  final String platform;

  Map<String, Object?> toJson() => {
        'appVersion': appVersion,
        'build': build,
        'platform': platform,
      };
}

import 'package:codebase_ai/data/services/remote_config_service.dart';
import 'package:codebase_ai/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

/// This widget demonstrates inline adaptive banner ads.
///
/// Loads and shows an inline adaptive banner ad in a scrolling view,
/// and reloads the ad when the orientation changes.
class InlineAdaptiveBannerAd extends StatefulWidget {
  const InlineAdaptiveBannerAd({super.key});

  @override
  InlineAdaptiveBannerAdState createState() => InlineAdaptiveBannerAdState();
}

class InlineAdaptiveBannerAdState extends State<InlineAdaptiveBannerAd> {
  Orientation? _currentOrientation;
  double? _adWidth;
  bool isJobLoading = false;

  // State changed
  BannerAd? _inlineAdaptiveAd;
  bool _isAdLoaded = false;
  AdSize? _adSize;

  final _log = Logger('InlineAdaptiveBannerAd');

  @override
  void initState() {
    super.initState();
    _log.info('Inline adaptive banner ad initialized');
  }

  Future<void> _loadAd(Orientation orientation, double width) async {
    if (orientation == _currentOrientation && width == _adWidth && _inlineAdaptiveAd != null) {
      _log.info('Inline adaptive banner ad is already loaded, skipping load');
      return;
    }

    if (isJobLoading) {
      _log.info('Inline adaptive banner ad is already loading, skipping load');
      return;
    }

    isJobLoading = true;
    final isAdBannerEnabled = context.read<RemoteConfigService>().adBannerEnabled;
    final adUnitBanner = context.read<RemoteConfigService>().adUnitBanner;
    if (!isAdBannerEnabled) {
      _log.info('Ad banner is disabled in remote config, skipping inline adaptive banner ad');
      isJobLoading = false;
      return;
    }

    if (await isPremium()) {
      _log.info('User is premium, skipping inline adaptive banner ad');
      isJobLoading = false;
      return;
    }

    await _inlineAdaptiveAd?.dispose();

    _adWidth = width;
    _currentOrientation = orientation;

    if (mounted) {
      setState(() {
        _inlineAdaptiveAd = null;
        _isAdLoaded = false;
        _adSize = null;
      });
    }

    // Get an inline adaptive size for the current orientation.
    // final size = AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(width.truncate());
    final size = AdSize.getInlineAdaptiveBannerAdSize(width.truncate(), 60);

    _log.info('Loading inline adaptive banner ad: $adUnitBanner, ${size.width} x ${size.height}');
    _inlineAdaptiveAd = BannerAd(
      adUnitId: adUnitBanner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) async {
          _log.info('Inline adaptive banner loaded');

          // After the ad is loaded, get the platform ad size and use it to
          // update the height of the container. This is necessary because the
          // height can change after the ad is loaded.
          final BannerAd bannerAd = ad as BannerAd;
          final AdSize? size = await bannerAd.getPlatformAdSize();
          if (size == null) {
            _log.warning('Error: getPlatformAdSize() returned null for $bannerAd');
            return;
          }

          if (mounted) {
            setState(() {
              _inlineAdaptiveAd = bannerAd;
              _isAdLoaded = true;
              _adSize = size;
            });
          }
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _log.warning('Inline adaptive banner failedToLoad: $error');
          ad.dispose();
        },
      ),
    );
    await _inlineAdaptiveAd!.load();
    isJobLoading = false;
  }

  @override
  Widget build(BuildContext context) => OrientationBuilder(
    builder:
        (context, orientation) => LayoutBuilder(
          builder: (context, constraints) {
            final double maxWidth = constraints.maxWidth;
            _loadAd(orientation, maxWidth);
            if (_inlineAdaptiveAd != null && _isAdLoaded && _adSize != null) {
              return Align(
                child: SizedBox(
                  width: _adSize!.width.toDouble(),
                  height: _adSize!.height.toDouble(),
                  child: AdWidget(ad: _inlineAdaptiveAd!),
                ),
              );
            }
            return Container();
          },
        ),
  );

  @override
  void dispose() {
    super.dispose();
    _inlineAdaptiveAd?.dispose();
  }
}

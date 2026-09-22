import 'package:flutter/widgets.dart';

/// Spacing scale from v1's dimens.dart, as numbers this time so they can also
/// be used for padding and radii, with the same SizedBox helpers on top.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}

const SizedBox gapW4 = SizedBox(width: AppSpacing.xs);
const SizedBox gapW8 = SizedBox(width: AppSpacing.sm);
const SizedBox gapW12 = SizedBox(width: AppSpacing.md);
const SizedBox gapW16 = SizedBox(width: AppSpacing.lg);
const SizedBox gapW24 = SizedBox(width: AppSpacing.xl);
const SizedBox gapW32 = SizedBox(width: AppSpacing.xxl);
const SizedBox gapW48 = SizedBox(width: AppSpacing.xxxl);
const SizedBox gapW64 = SizedBox(width: AppSpacing.huge);

const SizedBox gapH4 = SizedBox(height: AppSpacing.xs);
const SizedBox gapH8 = SizedBox(height: AppSpacing.sm);
const SizedBox gapH12 = SizedBox(height: AppSpacing.md);
const SizedBox gapH16 = SizedBox(height: AppSpacing.lg);
const SizedBox gapH24 = SizedBox(height: AppSpacing.xl);
const SizedBox gapH32 = SizedBox(height: AppSpacing.xxl);
const SizedBox gapH48 = SizedBox(height: AppSpacing.xxxl);
const SizedBox gapH64 = SizedBox(height: AppSpacing.huge);

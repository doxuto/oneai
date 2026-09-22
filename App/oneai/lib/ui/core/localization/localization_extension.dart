import 'package:codebase_ai/ui/core/localization/generated/l10n.dart';
import 'package:flutter/material.dart';

/// Extension on BuildContext to easily access localization
extension LocalizationExtension on BuildContext {
  AppLocalizations get loc => AppLocalizations.of(this);
}

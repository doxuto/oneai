import 'package:flutter/widgets.dart';
import 'package:one_ai/core/l10n/generated/app_localizations.dart';

export 'package:one_ai/core/l10n/generated/app_localizations.dart';

/// `context.l10n.myNotes` — the only way UI code reads a string.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

import 'package:codebase_ai/ui/core/localization/generated/l10n.dart';
import 'package:codebase_ai/ui/core/localization/view_model/language_bloc.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A widget that allows the user to switch between languages
class LanguageSelector extends StatelessWidget {
  /// Creates a [LanguageSelector] widget
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<LanguageBloc, LanguageState>(
    builder: (context, state) {
      final currentLocale = state.locale;

      return PopupMenuButton<Locale>(
        icon: const Icon(Icons.language),
        tooltip: 'Change language',
        onSelected: (Locale locale) {
          context.read<LanguageBloc>().add(LanguageEvent.changed(locale: locale));
        },
        itemBuilder:
            (BuildContext context) =>
                AppLocalizations.delegate.supportedLocales
                    .map(
                      (Locale locale) => PopupMenuItem<Locale>(
                        value: locale,
                        child: Row(
                          children: [
                            if (locale.languageCode == currentLocale.languageCode) const Icon(Icons.check, size: 18),
                            gapW8,
                            Text(_getLanguageName(locale.languageCode)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
      );
    },
  );

  // Get language display name based on language code
  String _getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      default:
        return languageCode;
    }
  }
}

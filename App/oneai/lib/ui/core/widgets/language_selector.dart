import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:flutter/material.dart';

/// Languages supported for auto detection
enum Language {
  autodetect('auto-detect', 'Auto Detect'),
  arabic('ara', 'Arabic'),
  bengali('ben', 'Bengali'),
  bulgarian('bul', 'Bulgarian'),
  catalan('cat', 'Catalan'),
  chinese('zho', 'Chinese'),
  croatian('hrv', 'Croatian'),
  czech('ces', 'Czech'),
  danish('dan', 'Danish'),
  dutch('nld', 'Dutch'),
  english('eng', 'English'),
  estonian('est', 'Estonian'),
  filipino('fil', 'Filipino'),
  finnish('fin', 'Finnish'),
  french('fra', 'French'),
  german('deu', 'German'),
  greek('ell', 'Greek'),
  hebrew('heb', 'Hebrew'),
  hindi('hin', 'Hindi'),
  hungarian('hun', 'Hungarian'),
  icelandic('isl', 'Icelandic'),
  indonesian('ind', 'Indonesian'),
  italian('ita', 'Italian'),
  japanese('jpn', 'Japanese'),
  kannada('kan', 'Kannada'),
  korean('kor', 'Korean'),
  latvian('lav', 'Latvian'),
  lithuanian('lit', 'Lithuanian'),
  malay('msa', 'Malay'),
  malayalam('mal', 'Malayalam'),
  marathi('mar', 'Marathi'),
  norwegian('nor', 'Norwegian'),
  polish('pol', 'Polish'),
  portuguese('por', 'Portuguese'),
  punjabi('pan', 'Punjabi'),
  romanian('ron', 'Romanian'),
  russian('rus', 'Russian'),
  serbian('srp', 'Serbian'),
  slovak('slk', 'Slovak'),
  slovenian('slv', 'Slovenian'),
  spanish('spa', 'Spanish'),
  swedish('swe', 'Swedish'),
  tamil('tam', 'Tamil'),
  telugu('tel', 'Telugu'),
  thai('tha', 'Thai'),
  turkish('tur', 'Turkish'),
  ukrainian('ukr', 'Ukrainian'),
  urdu('urd', 'Urdu'),
  uzbek('uzb', 'Uzbek'),
  vietnamese('vie', 'Vietnamese');

  final String languageCode;
  final String displayName;

  const Language(this.languageCode, this.displayName);
}

/// A reusable language selector dropdown
class LanguageSelector extends StatelessWidget {
  /// The currently selected language
  final Language selectedLanguage;

  /// Function called when a language is selected
  final ValueChanged<Language> onLanguageSelected;

  /// Custom child widget to display instead of default button. This widget will be used as the trigger for the language selector dropdown.
  final Widget triggerButton;

  /// Creates a language selector widget
  const LanguageSelector({
    required this.selectedLanguage,
    required this.onLanguageSelected,
    required this.triggerButton,
    super.key,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<Language>(
    initialValue: selectedLanguage,
    onSelected: onLanguageSelected,
    offset: const Offset(0, 40),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    popUpAnimationStyle: AnimationStyle(curve: Curves.easeInOut),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<Language>>[
      // Language options
      ...Language.values
          .map((language) {
            final menuItem = PopupMenuItem<Language>(
              value: language,
              height: 42,
              child: Row(
                children: [
                  Text(getLanguageName(context, language)),
                  if (selectedLanguage == language) ...[const Spacer(), Text(' (${context.loc.selected})')],
                ],
              ),
            );

            // Add dividers between items, but not after the last item
            if (language != Language.values.last) {
              return <PopupMenuEntry<Language>>[
                menuItem,
                const PopupMenuItem<Language>(
                  height: 1,
                  enabled: false,
                  padding: EdgeInsets.zero,
                  child: Divider(color: Color(0xFFBDBDBD), height: 1),
                ),
              ];
            } else {
              return [menuItem];
            }
          })
          .expand((widgets) => widgets),
    ],
    child: triggerButton,
  );

  /// Helper method to get the localized name for a language
  static String getLanguageName(BuildContext context, Language language) => language.displayName;
}

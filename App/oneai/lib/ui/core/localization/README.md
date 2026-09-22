# Flutter Internationalization Guide

This directory contains internationalization files for the application.

## Structure

The internationalization setup is organized in the `lib/ui/core/localization` directory:

- `generated/`: Contains auto-generated localization files created by the Flutter Intl plugin
  - `l10n.dart`: Main localization class that provides the translations
  - `intl/messages_all.dart`: Loader for locale-specific message lookups
  - `intl/messages_[locale].dart`: Locale-specific message implementations

- `l10n/`: Contains ARB (Application Resource Bundle) files that define translations
  - `intl_en.arb`: English translations
  - `intl_es.arb`: Spanish translations
  - Add more ARB files for additional languages using the pattern `intl_[locale].arb`

- `language_selector.dart`: A widget that allows users to switch between languages
- `localization_extension.dart`: Provides an extension method on BuildContext for easy access to translations

## Usage

1. Define new strings in the ARB files under the `l10n/` directory
2. Run `flutter --no-color pub global run intl_utils:generate` to regenerate localization files
3. Access translations in your code using the extension method: `context.loc.stringKey`
4. Add the `LanguageSelector` widget to your UI to allow users to switch languages

## Adding a New Language

1. Create a new ARB file named `intl_[locale].arb` in the `l10n/` directory
2. Copy the structure from existing ARB files and translate the string values
3. Run `flutter --no-color pub global run intl_utils:generate` to generate the code for the new language
4. Update the `_getLanguageName` method in `language_selector.dart` to include the new language

## How Localization Works

1. The Flutter Intl plugin generates Dart code from ARB files
2. The main `l10n.dart` file provides the `AppLocalizations` class with getters for all translation strings
3. The `messages_[locale].dart` files contain locale-specific string mappings
4. The `messages_all.dart` file handles loading the appropriate messages based on the selected locale
5. The `localization_extension.dart` provides a convenient `context.loc` shorthand for accessing translations
6. The `LanguageSelector` widget allows users to change the app's locale at runtime

## Changing Language at Runtime

To change the language at runtime, use the `LocaleController` from `main.dart`:
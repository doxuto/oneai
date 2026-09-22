# Generated Localization Files

This directory contains automatically generated files for internationalization:

- `l10n.dart`: Generated Dart code providing localization support and string accessors
- `intl/`: Generated message files for each supported language

**Note:** Do not modify these files directly. To update localizations:
1. Edit the ARB files in the `../l10n` directory
2. Run `flutter --no-color pub global run intl_utils:generate` to regenerate these files
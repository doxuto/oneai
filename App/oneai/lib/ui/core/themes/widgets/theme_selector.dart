import 'package:codebase_ai/domain/models/theme_type_model.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/themes/view_model/theme_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A widget that displays theme mode selection options
class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<ThemeBloc, ThemeState>(
    builder:
        (context, state) => PopupMenuButton<ThemeType>(
          tooltip: context.loc.selectTheme,
          icon: Icon(state.isDarkMode ? Icons.dark_mode : Icons.light_mode, color: context.colorScheme.onSurface),
          onSelected: (themeType) => context.read<ThemeBloc>().add(ThemeEvent.changed(themeType: themeType)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(context.appTheme.buttonRadius)),
          itemBuilder:
              (context) => [
                _buildPopupMenuItem(
                  context,
                  ThemeType.system,
                  context.loc.systemTheme,
                  Icons.brightness_auto,
                  state.themeType,
                ),
                _buildPopupMenuItem(
                  context,
                  ThemeType.light,
                  context.loc.lightTheme,
                  Icons.light_mode,
                  state.themeType,
                ),
                _buildPopupMenuItem(context, ThemeType.dark, context.loc.darkTheme, Icons.dark_mode, state.themeType),
              ],
        ),
  );

  PopupMenuItem<ThemeType> _buildPopupMenuItem(
    BuildContext context,
    ThemeType themeType,
    String text,
    IconData iconData,
    ThemeType currentThemeType,
  ) {
    final isSelected = currentThemeType == themeType;
    final colorScheme = context.colorScheme;

    return PopupMenuItem<ThemeType>(
      value: themeType,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            text,
            style: context.textTheme.labelLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
          gapW8,
          Icon(iconData, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }
}

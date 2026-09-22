# Core UI

This directory contains core UI components and utilities used throughout the application.

## Structure:
- `localization/`: Internationalization and localization components
- `themes/`: Application theme definitions
  - `color_schemes/`: Color scheme definitions for light and dark themes
  - `dark_theme.dart`: Dark theme configuration
  - `light_theme.dart`: Light theme configuration
  - `dimens.dart`: Spacing and dimension constants
  - `typography.dart`: Text styles and font configurations
  - `theme_extension.dart`: Custom theme extensions
  - `theme_helpers.dart`: Helper methods for theme-related operations
  - `theme.dart`: Barrel file exporting all theme-related components
  - `view_model/`: Theme state management using BLoC pattern
  - `widgets/`: Theme-related widgets like ThemeSelector
- `ui/`: Shared reusable UI components that are used across multiple features:
  - Custom buttons
  - Form elements
  - Layout components
  - Common indicators and dialogs

## Theme System

The application uses a comprehensive theming system with support for light, dark, and system themes. The theme system consists of:

1. **Color Schemes**: Separate color palettes for light and dark themes
2. **Typography**: Consistent text styles across themes
3. **Component Themes**: Styling for buttons, cards, inputs and other UI components
4. **Theme Extensions**: Custom theme properties and colors for app-specific components
5. **Theme Helpers**: Utility methods for theme-related operations
6. **Theme Management**: BLoC pattern for managing theme state and persistence

### Usage

To use the theme system:

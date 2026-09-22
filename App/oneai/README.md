# codebase_ai

A modern Flutter app template using Clean Architecture principles and feature-first organization.

## Architecture Overview

This project follows a Clean Architecture approach with a feature-first organization:

- **UI Layer**: Presentation components using BLoC pattern for state management
- **Domain Layer**: Business logic and models independent of external frameworks
- **Data Layer**: Data sources, repositories, and services that implement the domain interfaces

## Features

- **Clean Architecture**: Clear separation of concerns with domain-driven design
- **Feature-first Organization**: Code organized by feature rather than type
- **BLoC Pattern**: Predictable state management using the BLoC pattern
- **Internationalization**: Support for multiple languages
- **Theming**: Comprehensive theming system with light/dark mode
- **Navigation**: Type-safe routing with GoRouter
- **Dependency Injection**: Simple service locator pattern

## Getting Started

### Prerequisites

- Flutter SDK (stable channel)
- Dart SDK
- Android Studio / VS Code with Flutter extensions

### Installation

- Clone the repository
- Install dependencies:

```bash
flutter pub get
```

- Run the application:

```bash
# For development environment
flutter run --target lib/main_development.dart

# For staging environment
flutter run --target lib/main_staging.dart
```

### Code Generation

After modifying models or BLoCs that use freezed:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Localization

After updating ARB files:

```bash
flutter --no-color pub global run intl_utils:generate
```

## Project Structure

```text
lib
├─┬─ ui                      # User interface components
│ ├─┬─ core                  # Core UI components
│ │ ├─── localization        # Internationalization
│ │ ├─┬─ themes              # Theme configuration
│ │ │ ├─── color_schemes     # Color palettes for themes
│ │ │ ├─── view_model        # Theme management
│ │ │ └─── widgets           # Theme-related UI components
│ │ └─┬─ ui                  # Shared widgets
│ │   └─── animation         # Animation utilities
│ └─┬─ features              # Feature-specific UI components
│   └─┬─ <feature_name>      # Each feature has its own directory
│     ├─── view_model        # State management for the feature
│     └─── widgets           # UI components for the feature
├─┬─ domain                  # Business logic and models
│ ├─── models                # Domain models that represent business entities
│ └─── use_cases             # Business logic operations
├─┬─ data                    # Data sources implementation
│ ├─── repositories          # Repository implementations
│ └─┬─ services              # Services for external data sources
│   ├─── api                 # API clients for remote data
│   ├─── local               # Services for local storage
│   └─── model               # DTOs for external services
├─── config                  # App configuration and dependencies
├─── routing                 # Navigation/routing with GoRouter
├─── utils                   # Utilities and helpers
├─── main_development.dart   # Development entry point
├─── main_staging.dart       # Staging entry point
└─── main.dart               # Production entry point

# Testing structure
test                         # Unit and widget tests
├─── data                    # Tests for data layer components
├─── domain                  # Tests for domain layer components
├─── ui                      # Tests for UI components
└─── utils                   # Tests for utilities

testing                      # Test helpers
├─── fakes                   # Fake implementations for testing
└─── models                  # Test data models
```

## Key Components

### BLoC Pattern Implementation

- Uses Freezed for generating immutable state and event classes
- Follows a unidirectional data flow pattern
- Separates UI from business logic

### Navigation

- Type-safe routing with GoRouter
- Customizable page transitions
- Support for deep linking

### Theming System

- Light, dark, and system themes
- Material 3 color schemes
- Custom theme extensions

### Internationalization

- Multiple language support
- Localized strings using ARB files
- Language switching at runtime

## Reference

- [Flutter Intl Extension](https://marketplace.visualstudio.com/items?itemName=localizely.flutter-intl) -
  For internationalization
- [Dart 3.7 Formatting Style](https://github.com/bizz84/flutter-tips-and-tricks/blob/main/tips/0229-new-formatting-style-dart-3.7/index.md) -
  New formatting guidelines
- [Gap Widget Pattern](https://github.com/bizz84/flutter-tips-and-tricks/blob/main/tips/0023-the-gap-widget/index.md) -
  For consistent spacing
- [BLoC Library](https://bloclibrary.dev) - State management
- [GoRouter](https://pub.dev/packages/go_router) - Navigation
- [Freezed](https://pub.dev/packages/freezed) - Code generation for immutable classes
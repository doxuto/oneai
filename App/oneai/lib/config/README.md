# Config Directory

This directory contains configuration files for the application:

- `assets.dart`: Manages asset paths and references for the application
- `dependencies.dart`: Handles dependency injection and service locator configuration using Provider/RepositoryProvider

## Dependency Injection

The `dependencies.dart` file configures the application's dependency graph using the Provider pattern from the flutter_bloc package. It defines:

- Shared providers used across all environments
- Environment-specific provider configurations

## Usage

The dependency providers are imported and used in the main application entry points:

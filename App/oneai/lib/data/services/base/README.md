# Base Services

This directory contains base service implementations that other services can extend:

- `base_long_init_service.dart`: Base class for services with lengthy initialization processes
- `example_long_init_service.dart`: Example implementation showing how to use BaseLongInitService

## BaseLongInitService

The `BaseLongInitService` provides a reusable pattern for services that require lengthy initialization processes. Key features:

- Handles concurrent initialization requests by awaiting the same initialization future
- Provides automatic initialization when service methods are called
- Implements proper error handling during initialization
- Exposes logging capabilities for child classes

### Usage

To implement a service with lengthy initialization:

1. Extend `BaseLongInitService`
2. Implement the abstract `performInitialization()` method with your initialization logic
3. Call `checkInitialization()` at the beginning of each method that requires initialization
4. Use the inherited `log` field for consistent logging

See `example_long_init_service.dart` for a complete working example.
# Services

This directory contains service implementations that interact with external systems:

- `api/`: API service implementations for making network requests
- `base/`: Base service classes that can be extended by other services
- `local/`: Local storage service implementations
- `model/`: Model service implementations
- `shared_preferences_service.dart`: Service for handling persistent preferences

Services are responsible for direct interaction with external data sources and systems.

## Base Service Classes

The `base/` directory contains reusable base classes for services:

- `BaseLongInitService`: A base class for services that require lengthy initialization processes. It handles concurrent initialization requests properly by awaiting the same initialization future.
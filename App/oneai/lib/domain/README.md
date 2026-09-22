# Domain Layer

This directory contains the core business logic and domain models of the application:

- `models/`: Data models representing business entities
  - Immutable data classes using freezed for immutability
  - Independent of UI and external frameworks
  - Represent core business concepts

- `use_cases/`: Business logic use cases that orchestrate operations
  - Single responsibility classes for specific business operations
  - Implement application-specific business rules
  - Orchestrate data flow between UI and data layers

## Architecture

The domain layer is the core of the application and:

1. Contains business rules and logic independent of external concerns
2. Defines interfaces (abstract classes) that are implemented by the data layer
3. Uses models to represent business entities and value objects
4. Communicates with the outside world through repository interfaces
5. Is independent of UI, frameworks, and external services

## Best Practices

- Keep domain models free of platform or framework dependencies
- Define clear interfaces for repositories that will be implemented in the data layer
- Use the Result type for error handling to maintain functional programming style
- Implement use cases as single-purpose classes following the Single Responsibility Principle
- Use sealed classes or enums for representing domain states and events
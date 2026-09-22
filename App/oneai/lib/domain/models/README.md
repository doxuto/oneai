# Models

This directory contains data models that represent the core business entities of the application.

Models define the structure and behavior of domain objects used throughout the app. They are:

- Immutable data classes
- Independent of any external frameworks or databases
- Used by use cases, repositories, and UI components

Each model is organized into its own directory and typically includes:
- The model class definition (`.dart`)
- Generated code for immutability via Freezed (`.freezed.dart`)

Models should represent domain concepts and contain minimal logic beyond validation and simple transformations.
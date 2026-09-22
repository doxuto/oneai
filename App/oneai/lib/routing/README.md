# Navigation and Routing

This directory contains the application's routing configuration using GoRouter, a declarative routing package for Flutter.

## Files Overview

- `routes.dart`: Defines route path constants for type-safe navigation across the application
- `router.dart`: Configures the GoRouter instance with route definitions, animations, and error handling

## Key Features

### Type-safe Navigation
- Centralized route constants prevent typos and make refactoring easier
- Helper methods for routes with parameters (e.g., `postDemoWithId(int id)`)
- IntelliSense support for route paths throughout the codebase

### Page Transitions and Animations
- Custom transitions for different navigation patterns
- Fade transitions for top-level navigation
- Slide transitions for detail views
- Scale transitions for modal dialogs
- All transitions managed by `PageAnimationManager`

### Deep Link Handling
- Support for external deep links
- URL pattern matching with GoRouter
- Parameter extraction from URLs

### Integration with BLoC
- Automatic injection of BLoCs during navigation
- Example: `DemoUserBloc` is created when navigating to the users route
- Repository dependencies automatically resolved via dependency injection

### Error Handling
- Custom error page for invalid routes
- User-friendly error messages with path information
- Easy navigation back to home

## Usage Examples

### Basic Navigation

Navigate to a named route:

```
// Navigate to home
context.go(Routes.home);

// Navigate to users
context.go(Routes.users);
```

### Navigation with Parameters

Navigate to a route with a path parameter:

```
// Navigate to a specific post detail
context.go(Routes.postDemoWithId(123));
```

### Navigation with Extra Data

Pass complex objects during navigation:

```
// Navigate to post detail with the post object
context.go(
  Routes.posts + '/${post.id}', 
  extra: post
);
```

### Handling Query Parameters

Access query parameters from the GoRouterState:

```
GoRoute(
  path: Routes.search,
  builder: (context, state) {
    final query = state.queryParameters['q'] ?? '';
    return SearchResultScreen(query: query);
  },
),
```

### Nested Navigation

For more complex UIs with nested navigation (not currently implemented):

```
ShellRoute(
  builder: (context, state, child) => ScaffoldWithNavBar(child: child),
  routes: [
    GoRoute(
      path: '/a',
      builder: (context, state) => const PageA(),
    ),
    GoRoute(
      path: '/b',
      builder: (context, state) => const PageB(),
    ),
  ],
),
```

## Extending the Router

To add new routes:

1. Define the route path constant in `routes.dart`
2. Add the route definition in `router.dart`
3. Choose appropriate transitions from `PageAnimationManager`
4. Configure any necessary BLoC providers

## Best Practices

- Always use the constants in `Routes` class instead of hardcoding paths
- Use `context.go()` for normal navigation and `context.push()` for stacked navigation
- Pass complex objects via the `extra` parameter
- Keep query parameters simple (strings, numbers, booleans)
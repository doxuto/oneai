import 'package:logging/logging.dart';

/// A base service class that handles long-running initialization
///
/// This class provides a reusable pattern for services that require
/// lengthy initialization processes, ensuring that concurrent initialization
/// requests are handled properly by awaiting the same initialization future.
abstract class BaseLongInitService {
  final Logger log;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  /// Creates a new instance with the specified logger name
  BaseLongInitService(String loggerName) : log = Logger(loggerName);

  /// Initializes the service
  ///
  /// This method must be called before using methods that require initialization.
  /// If initialization is already complete, it returns immediately.
  /// If initialization is in progress, it returns the existing initialization future.
  Future<void> initialize() async {
    if (_isInitialized) {
      log.info('$runtimeType already initialized');
      return;
    }

    // If initialization is already in progress, return the future
    if (_initializationFuture != null) {
      log.info('$runtimeType initialization already in progress, waiting...');
      return _initializationFuture;
    }

    log.info('Initializing $runtimeType');
    try {
      // Store the future so other calls can wait for it
      _initializationFuture = Future(() async {
        await performInitialization();
        _isInitialized = true;
        log.info('$runtimeType initialized successfully');
      });

      await _initializationFuture;
    } catch (e) {
      log.severe('Failed to initialize $runtimeType: $e');
      rethrow;
    }
  }

  /// Checks if the service is initialized before proceeding
  /// If not initialized, it will automatically call initialize()
  Future<void> checkInitialization() async {
    if (_isInitialized) {
      return;
    }

    if (_initializationFuture != null) {
      log.info('Waiting for $runtimeType initialization to complete');
      await _initializationFuture;
      return;
    }

    await initialize();
  }

  /// Implement this method in subclasses to perform the actual initialization work
  Future<void> performInitialization();
}

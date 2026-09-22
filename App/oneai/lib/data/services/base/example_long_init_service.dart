import 'package:codebase_ai/data/services/base/base_long_init_service.dart';
import 'package:codebase_ai/utils/result.dart';

/// Example service that demonstrates using the BaseLongInitService
///
/// This class shows how to implement a service that requires lengthy initialization
/// by extending the BaseLongInitService. It demonstrates proper usage of
/// the initialization pattern and how to ensure operations wait for initialization
/// before executing.
class ExampleLongInitService extends BaseLongInitService {
  /// Sample data that will be populated during initialization
  List<String> _data = [];

  /// Flag to simulate initialization error for testing
  final bool _simulateError;

  /// Creates a new ExampleLongInitService
  ///
  /// [simulateError] can be set to true to demonstrate error handling during initialization
  ExampleLongInitService({bool simulateError = false})
    : _simulateError = simulateError,
      super('ExampleLongInitService');

  @override
  Future<void> performInitialization() async {
    // Simulate a long initialization process (e.g., loading data from disk, network, etc.)
    log.info('Starting example initialization with heavy processing...');
    await Future.delayed(const Duration(seconds: 2));

    // Simulate potential initialization failure
    if (_simulateError) {
      throw Exception('Simulated initialization error');
    }

    // Populate data that will be used by the service
    _data = ['Item 1', 'Item 2', 'Item 3', 'Item 4', 'Item 5'];
    log.info('Data loaded with ${_data.length} items');
  }

  /// Gets all data items
  ///
  /// This method requires initialization to complete before it can be called.
  /// The checkInitialization() method ensures initialization happens before
  /// retrieving data.
  Future<Result<List<String>>> getAllData() async {
    try {
      await checkInitialization();
      log.info('Getting all data items');
      return Result.ok(_data);
    } on Exception catch (e) {
      log.warning('Error getting data: $e');
      return Result.error(e);
    }
  }

  /// Gets a specific data item by index
  ///
  /// This method requires initialization to complete before it can be called.
  /// The checkInitialization() method ensures initialization happens before
  /// retrieving data.
  Future<Result<String>> getDataItem(int index) async {
    try {
      await checkInitialization();
      log.info('Getting data item at index $index');

      if (index < 0 || index >= _data.length) {
        throw Exception('Index out of bounds: $index');
      }
      return Result.ok(_data[index]);
    } on Exception catch (e) {
      log.warning('Error getting data item: $e');
      return Result.error(e);
    }
  }

  /// Adds a new item to the data collection
  ///
  /// This method requires initialization to complete before it can be called.
  Future<Result<void>> addItem(String item) async {
    try {
      await checkInitialization();
      log.info('Adding new item: $item');
      _data.add(item);
      return const Result.ok(null);
    } on Exception catch (e) {
      log.warning('Error adding item: $e');
      return Result.error(e);
    }
  }
}

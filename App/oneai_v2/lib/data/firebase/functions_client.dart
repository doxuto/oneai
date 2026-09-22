import 'package:cloud_functions/cloud_functions.dart';
import 'package:one_ai/core/config/app_config.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/firebase/client_info.dart';

/// The single place callables are invoked. Repositories call through here and
/// never touch FirebaseFunctions directly, so error mapping cannot be skipped.
class FunctionsClient {
  FunctionsClient({required AppConfig config, FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: config.functionsRegion) {
    if (config.useEmulator) {
      _functions.useFunctionsEmulator(config.emulatorHost, 5001);
    }
  }

  final FirebaseFunctions _functions;
  ClientInfo? _clientInfo;

  /// Always `call<Map<String, dynamic>>` — never `call<SomeModel>()`, which is
  /// an unchecked cast that throws far from the call site.
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    final client = _clientInfo ??= await ClientInfo.current();
    try {
      final result = await _functions.httpsCallable(name).call<Map<String, dynamic>>({
        ...data,
        'client': client.toJson(),
      });
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw ApiFailure.fromFunctions(e);
    }
  }

  /// Streaming callable (used by `chat`). Yields each chunk's data, then the
  /// final result's data. cloud_functions ≥ 5.2: `ChunkResponse` / `ResultResponse`.
  Stream<Object?> stream(
    String name, [
    Map<String, Object?> data = const {},
  ]) async* {
    final client = _clientInfo ??= await ClientInfo.current();
    try {
      final response = _functions.httpsCallable(name).stream({
        ...data,
        'client': client.toJson(),
      });
      await for (final r in response) {
        switch (r) {
          case ChunkResponse(:final data):
            yield data;
          case ResultResponse(:final data):
            yield data;
        }
      }
    } on FirebaseFunctionsException catch (e) {
      throw ApiFailure.fromFunctions(e);
    }
  }
}

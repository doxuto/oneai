import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/models/user_models.dart';

/// Device registration for push. The client never writes `devices/`
/// itself; the server owns the token registry (docs/05 §2.5b).
class PushRepository {
  PushRepository({required FunctionsClient functions}) : _fns = functions;
  final FunctionsClient _fns;

  Future<void> registerDevice({required String token, String? locale}) =>
      _fns.call('registerDevice', {'token': token, if (locale != null) 'locale': locale});

  /// Call on sign-out so the next account on this phone does not get the
  /// previous one's pushes (the server also moves tokens on register).
  Future<void> unregisterDevice(String token) => _fns.call('unregisterDevice', {'token': token});

  Future<NotificationPrefs> updatePrefs({required bool transcriptionDone}) async {
    final j = await _fns.call('updateNotificationPrefs', {'transcriptionDone': transcriptionDone});
    return NotificationPrefs.fromJson(j['notifications'] as Map<String, dynamic>?);
  }
}

// The composition root. Everything that reaches outside the app is created
// here, once, and is overridable in tests (ProviderContainer.test /
// ProviderScope(overrides: …)). Nothing below the data layer imports Firebase.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/bootstrap.dart' show appConfigProvider;
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/data/repositories/minutes_repository.dart';
import 'package:one_ai/data/repositories/glossary_repository.dart';
import 'package:one_ai/data/repositories/tags_repository.dart';
import 'package:one_ai/data/repositories/transcription_repository.dart';
import 'package:one_ai/data/repositories/user_repository.dart';

export 'package:one_ai/bootstrap.dart' show appConfigProvider;

// ---- Firebase singletons ----

final firebaseAuthProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);
final firebaseStorageProvider = Provider<FirebaseStorage>((_) => FirebaseStorage.instance);

final functionsClientProvider = Provider<FunctionsClient>(
  (ref) => FunctionsClient(config: ref.watch(appConfigProvider)),
);

// ---- Auth ----

/// The signed-in Firebase user, or null. Drives the router redirect.
final authUserProvider = StreamProvider<User?>((ref) => ref.watch(firebaseAuthProvider).authStateChanges());

/// Convenience: uid when signed in. Throws if read while signed out — callers
/// that can run signed-out watch authUserProvider instead.
final currentUidProvider = Provider<String>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) throw StateError('currentUidProvider read while signed out');
  return user.uid;
});

// ---- Repositories ----

final minutesRepositoryProvider = Provider<MinutesRepository>(
  (ref) => MinutesRepository(functions: ref.watch(functionsClientProvider), firestore: ref.watch(firestoreProvider)),
);

final transcriptionRepositoryProvider = Provider<TranscriptionRepository>(
  (ref) => TranscriptionRepository(functions: ref.watch(functionsClientProvider), storage: ref.watch(firebaseStorageProvider)),
);

final tagsRepositoryProvider = Provider<TagsRepository>(
  (ref) => TagsRepository(functions: ref.watch(functionsClientProvider), firestore: ref.watch(firestoreProvider)),
);

final glossaryRepositoryProvider = Provider<GlossaryRepository>(
  (ref) => GlossaryRepository(functions: ref.watch(functionsClientProvider), firestore: ref.watch(firestoreProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(functions: ref.watch(functionsClientProvider), firestore: ref.watch(firestoreProvider)),
);

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(functions: ref.watch(functionsClientProvider)),
);

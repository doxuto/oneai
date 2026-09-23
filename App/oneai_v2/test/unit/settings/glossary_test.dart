import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/glossary_models.dart';
import 'package:one_ai/data/repositories/glossary_repository.dart';
import 'package:one_ai/features/settings/glossary_screen.dart';

class FakeGlossary implements GlossaryRepository {
  final calls = <String>[];
  Object? error;
  final ctl = StreamController<List<GlossaryTerm>>.broadcast();
  @override
  Stream<List<GlossaryTerm>> watch(String uid) => ctl.stream;
  @override
  Future<GlossaryTerm> upsert(String term, {String? hint}) async {
    calls.add('upsert:$term:${hint ?? ''}');
    if (error != null) throw error!;
    return GlossaryTerm(id: 'id', term: term, hint: hint, createdAt: DateTime(2026));
  }
  @override
  Future<void> delete(String termId) async {
    calls.add('delete:$termId');
    if (error != null) throw error!;
  }
}

void main() {
  test('add trims, skips blanks, sends the hint; failures surface as state', () async {
    final g = FakeGlossary();
    final c = ProviderContainer.test(overrides: [glossaryRepositoryProvider.overrideWithValue(g), currentUidProvider.overrideWithValue('u1')]);
    expect(await c.read(glossaryActionsProvider.notifier).add('   '), isFalse);
    expect(await c.read(glossaryActionsProvider.notifier).add('  VinFast ', hint: ' company '), isTrue);
    expect(g.calls, ['upsert:VinFast:company']);
    g.error = const TransientFailure('x');
    expect(await c.read(glossaryActionsProvider.notifier).add('Ana'), isFalse);
    expect(c.read(glossaryActionsProvider), isA<TransientFailure>());
    g.error = null;
    expect(await c.read(glossaryActionsProvider.notifier).remove('id'), isTrue);
    expect(c.read(glossaryActionsProvider), isNull);
  });

  test('fromJson / fromFirestore', () {
    final t = GlossaryTerm.fromJson({'id': 'a', 'term': 'X', 'hint': null, 'createdAt': '2026-09-24T00:00:00.000Z'});
    expect((t.id, t.term, t.hint), ('a', 'X', null));
    expect(GlossaryTerm.fromFirestore('b', {'term': 'Y', 'hint': 'h'}).hint, 'h');
  });
}

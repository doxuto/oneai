import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/transcription/incoming_share.dart';

void main() {
  test('pending shares hand out one file at a time, in order', () {
    final c = ProviderContainer.test();
    final n = c.read(pendingIncomingSharesProvider.notifier);
    expect(n.takeFirst(), isNull);
    n.addAll(const [IncomingShare(path: '/a.m4a'), IncomingShare(path: '/b.m4a')]);
    expect(c.read(pendingIncomingSharesProvider).length, 2);
    expect(n.takeFirst()?.path, '/a.m4a');
    expect(c.read(pendingIncomingSharesProvider).length, 1);
    expect(n.takeFirst()?.path, '/b.m4a');
    expect(n.takeFirst(), isNull);
  });
}

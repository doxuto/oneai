import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/firebase/json_read.dart';

void main() {
  group('readDouble survives an int on the wire', () {
    test('int becomes double', () {
      expect(readDouble(<String, dynamic>{'x': 3}, 'x'), 3.0);
    });
    test('double stays double', () {
      expect(readDouble(<String, dynamic>{'x': 3.5}, 'x'), 3.5);
    });
    test('a string is null, not a crash', () {
      expect(readDouble(<String, dynamic>{'x': '3'}, 'x'), isNull);
    });
  });

  group('readDateTime expects ISO-8601', () {
    test('parses the server format', () {
      final d = readDateTime(<String, dynamic>{'at': '2026-09-22T08:41:12.345Z'}, 'at');
      expect(d, isNotNull);
      expect(d!.toUtc().year, 2026);
      expect(d.toUtc().month, 9);
    });
    test("v1's {_seconds,_nanoseconds} is no longer accepted", () {
      final d = readDateTime(<String, dynamic>{
        'at': <String, dynamic>{'_seconds': 1790000000, '_nanoseconds': 0},
      }, 'at');
      expect(d, isNull);
    });
  });

  group('lists', () {
    test('readStringList drops non-strings instead of throwing', () {
      expect(readStringList(<String, dynamic>{'xs': <dynamic>['a', 1, 'b']}, 'xs'), <String>['a', 'b']);
    });
    test('readObjectList returns typed maps', () {
      final out = readObjectList(<String, dynamic>{
        'xs': <dynamic>[
          <dynamic, dynamic>{'a': 1},
        ],
      }, 'xs');
      expect(out, hasLength(1));
      expect(out.first['a'], 1);
    });
    test('a missing key is an empty list, not null', () {
      expect(readStringList(<String, dynamic>{}, 'nope'), isEmpty);
    });
  });

  group('readEnum is tolerant', () {
    test('known value decodes', () {
      expect(
        readEnum(<String, dynamic>{'s': 'ready'}, 's', <String, int>{'ready': 1}, 0),
        1,
      );
    });
    test('a value a newer server added falls back', () {
      expect(
        readEnum(<String, dynamic>{'s': 'brand_new'}, 's', <String, int>{'ready': 1}, 0),
        0,
      );
    });
  });
}

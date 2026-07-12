// driver_access_test.dart
//
// Unit tests (no database) for the DriverAccess layer added in the
// `performace` branch. Focuses on the pure COPY-text row formatting and the
// null-capability path.

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() {
  group('DriverAccess.formatCopyTextRow', () {
    test('simple tab-delimited row', () {
      expect(
        DriverAccess.formatCopyTextRow([1, 'abc', true]),
        equals('1\tabc\ttrue\n'),
      );
    });

    test('null becomes the null token', () {
      expect(
        DriverAccess.formatCopyTextRow(['a', null, 'b']),
        equals('a\t\\N\tb\n'),
      );
    });

    test('escapes tab, newline, carriage-return and backslash', () {
      expect(
        DriverAccess.formatCopyTextRow(['a\tb', 'c\nd', 'e\\f', 'g\rh']),
        equals('a\\tb\tc\\nd\te\\\\f\tg\\rh\n'),
      );
    });

    test('custom null string', () {
      expect(
        DriverAccess.formatCopyTextRow(['x', null], nullString: 'NULL'),
        equals('x\tNULL\n'),
      );
    });

    test('custom delimiter is escaped when present in values', () {
      expect(
        DriverAccess.formatCopyTextRow(['a,b', 'c'], delimiter: ','),
        equals('a\\,b,c\n'),
      );
    });

    test('empty row yields just newline', () {
      expect(DriverAccess.formatCopyTextRow([]), equals('\n'));
    });
  });

  group('driver() capability probe', () {
    test('FakeConnection.driver() returns null (no driver access)', () {
      final conn = FakeConnection();
      final qb = QueryBuilder(conn, QueryPostgresGrammar(), Processor())
          .from('t');
      expect(conn.driver(), isNull);
      expect(qb.driver(), isNull);
    });
  });
}

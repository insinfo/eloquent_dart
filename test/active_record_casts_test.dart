import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

enum Situacao { ativa, arquivada }

void main() {
  test('boolean', () {
    expect(Casts.boolean.fromDatabase(1), isTrue);
    expect(Casts.boolean.fromDatabase(0), isFalse);
    expect(Casts.boolean.fromDatabase('t'), isTrue);
    expect(Casts.boolean.fromDatabase(true), isTrue);
    expect(Casts.boolean.fromDatabase(null), isNull);
  });

  test('numbers and dates', () {
    expect(Casts.integer.fromDatabase('42'), 42);
    expect(Casts.integer.fromDatabase(BigInt.from(7)), 7);
    expect(Casts.decimal.fromDatabase('10.50'), 10.5);
    expect(Casts.dateTime.fromDatabase('2026-03-10T12:00:00Z'),
        DateTime.utc(2026, 3, 10, 12));
  });

  test('json and enum', () {
    expect(Casts.json.fromDatabase('{"a":1}'), {'a': 1});
    expect(Casts.json.fromDatabase({'a': 1}), {'a': 1});
    expect(Casts.json.toDatabase({'a': 1}), '{"a":1}');
    final cast = Casts.enumByName(Situacao.values);
    expect(cast.fromDatabase('arquivada'), Situacao.arquivada);
    expect(cast.toDatabase(Situacao.ativa), 'ativa');
    // Values from Model.toMap() are already Dart values.
    expect(cast.fromDatabase(Situacao.ativa), Situacao.ativa);
    expect(Casts.boolean.fromDatabase(false), isFalse);
    expect(Casts.decimal.fromDatabase(2.5), 2.5);
    expect(() => cast.fromDatabase('x'), throwsArgumentError);
  });
}

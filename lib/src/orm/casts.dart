part of 'active_record.dart';

/// Converts a column between its database value and its Dart value.
abstract class AttributeCast<T> {
  const AttributeCast();

  /// The Dart value of a database value (`null` stays `null`).
  T? fromDatabase(Object? value);

  /// The value written to the database.
  Object? toDatabase(Object? value);
}

/// Built-in casts.
abstract final class Casts {
  /// `bool`; MySQL `tinyint` 0/1 and strings `'t'`/`'1'`/`'true'` included.
  static const AttributeCast<bool> boolean = _BoolCast();

  /// `int` from `int`, `BigInt` or numeric text.
  static const AttributeCast<int> integer = _IntCast();

  /// `double` from numbers or numeric text (PostgreSQL `numeric` is read
  /// as text by the postgres/dargres adapters to keep its precision).
  static const AttributeCast<double> decimal = _DoubleCast();

  /// `DateTime` from `DateTime` or ISO-8601 text.
  static const AttributeCast<DateTime> dateTime = _DateTimeCast();

  /// JSON object/array: text is decoded on read and values are encoded as
  /// JSON text on write.
  static const AttributeCast<Object> json = _JsonCast();

  /// An enum stored by name.
  static AttributeCast<E> enumByName<E extends Enum>(List<E> values) =>
      _EnumCast<E>(values);
}

final class _BoolCast extends AttributeCast<bool> {
  const _BoolCast();

  @override
  bool? fromDatabase(Object? value) => switch (value) {
        null => null,
        bool b => b,
        num n => n != 0,
        String s =>
          const {'1', 't', 'true', 'y', 'yes'}.contains(s.trim().toLowerCase()),
        _ => throw FormatException('Not a boolean: $value'),
      };

  @override
  Object? toDatabase(Object? value) => value;
}

final class _IntCast extends AttributeCast<int> {
  const _IntCast();

  @override
  int? fromDatabase(Object? value) => switch (value) {
        null => null,
        int i => i,
        BigInt b => b.toInt(),
        num n => n.toInt(),
        String s => int.parse(s),
        _ => throw FormatException('Not an integer: $value'),
      };

  @override
  Object? toDatabase(Object? value) => value;
}

final class _DoubleCast extends AttributeCast<double> {
  const _DoubleCast();

  @override
  double? fromDatabase(Object? value) => switch (value) {
        null => null,
        num n => n.toDouble(),
        String s => double.parse(s),
        _ => throw FormatException('Not a number: $value'),
      };

  @override
  Object? toDatabase(Object? value) => value;
}

final class _DateTimeCast extends AttributeCast<DateTime> {
  const _DateTimeCast();

  @override
  DateTime? fromDatabase(Object? value) => switch (value) {
        null => null,
        DateTime d => d,
        String s => DateTime.parse(s),
        _ => throw FormatException('Not a date/time: $value'),
      };

  @override
  Object? toDatabase(Object? value) => value;
}

final class _JsonCast extends AttributeCast<Object> {
  const _JsonCast();

  @override
  Object? fromDatabase(Object? value) =>
      value is String ? jsonDecode(value) : value;

  @override
  Object? toDatabase(Object? value) =>
      value == null || value is String ? value : jsonEncode(value);
}

final class _EnumCast<E extends Enum> extends AttributeCast<E> {
  const _EnumCast(this.values);

  final List<E> values;

  @override
  E? fromDatabase(Object? value) =>
      value == null ? null : values.byName(value.toString());

  @override
  Object? toDatabase(Object? value) => value is Enum ? value.name : value;
}

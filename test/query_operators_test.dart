// An operator goes into the SQL as it is, so every clause must refuse what is not
// one, without refusing the ones people use, or their own.
import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:test/test.dart';

import 'helper.dart';

/// SQL that works if it goes in as an operator: it keeps the one placeholder.
const _evil = '= 0 or 1=1 or 1 =';

void main() {
  late FakeConnection conn;
  late QueryPostgresGrammar pgGrammar;
  late QueryMySqlGrammar myGrammar;
  QueryBuilder pg() => QueryBuilder(conn, pgGrammar, Processor());
  QueryBuilder my() => QueryBuilder(conn, myGrammar, Processor());

  setUp(() {
    conn = FakeConnection();
    pgGrammar = QueryPostgresGrammar();
    myGrammar = QueryMySqlGrammar();
  });

  /// Every clause that takes an operator, with [operator] in it.
  Map<String, QueryBuilder Function(QueryBuilder)> clauses(String operator) => {
        'where': (q) => q.where('a', operator, 1),
        'orWhere': (q) => q.orWhere('a', operator, 1),
        'whereNot': (q) => q.whereNot('a', operator, 1),
        'orWhereNot': (q) => q.orWhereNot('a', operator, 1),
        'whereAny': (q) => q.whereAny(['a', 'b'], operator, 1),
        'orWhereAny': (q) => q.orWhereAny(['a', 'b'], operator, 1),
        'whereAll': (q) => q.whereAll(['a', 'b'], operator, 1),
        'orWhereAll': (q) => q.orWhereAll(['a', 'b'], operator, 1),
        'whereFlex': (q) => q.whereFlex('a', operator, 1),
        'orWhereFlex': (q) => q.orWhereFlex('a', operator, 1),
        'whereColumn': (q) => q.whereColumn('a', operator, 'b'),
        'orWhereColumn': (q) => q.orWhereColumn('a', operator, 'b'),
        'whereColumn with a list': (q) => q.whereColumn([
              ['a', operator, 'b']
            ]),
        'whereSub': (q) => q.where('a', operator, (QueryBuilder s) => s),
        'whereSubFlex': (q) =>
            q.whereSubFlex('a', operator, (QueryBuilder s) => s, 'and'),
        'having': (q) => q.having('a', operator, 1),
        'orHaving': (q) => q.orHaving('a', operator, 1),
        'join': (q) => q.join('b', 'b.id', operator, 'a.id'),
        'leftJoin': (q) => q.leftJoin('b', 'b.id', operator, 'a.id'),
        'joinWhere': (q) => q.joinWhere('b', 'b.id', operator, 1),
        'join with a function': (q) =>
            q.join('b', (JoinClause j) => j.on('b.id', operator, 'a.id')),
        'join where': (q) =>
            q.join('b', (JoinClause j) => j.where('b.id', operator, 1)),
        'whereDate': (q) => q.whereDate('a', operator, DateTime.utc(2024)),
        'whereTime': (q) => q.whereTime('a', operator, '12:00'),
        'whereDay': (q) => q.whereDay('a', operator, 1),
        'whereMonth': (q) => q.whereMonth('a', operator, 1),
        'whereYear': (q) => q.whereYear('a', operator, 2024),
        'whereJsonLength': (q) => q.whereJsonLength('a', operator, 1),
      };

  group('an operator that is SQL is refused', () {
    for (final name in clauses(_evil).keys) {
      for (final operator in [
        _evil,
        "= '1' OR 1=1 --",
        '= 1; drop table t',
        '=/**/',
        '= ?',
        'like or',
        '',
      ]) {
        test('$name: $operator', () {
          for (final builder in [pg, my]) {
            expect(() => clauses(operator)[name]!(builder().from('t')).toSql(),
                throwsArgumentError);
          }
        });
      }
    }

    test('the message tells how to add an operator', () {
      expect(
          () => pg().from('t').where('a', '<==>', 1),
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, 'message', contains('custom_operators'))
              .having((e) => e.invalidValue, 'value', '<==>')));
    });

    test('an operator that is not a string', () {
      expect(() => pg().from('t').where('a', 1, 2), throwsArgumentError);
      expect(() => pg().from('t').where('a', null, 2), throwsArgumentError);
    });
  });

  group('known operators still work', () {
    test('as they were written', () {
      expect(pg().from('t').where('a', 'ILIKE', 'x').toSql(),
          'select * from "t" where "a" ILIKE ?');
      expect(pg().from('t').where('a', 'not   like', 'x').toSql(),
          'select * from "t" where "a" not   like ?');
      expect(pg().from('t').where('a', ' = ', 1).toSql(),
          'select * from "t" where "a"  =  ?');
    });

    test('on PostgreSQL', () {
      for (final operator in [
        // Comparison.
        '=', '<>', '!=', '<', '>', '<=', '>=', 'is distinct from',
        'is not distinct from',
        // Math and bits.
        '+', '-', '*', '/', '%', '^', '|/', '||/', '@', '&', '|', '#', '~',
        '<<', '>>',
        // Text.
        '||', 'like', 'not like', 'ilike', 'not ilike', '~~', '!~~', '~~*',
        '!~~*', '~*', '!~', '!~*', 'similar to', 'not similar to', '^@',
        // JSON.
        '->', '->>', '#>', '#>>', '@>', '<@', '#-', '@@',
        // Geometry, ranges and networks.
        '##', '&&', '<->', '-|-', '&<', '&>', '<<=', '>>=', '~=', '@-@',
      ]) {
        expect(pg().from('t').where('a', operator, 1).toSql(),
            'select * from "t" where "a" $operator ?');
      }
    });

    test('on MySQL', () {
      for (final operator in [
        '=',
        '<=>',
        '!=',
        '<>',
        'like',
        'not like',
        'like binary',
        'not like binary',
        'rlike',
        'not rlike',
        'regexp',
        'not regexp',
        'sounds like',
        '&',
        '|',
        '^',
        '<<',
        '>>',
      ]) {
        expect(my().from('t').where('a', operator, 1).toSql(),
            'select * from `t` where `a` $operator ?');
      }
    });

    test('with a raw value and with no value', () {
      expect(pg().from('t').where('a', 'is', QueryExpression('true')).toSql(),
          'select * from "t" where "a" is true');
      expect(pg().from('t').where('a', '=', null).toSql(),
          'select * from "t" where "a" is null');
      expect(pg().from('t').where('a', '!=', null).toSql(),
          'select * from "t" where "a" is not null');
      expect(pg().from('t').where('a', 1).toSql(),
          'select * from "t" where "a" = ?');
    });

    test('whereFlex with two arguments reads the same values as before', () {
      for (final value in ['+', '*', '/', '%', '@', 'IS', 'is not', 'not in']) {
        final q = pg().from('t').whereFlex('a', value);
        expect(q.toSql(), 'select * from "t" where "a" = ?', reason: value);
        expect(q.getBindings(), [value]);
      }
      expect(pg().from('t').whereFlex('a', '=').toSql(),
          'select * from "t" where "a" is null');
      expect(pg().from('t').whereFlex('a', '!=').toSql(),
          'select * from "t" where "a" is not null');
      expect(() => pg().from('t').whereFlex('a', '>'), throwsArgumentError);
    });

    test('~* and !~* are what their constants say', () {
      expect(SqlOperator.postgresRegexAll, '~*');
      expect(SqlOperator.postgresNotRegexAll, '!~*');
      expect(pg().from('t').whereFlex('a', '~*', 'x').toSql(),
          'select * from "t" where "a" ~* ?');
    });

    test('a join by its own helpers', () {
      final sql = pg().from('t').join('b', (JoinClause j) {
        j.on('b.id', '=', 't.id');
        j.whereNull('b.x');
        j.whereNotNull('b.y');
        j.whereIn('b.z', [1, 2]);
        j.whereNotIn('b.w', [3]);
      }).toSql();
      expect(
          sql,
          'select * from "t" inner join "b" on "b"."id" = "t"."id" '
          'and "b"."x" is null and "b"."y" is not null '
          'and "b"."z" in (?, ?) and "b"."w" not in (?)');
      expect(pg().from('t').join('b', (JoinClause j) => j.onTrue()).toSql(),
          'select * from "t" inner join "b" on TRUE');
    });

    test('whereColumn with two arguments is a = b', () {
      expect(pg().from('t').whereColumn('a', 'b').toSql(),
          'select * from "t" where "a" = "b"');
      // A column may have the name of an operator.
      expect(pg().from('t').whereColumn('a', 'is').toSql(),
          'select * from "t" where "a" = "is"');
      // An unknown operator with three arguments used to drop the third.
      expect(
          () => pg().from('t').whereColumn('a', 'b', 'c'), throwsArgumentError);
    });
  });

  group('MySQL and comments', () {
    test('# starts a comment there, and is an operator on PostgreSQL', () {
      expect(() => my().from('t').where('a', '#', 1), throwsArgumentError);
      expect(() => my().from('t').where('a', '#-', 1), throwsArgumentError);
      expect(pg().from('t').where('a', '#', 1).toSql(),
          'select * from "t" where "a" # ?');
    });
  });

  group('operators of your own', () {
    test('every clause accepts them', () {
      pgGrammar.addCustomOperators(['===']);
      for (final entry in clauses('===').entries) {
        final sql = entry.value(pg().from('t')).toSql();
        expect(sql, contains(' === '), reason: entry.key);
      }
    });

    test('whereSqlOperator accepts them too', () {
      expect(() => pgGrammar.addCustomOperators(['===']), returnsNormally);
      final q = QueryBuilder2.using(pg, 't');
      expect(q.whereSqlOperator('a', '===', 1).toSql(),
          'select * from "t" where "a" === ?');
    });

    test('they do not reach other grammars, and the others stay refused', () {
      pgGrammar.addCustomOperators(['===']);
      expect(() => my().from('t').where('a', '===', 1), throwsArgumentError);
      expect(
          () => QueryBuilder(conn, QueryPostgresGrammar(), Processor())
              .from('t')
              .where('a', '===', 1),
          throwsArgumentError);
      expect(() => pg().from('t').where('a', '====', 1), throwsArgumentError);
      expect(() => pg().from('t').where('a', _evil, 1), throwsArgumentError);
    });

    test('symbols, qualified, in words, ignoring case', () {
      pgGrammar.addCustomOperators([
        '<=>~',
        'OPERATOR(geo.<->)',
        'operator( "My Schema".public.=~= )',
        'near TO',
      ]);
      for (final operator in [
        '<=>~',
        'OPERATOR(geo.<->)',
        'operator(geo.<->)',
        'near to',
        'NEAR   TO',
      ]) {
        expect(pg().from('t').where('a', operator, 1).toSql(),
            'select * from "t" where "a" $operator ?');
      }
      expect(pgGrammar.customOperators, contains('operator(geo.<->)'));
    });

    test('what is not an operator cannot be added', () {
      for (final operator in [
        '',
        ' ',
        '--',
        '=--',
        '/*',
        '=/*',
        "='",
        '=;',
        '= 1',
        '=1',
        '?',
        '?=',
        '@?',
        'a;b',
        "a'b",
        'a--b',
        'a b;',
        '(a)',
        'operator(geo.?)',
        'operator(geo.--)',
        'operator(geo.= or 1=1)',
        'operator(a b.+)',
        'operator(+) or 1=1',
      ]) {
        expect(
            () => pgGrammar.addCustomOperators([operator]), throwsArgumentError,
            reason: operator);
      }
      expect(pgGrammar.customOperators, isEmpty);
    });

    test('one bad operator adds none', () {
      expect(() => pgGrammar.addCustomOperators(['===', '--']),
          throwsArgumentError);
      expect(pgGrammar.customOperators, isEmpty);
    });

    test('# cannot be added on MySQL, where it starts a comment', () {
      expect(() => myGrammar.addCustomOperators(['#']), throwsArgumentError);
      expect(() => myGrammar.addCustomOperators(['<#>']), throwsArgumentError);
      expect(() => myGrammar.addCustomOperators(['operator(a.#)']),
          throwsArgumentError);
      myGrammar.addCustomOperators(['sounds alike']);
      pgGrammar.addCustomOperators(['<#>']);
    });
  });

  group('operators with ? on PostgreSQL', () {
    test('compile to their functions, with one binding', () {
      for (final (operator, function, value) in [
        ('?', 'jsonb_exists', 'k'),
        ('?|', 'jsonb_exists_any', ['a', 'b']),
        ('?&', 'jsonb_exists_all', ['a', 'b']),
        ('@?', 'jsonb_path_exists_opr', r'$.a'),
      ]) {
        final q = pg().from('t').where('data', operator, value);
        expect(q.toSql(), 'select * from "t" where $function("data", ?)');
        expect(q.getBindings(), [value]);
      }
      expect(pg().from('t').whereFlex('data', '?', 'k').toSql(),
          'select * from "t" where jsonb_exists("data", ?)');
    });

    test('whereSqlOperator compiles them too', () {
      expect(
          QueryBuilder2.using(pg, 't')
              .whereSqlOperator('data', '?', 'k')
              .toSql(),
          'select * from "t" where jsonb_exists("data", ?)');
    });

    test('other clauses refuse them, as ? would be a placeholder', () {
      for (final name in [
        'whereColumn',
        'having',
        'join',
        'joinWhere',
        'whereDate',
        'whereJsonLength',
        'whereSub',
      ]) {
        expect(() => clauses('?')[name]!(pg().from('t')).toSql(),
            throwsArgumentError,
            reason: name);
      }
    });

    test('the geometric ones, and MySQL, refuse them', () {
      for (final operator in ['?#', '?-', '?-|', '?||']) {
        expect(
            () => pg().from('t').where('a', operator, 1),
            throwsA(isA<ArgumentError>()
                .having((e) => e.message, 'message', contains('whereRaw'))));
      }
      for (final operator in ['?', '?|', '?&', '@?']) {
        expect(
            () => my().from('t').where('a', operator, 1), throwsArgumentError);
      }
    });
  });

  group('a JSON selector cannot end its string', () {
    test('a quote on PostgreSQL', () {
      final q = pg().from('t').where("data->x' is null or 1=1 or 'a", 'v');
      expect(q.toSql(),
          'select * from "t" where "data"->>\'x\'\' is null or 1=1 or \'\'a\' = ?');
    });

    test('at every level, also in order by and select', () {
      expect(pg().from('t').where("data->x'->y'", 'v').toSql(),
          'select * from "t" where "data"->\'x\'\'\'->>\'y\'\'\' = ?');
      expect(pg().from('t').orderBy("data->x'").toSql(),
          'select * from "t" order by "data"->>\'x\'\'\' asc');
      expect(pg().from('t').select(["data->x'"]).toSql(),
          'select "data"->>\'x\'\'\' from "t"');
    });

    test('a double quote on MySQL', () {
      expect(my().from('t').where('data->x" or 1=1 or "a', 'v').toSql(),
          'select * from `t` where `data`->"\$.x"" or 1=1 or ""a" = ?');
    });

    test('a backslash on MySQL does not unescape the quote', () {
      expect(my().from('t').where(r'data->x\" or 1=1 or \"a', 'v').toSql(),
          r'select * from `t` where `data`->"$.x\\"" or 1=1 or \\""a" = ?');
    });

    test('whereJsonContains on MySQL', () {
      expect(
          my().from('t').whereJsonContains(r"data->a\') or 1=1 #", 'v').toSql(),
          r'''select * from `t` where json_contains(`data`, ?, '$."a\\'''
          r"""'') or 1=1 #"')""");
    });

    test('the plain selectors are unchanged', () {
      expect(pg().from('t').where('data->a->b', 'v').toSql(),
          'select * from "t" where "data"->\'a\'->>\'b\' = ?');
      expect(my().from('t').where('data->a->b', 'v').toSql(),
          'select * from `t` where `data`->"\$.a.b" = ?');
      expect(my().from('t').whereJsonContains('data->a->b', 'v').toSql(),
          'select * from `t` where json_contains(`data`, ?, \'\$."a"."b"\')');
    });
  });
}

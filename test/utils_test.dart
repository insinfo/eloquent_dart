import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  group('utils', () {
    test('implode', () {
      var array = ['lastname', 'email', 'phone'];
      var commaSeparated = Utils.implode(',', array);
      expect(commaSeparated, equals('lastname,email,phone'));
    });

    test('explode', () {
      var pizzas = 'piece1 piece2 piece3 piece4 piece5 piece6';
      var pieces = Utils.explode(" ", pizzas);
      expect(pieces[0], equals('piece1'));
    });

    test('strpos', () {
      var mystring = 'abc';
      var findme = 'a';
      var pos = Utils.strpos(mystring, findme);
      expect(pos, equals(0));
    });

    test('strReplace', () {
      var bodytag = Utils.strReplace("%body%", "black", "<body text='%body%'>");
      expect(bodytag, equals("<body text='black'>"));
    });
  });

  group('Utils Tests', () {
    test('toSnakeCase', () {
      expect(Utils.toSnakeCase('CamelCaseString'), equals('camel_case_string'));
      expect(Utils.toSnakeCase('simpleTest'), equals('simple_test'));
      expect(Utils.toSnakeCase('already_snake'), equals('already_snake'));
    });

    test('arrayMap', () {
      var input = [1, 2, 3];
      var output = Utils.arrayMap((x) => x * 2, input);
      expect(output, equals([2, 4, 6]));
    });

    test('arrayFilter', () {
      var input = [1, 2, 3, 4, 5];
      var output = Utils.arrayFilter(input, (x) => x % 2 == 0);
      expect(output, equals([2, 4]));
    });

    test('inArray', () {
      var input = [1, 'teste', true];
      expect(Utils.inArray(1, input), isTrue);
      expect(Utils.inArray('teste', input), isTrue);
      expect(Utils.inArray(false, input), isFalse);
    });

    test('implode', () {
      var input = ['a', 'b', 'c'];
      expect(Utils.implode(',', input), equals('a,b,c'));
    });

    test('strReplace', () {
      expect(Utils.strReplace('world', 'Dart', 'Hello world!'),
          equals('Hello Dart!'));
      // Teste com array
      expect(Utils.strReplace(['a', 'e'], 'X', 'banana'), equals('bXnXnX'));
    });

    test('isString', () {
      expect(Utils.isString('abc'), isTrue);
      expect(Utils.isString(123), isFalse);
    });

    test('explode', () {
      // sem limit
      expect(Utils.explode('.', 'a.b.c'), equals(['a', 'b', 'c']));
      // with a limit, the last piece keeps the rest (PHP semantics)
      expect(Utils.explode('.', 'a.b.c', 2), equals(['a', 'b.c']));
    });

    test('count', () {
      expect(Utils.count([1, 2, 3]), equals(3));
    });

    test('explodePluckParameters', () {
      // valueP e keyP como strings
      var result = Utils.explodePluckParameters('people.id', 'people.name');
      // Esperamos que vire [['people','id'], ['people','name']]
      expect(result[0], equals(['people', 'id']));
      expect(result[1], equals(['people', 'name']));

      // valueP como lista, keyP como nulo
      result = Utils.explodePluckParameters(['id'], null);
      expect(result[0], equals(['id']));
      expect(result[1], isNull);

      // keyP string
      result = Utils.explodePluckParameters(['id'], 'name');
      expect(result[0], equals(['id']));
      expect(result[1], equals(['name']));
    });

    group('dataGet / arrayGet / arrayExists', () {
      final sample = {
        'id': 1,
        'name': 'John',
        'address': {'city': 'Gotham', 'zip': 12345},
      };

      test('arrayExists - Map', () {
        expect(Utils.arrayExists(sample, 'id'), isTrue);
        expect(Utils.arrayExists(sample, 'foo'), isFalse);
      });

      test('arrayExists - List', () {
        var arr = [10, 20, 30];
        // chave int
        expect(Utils.arrayExists(arr, 1), isTrue); // arr[1] = 20
        expect(Utils.arrayExists(arr, 10), isFalse);
      });

      test('arrayGet - simples', () {
        expect(Utils.arrayGet(sample, 'id'), equals(1));
        // Dot notation, as Arr::get.
        expect(Utils.arrayGet(sample, 'address.city'), equals('Gotham'));
        expect(Utils.arrayGet(sample, 'address.country'), isNull);
      });

      test('dataGet - busca aninhada (dot notation)', () {
        expect(Utils.dataGet(sample, 'id'), equals(1));
        expect(Utils.dataGet(sample, 'address.city'), equals('Gotham'));
        expect(Utils.dataGet(sample, 'address.zip'), equals(12345));
        expect(Utils.dataGet(sample, 'address.country'), isNull);
      });
    });

    group('arrayPluck', () {
      test('arrayPluck sem key', () {
        var array = [
          {'id': 1, 'name': 'Isaque'},
          {'id': 2, 'name': 'John'},
          {'id': 3, 'name': 'Jane'}
        ];
        var result = Utils.arrayPluck(array, 'name');
        expect(result, equals(['Isaque', 'John', 'Jane']));
      });

      test('arrayPluck com key', () {
        var array = [
          {'id': 1, 'name': 'Isaque'},
          {'id': 2, 'name': 'John'},
          {'id': 3, 'name': 'Jane'}
        ];
        var result = Utils.arrayPluck(array, 'name', 'id');
        expect(result, equals({1: 'Isaque', 2: 'John', 3: 'Jane'}));
      });

      test('arrayPluck: an item without the key is keyed by null', () {
        var array = [
          {'id': 1, 'name': 'Isaque'},
          // No 'id' here.
          {'ID': 2, 'name': 'John'},
        ];
        var result = Utils.arrayPluck(array, 'name', 'id');
        expect(result, equals({1: 'Isaque', null: 'John'}));
      });
    });

    test('trim', () {
      expect(Utils.trim('  hello  '), equals('hello'));
    });

    test('substr', () {
      // offset positivo
      expect(Utils.substr('abcdef', 1, 3), equals('bcd'));
      // offset negativo
      expect(Utils.substr('abcdef', -2, 10), equals('ef'));
    });

    test('formatDate', () {
      var dt = DateTime(2023, 5, 15);
      expect(Utils.formatDate(dt), equals('2023-05-15'));
      expect(Utils.formatDate(dt, 'dd/MM/yyyy'), equals('15/05/2023'));
    });

    test('arrayFill', () {
      expect(Utils.arrayFill(0, 3, 'x'), equals(['x', 'x', 'x']));
    });

    test('arrayMerge', () {
      expect(Utils.arrayMerge([1, 2], [3, 4]), equals([1, 2, 3, 4]));
    });

    test('mapMergeSd', () {
      var map1 = {'driver': 'pgsql', 'host': 'localhost'};
      var map2 = {'host': '127.0.0.1', 'port': 5432};
      var merged = Utils.mapMergeSd(map1, map2);
      // Esperamos que host seja '127.0.0.1' (sobrescrito) e inclua 'port'
      expect(merged,
          equals({'driver': 'pgsql', 'host': '127.0.0.1', 'port': 5432}));
    });
  });
}

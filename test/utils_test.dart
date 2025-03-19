import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  group('utils', () {
    test('implode', () {
      var array = ['lastname', 'email', 'phone'];
      var comma_separated = Utils.implode(',', array);
      expect(comma_separated, equals('lastname,email,phone'));
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

    test('str_replace', () {
      var bodytag =
          Utils.str_replace("%body%", "black", "<body text='%body%'>");
      expect(bodytag, equals("<body text='black'>"));
    });
  });

  group('Utils Tests', () {
    test('toSnakeCase', () {
      expect(Utils.toSnakeCase('CamelCaseString'), equals('camel_case_string'));
      expect(Utils.toSnakeCase('simpleTest'), equals('simple_test'));
      expect(Utils.toSnakeCase('already_snake'), equals('already_snake'));
    });

    test('array_map', () {
      var input = [1, 2, 3];
      var output = Utils.array_map((x) => x * 2, input);
      expect(output, equals([2, 4, 6]));
    });

    test('array_filter', () {
      var input = [1, 2, 3, 4, 5];
      var output = Utils.array_filter(input, (x) => x % 2 == 0);
      expect(output, equals([2, 4]));
    });

    test('in_array', () {
      var input = [1, 'teste', true];
      expect(Utils.in_array(1, input), isTrue);
      expect(Utils.in_array('teste', input), isTrue);
      expect(Utils.in_array(false, input), isFalse);
    });

    test('implode', () {
      var input = ['a', 'b', 'c'];
      expect(Utils.implode(',', input), equals('a,b,c'));
    });

    test('str_replace', () {
      expect(Utils.str_replace('world', 'Dart', 'Hello world!'),
          equals('Hello Dart!'));
      // Teste com array
      expect(Utils.str_replace(['a', 'e'], 'X', 'banana'), equals('bXnXnX'));
    });

    test('is_string', () {
      expect(Utils.is_string('abc'), isTrue);
      expect(Utils.is_string(123), isFalse);
    });

    test('explode', () {
      // sem limit
      expect(Utils.explode('.', 'a.b.c'), equals(['a', 'b', 'c']));
      // com limit
      expect(Utils.explode('.', 'a.b.c', 2), equals(['a', 'b']));
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

    group('data_get / array_get / array_exists', () {
      final sample = {
        'id': 1,
        'name': 'John',
        'address': {'city': 'Gotham', 'zip': 12345},
      };

      test('array_exists - Map', () {
        expect(Utils.array_exists(sample, 'id'), isTrue);
        expect(Utils.array_exists(sample, 'foo'), isFalse);
      });

      test('array_exists - List', () {
        var arr = [10, 20, 30];
        // chave int
        expect(Utils.array_exists(arr, 1), isTrue); // arr[1] = 20
        expect(Utils.array_exists(arr, 10), isFalse);
      });

      test('array_get - simples', () {
        expect(Utils.array_get(sample, 'id'), equals(1));
        expect(Utils.array_get(sample, 'address.city'), isNull,
            reason:
                'array_get não desce no dot notation, só 1 nível (veja data_get).');
      });

      test('data_get - busca aninhada (dot notation)', () {
        expect(Utils.data_get(sample, 'id'), equals(1));
        expect(Utils.data_get(sample, 'address.city'), equals('Gotham'));
        expect(Utils.data_get(sample, 'address.zip'), equals(12345));
        expect(Utils.data_get(sample, 'address.country'), isNull);
      });
    });

    group('array_pluck', () {
      test('array_pluck sem key', () {
        var array = [
          {'id': 1, 'name': 'Isaque'},
          {'id': 2, 'name': 'John'},
          {'id': 3, 'name': 'Jane'}
        ];
        var result = Utils.array_pluck(array, 'name');
        expect(result, equals(['Isaque', 'John', 'Jane']));
      });

      test('array_pluck com key', () {
        var array = [
          {'id': 1, 'name': 'Isaque'},
          {'id': 2, 'name': 'John'},
          {'id': 3, 'name': 'Jane'}
        ];
        var result = Utils.array_pluck(array, 'name', 'id');
        expect(result, equals({1: 'Isaque', 2: 'John', 3: 'Jane'}));
      });

      test('array_pluck falha se key não existe no 2° item', () {
        var array = [
          {'id': 1, 'name': 'Isaque'},
          // aqui 'id' vira 'ID', para simular bug
          {'ID': 2, 'name': 'John'},
        ];
        var result = Utils.array_pluck(array, 'name', 'id');
        // Esperamos que o 2° item não encontre 'id',
        // e retorne fallback => { {ID:2, name:John} : 'John' }
        // ou algo do gênero. Vamos verificar:
        expect(result.length, equals(2));

        // A primeira chave deve ser '1'
        expect(result.keys.first, equals(1));

        // A segunda chave será 'ID'?? Vamos checar se é o Map inteiro:
        var secondKey = result.keys.last;
        // secondKey provavelmente vai ser {ID:2, name:John}
       
        expect(secondKey, equals({'ID': 2, 'name': 'John'}));
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

    test('array_fill', () {
      expect(Utils.array_fill(0, 3, 'x'), equals(['x', 'x', 'x']));
    });

    test('array_merge', () {
      expect(Utils.array_merge([1, 2], [3, 4]), equals([1, 2, 3, 4]));
    });

    test('map_merge_sd', () {
      var map1 = {'driver': 'pgsql', 'host': 'localhost'};
      var map2 = {'host': '127.0.0.1', 'port': 5432};
      var merged = Utils.map_merge_sd(map1, map2);
      // Esperamos que host seja '127.0.0.1' (sobrescrito) e inclua 'port'
      expect(merged,
          equals({'driver': 'pgsql', 'host': '127.0.0.1', 'port': 5432}));
    });
  });
}

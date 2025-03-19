import 'package:eloquent/src/support/arr.dart';
import 'package:test/test.dart';

void main() {
  group('Arr Tests', () {
    test('accessible', () {
      expect(Arr.accessible([1, 2, 3]), isTrue);
      expect(Arr.accessible({'key': 'value'}), isTrue);
      expect(Arr.accessible('string'), isFalse);
      expect(Arr.accessible(123), isFalse);
    });

    group('exists', () {
      test('Map', () {
        var map = {'a': 1, 'b': 2};
        expect(Arr.exists(map, 'a'), isTrue);
        expect(Arr.exists(map, 'c'), isFalse);
      });

      test('List', () {
        var list = [10, 20, 30];
        expect(Arr.exists(list, 1), isTrue); // index 1 -> 20
        expect(Arr.exists(list, 3), isFalse);
        expect(Arr.exists(list, '1'), isFalse,
            reason: 'String "1" não é int, então deve dar false');
      });
    });

    group('get', () {
      test('Map sem dot notation', () {
        var map = {'name': 'John', 'age': 30};
        expect(Arr.get(map, 'name'), equals('John'));
        expect(Arr.get(map, 'foo', 'default'), equals('default'));
      });

      test('Map com dot notation', () {
        var map = {
          'person': {
            'name': 'Alice',
            'address': {
              'city': 'Wonderland',
            },
          },
        };
        // Dot notation
        expect(Arr.get(map, 'person.name'), equals('Alice'));
        expect(Arr.get(map, 'person.address.city'), equals('Wonderland'));
        expect(Arr.get(map, 'person.address.zip', 'no-zip'), equals('no-zip'));
      });

      test('List com índice e dot notation', () {
        var list = [
          {'id': 1, 'name': 'John'},
          {'id': 2, 'name': 'Jane'}
        ];
        // Arr.get em list -> "0" string => falha
        expect(Arr.get(list, '0'), isNull);
        // Arr.get em list -> 0 int => pega item index 0
        expect(Arr.get(list, '0'), isNull,
            reason:
                'Ainda não implementamos "toIntOrNull" aqui, é só exemplo.');

        // Exemplo prático:
        // Se quisermos "id" do item 1:
        // Precisamos "get(list, '1')" => a function 'exists' falha pois "1" é string
        // Precisamos int key => get(list, '1'.toIntOrNull()) ou algo assim
      });
    });

    group('has', () {
      test('Map com dot notation', () {
        var map = {
          'user': {
            'profile': {'id': 10}
          }
        };
        expect(Arr.has(map, 'user.profile.id'), isTrue);
        expect(Arr.has(map, 'user.profile.name'), isFalse);
      });

      test('List', () {
        var list = [10, 20];
        expect(Arr.has(list, 1), isTrue);
        expect(Arr.has(list, 2), isFalse);
      });
    });

    group('forget', () {
      test('Map direct key', () {
        var map = {'a': 1, 'b': 2, 'c': 3};
        Arr.forget(map, 'b');
        expect(map, equals({'a': 1, 'c': 3}));
      });

      test('Map dot notation', () {
        var map = {
          'person': {
            'name': 'Bob',
            'contact': {'phone': '555-1234', 'email': 'bob@x.com'}
          }
        };
        Arr.forget(map, 'person.contact.email');
        expect(Arr.has(map, 'person.contact.email'), isFalse);
        // phone continua
        expect(Arr.get(map, 'person.contact.phone'), equals('555-1234'));
      });

      test('List', () {
        var list = [5, 6, 7];
        Arr.forget(list, 1); // removeAt(1)
        expect(list, equals([5, 7]));
      });
    });

    group('flatten', () {
      test('exemplo básico', () {
        var nested = [
          1,
          [2, 3],
          [
            4,
            [5]
          ]
        ];
        var result = Arr.flatten(nested);
        expect(
            result,
            equals([
              1,
              2,
              3,
              4,
              [5]
            ]));

        var resultDeep = Arr.flatten(nested, 2);
        expect(resultDeep, equals([1, 2, 3, 4, 5]));
      });
    });

    group('pluck', () {
      test('List sem key => retorna List', () {
        var arr = [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'}
        ];
        var names = Arr.pluck(arr, 'name');
        expect(names, equals(['Alice', 'Bob']));
      });

      test('List com key => retorna Map', () {
        var arr = [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'}
        ];
        var mapped = Arr.pluck(arr, 'name', 'id');
        expect(mapped, equals({1: 'Alice', 2: 'Bob'}));
      });

      test('Map com key => retorna Map', () {
        var map = {
          'u1': {'id': 10, 'name': 'Jane'},
          'u2': {'id': 20, 'name': 'John'}
        };
        var r = Arr.pluck(map, 'name', 'id');
        // Precisamos percorrer os values do map e usar 'id' como key
        // => {10: 'Jane', 20: 'John'}
        expect(r, equals({10: 'Jane', 20: 'John'}));
      });
    });

    test('dataGet', () {
      var item = {
        'person': {
          'info': {
            'email': 'x@y.com',
          }
        }
      };
      expect(Arr.dataGet(item, 'person.info.email'), equals('x@y.com'));
      expect(Arr.dataGet(item, 'person.info.phone'), isNull);
    });

    group('only', () {
      test('pega apenas as chaves informadas', () {
        var map = {'a': 1, 'b': 2, 'c': 3};
        var onlyAB = Arr.only(map, ['a', 'b']);
        expect(onlyAB, equals({'a': 1, 'b': 2}));
      });
    });

    group('except', () {
      test('remove chaves informadas', () {
        var map = {'a': 1, 'b': 2, 'c': 3};
        var result = Arr.except(map, ['b']);
        expect(result, equals({'a': 1, 'c': 3}));
      });
    });

    group('collapse', () {
      test('colapsa lista de listas', () {
        var arr = [
          [1, 2],
          [3, 4]
        ];
        var collapsed = Arr.collapse(arr);
        expect(collapsed, equals([1, 2, 3, 4]));
      });
    });

    group('arrayMerge', () {
      test('simples merge de listas', () {
        var a1 = [1, 2];
        var a2 = [3, 4];
        var merged = Arr.arrayMerge(a1, a2);
        expect(merged, equals([1, 2, 3, 4]));
      });
    });

    group('prepend', () {
      test('em List, sem key', () {
        var lst = [2, 3];
        var returned = Arr.prepend(lst, 1);
        expect(lst, equals([1, 2, 3]));
        // returned deve ser a mesma list
        expect(returned, same(lst));
      });

      test('em List, com key => vira Map', () {
        var lst = ['a', 'b'];
        var result = Arr.prepend(lst, 'FIRST', 'k');
        // Esperamos { k: 'FIRST', 0: 'a', 1: 'b' }
        expect(result, equals({'k': 'FIRST', 0: 'a', 1: 'b'}));
      });

      test('em Map, sem key', () {
        var map = {'one': 1};
        var result = Arr.prepend(map, 'xxx');
        // Esperamos {xxx: null, one:1}
        expect(result, equals({'xxx': null, 'one': 1}));
      });

      test('em Map, com key', () {
        var map = {'one': 1};
        var result = Arr.prepend(map, 'xxx', 'z');
        // {z: xxx, one: 1}
        expect(result, equals({'z': 'xxx', 'one': 1}));
      });
    });

    group('pull', () {
      test('Map - pega e remove', () {
        var map = {'a': 1, 'b': 2};
        var val = Arr.pull(map, 'a');
        expect(val, 1);
        expect(map, equals({'b': 2}));
      });
    });

    group('set', () {
      test('dot notation em Map', () {
        var map = {};
        Arr.set(map, 'user.name', 'Mark');
        expect(
            map,
            equals({
              'user': {'name': 'Mark'}
            }));

        // Sobrescrever
        Arr.set(map, 'user.email', 'mark@test.com');
        expect(
            map,
            equals({
              'user': {'name': 'Mark', 'email': 'mark@test.com'}
            }));
      });
    });
  });
}

// Se precisar de "string to int" parse:
// extension on String {
//   int? toIntOrNull() => int.tryParse(this);
// }

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
}

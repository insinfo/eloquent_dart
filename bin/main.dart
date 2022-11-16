import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:eloquent/src/utils/dsn_parser.dart';

void main(List<String> args) {
  //container.singleton('foo');
  // container.bind('config', (app) {
  //   return new FooBar();
  // });

  // var foo = container.make('foo');
  // foo.showMessage('Isaque');

  //var c = FooBar();
  //var result = Utils.property_exists(c, 'showMessage');
  //var result = Utils.call_method(c, 'showMessage', ['isaque']);
  // print(result);
  var capsule = new Manager();
  capsule.addConnection({
    'driver': 'pgsql',
    'host': 'localhost',
    'port': '5432',
    'database': 'sistemas',
    'username': 'sisadmin',
    'password': 's1sadm1n',
    'charset': 'utf8',
    'prefix': '',
    'schema': ['esic'],
    //'sslmode' => 'prefer',
  });

  capsule.setAsGlobal();
  var query = capsule.table('lda_solicitante');

  query.select(['idsolicitante', 'email']);
  query.limit(1);
  var users = query.get();
}

class FooBar {
  String showMessage(String msg) {
    print("message $msg");
    return msg;
  }
}

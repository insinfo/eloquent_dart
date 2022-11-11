import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:eloquent/src/utils/dsn_parser.dart';

void main(List<String> args) {
  var container = Container();

  container.singleton('foo');
}

class FooBar {
  void showMessage(String msg) {
    print("message $msg");
  }
}

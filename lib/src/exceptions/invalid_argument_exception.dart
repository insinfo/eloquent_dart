import 'package:eloquent/eloquent.dart';

class InvalidArgumentException implements LogicException {
  String cause;
  InvalidArgumentException([this.cause = 'InvalidArgumentException']);
}

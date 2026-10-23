import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';

mixin CapsuleManagerTrait {
  /// The instance made global by [setAsGlobal].
  static dynamic instance;

  /// The IoC container.
  late Container container;

  /// Sets [container] to [containerP], binding an empty [Fluent] as
  /// `config` when the container has none.
  void setupContainer(Container containerP) {
    this.container = containerP;

    if (!this.container.bound('config')) {
      this.container.instance('config', new Fluent());
    }
  }

  /// Makes this instance available globally as [instance].
  void setAsGlobal() {
    CapsuleManagerTrait.instance = this;
  }

  /// Returns [container].
  Container? getContainer() {
    return this.container;
  }

  /// Sets [container].
  void setContainer(Container containerP) {
    this.container = containerP;
  }
}

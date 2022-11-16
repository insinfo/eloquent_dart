import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';

mixin CapsuleManagerTrait {
  ///
  /// The current globally used instance.
  ///
  /// @var object
  ///
  static dynamic instance;

  ///
  /// The container instance.
  ///
  /// @var \Illuminate\Contracts\Container\Container
  ///
  late Container container;

  ///
  /// Setup the IoC container instance.
  ///
  /// @param  \Illuminate\Contracts\Container\Container  $container
  /// @return void
  ///
  void setupContainer(Container containerP) {
    this.container = containerP;

    if (!this.container.bound('config')) {
      this.container.instance('config', new Fluent());
    }
  }

  ///
  /// Make this capsule instance available globally.
  ///
  /// @return void
  ///
  void setAsGlobal() {
    CapsuleManagerTrait.instance = this;
  }

  ///
  /// Get the IoC container instance.
  ///
  /// @return \Illuminate\Contracts\Container\Container
  ///
  Container? getContainer() {
    return this.container;
  }

  ///
  /// Set the IoC container instance.
  ///
  /// @param  \Illuminate\Contracts\Container\Container  $container
  /// @return void
  ///
  void setContainer(Container containerP) {
    this.container = containerP;
  }
}

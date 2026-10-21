import 'container.dart';

/// Builds a contextual binding: `container.when(concrete).needs(abstract)
/// .give(implementation)`.
class ContextualBindingBuilder {
  /// The container that receives the binding.
  Container container;

  /// The abstract whose factory gets the implementation.
  String? concrete;

  /// The abstract that resolves to the implementation, set by [needs].
  String? needsProp;

  ContextualBindingBuilder(this.container, this.concrete);

  /// Sets the abstract that [concrete] needs.
  ContextualBindingBuilder needs(String abstract) {
    this.needsProp = abstract;
    return this;
  }

  /// Registers [implementation] (a factory or a name) as what [needsProp]
  /// resolves to while [concrete] is being built.
  void give(dynamic implementation) {
    this
        .container
        .addContextualBinding(this.concrete, this.needsProp, implementation);
  }
}

import 'container.dart';

class ContextualBindingBuilder {
/**
     * The underlying container instance.
     *
     * @var \Illuminate\Container\Container
     */
  Container container;

  /**
     * The concrete instance.
     *
     * @var string
     */
  String? concrete;

  /**
     * The abstract target.
     *
     * @var string
     */
  String? needsProp;

  /**
     * Create a new contextual binding builder.
     *
     * @param  \Illuminate\Container\Container  $container
     * @param  string  $concrete
     * @return void
     */
  ContextualBindingBuilder(this.container, this.concrete);

  /**
     * Define the abstract target that depends on the context.
     *
     * @param  string  $abstract
     * @return $this
     */
  ContextualBindingBuilder needs(String abstract) {
    this.needsProp = abstract;
    return this;
  }

  /**
     * Define the implementation for the contextual binding.
     *
     * @param  \Closure|string  $implementation
     * @return void
     */
  void give(dynamic implementation) {
    this
        .container
        .addContextualBinding(this.concrete, this.needs, implementation);
  }
}

import 'package:eloquent/eloquent.dart';
import 'contextual_binding_builder.dart';

/// IoC Container,
class Container {
  //from method dynamic share(Closure $closure)
  static dynamic object;

  ///
  /// The current globally available container (if any).
  ///
  /// @var static
  ///
  static Container? instanceProp;

  ///
  /// An array of the types that have been resolved.
  ///
  /// @var array
  ///
  Map<String, dynamic> resolvedProp = {};

  ///
  /// The container's bindings.
  ///
  /// @var array
  ///
  Map<String, dynamic> bindings = {};

  ///
  /// The container's shared instances.
  ///
  /// @var array
  ///
  Map<String, dynamic> instances = {};

  ///
  /// The registered type aliases.
  ///
  /// @var array
  ///
  Map<String, dynamic> aliases = {};

  ///
  /// The extension closures for services.
  ///
  /// @var array
  ///
  Map<String, dynamic> extenders = {};

  ///
  /// All of the registered tags.
  ///
  /// @var array
  ///
  Map<String, dynamic> tags = {};

  ///
  /// The stack of concretions currently being built.
  ///
  /// @var array
  ///
  List buildStack = [];

  ///
  /// The contextual binding map.
  ///
  /// @var array
  ///
  Map contextual = {};

  ///
  /// All of the registered rebound callbacks.
  ///
  /// @var array
  ///
  Map reboundCallbacks = {};

  ///
  /// All of the global resolving callbacks.
  ///
  /// @var array
  ///
  List globalResolvingCallbacks = [];

  ///
  /// All of the global after resolving callbacks.
  ///
  /// @var array
  ///
  List globalAfterResolvingCallbacks = [];

  ///
  /// All of the resolving callbacks by class type.
  ///
  /// @var array
  ///
  List resolvingCallbacks = [];

  ///
  /// All of the after resolving callbacks by class type.
  ///
  /// @var array
  ///
  List afterResolvingCallbacks = [];

  ///
  /// Define a contextual binding.
  ///
  /// @param  string  $concrete
  /// @return \Illuminate\Contracts\Container\ContextualBindingBuilder
  ///
  ContextualBindingBuilder when(String concrete) {
    concrete = this.normalize(concrete);
    return ContextualBindingBuilder(this, concrete);
  }

  ///
  /// Determine if the given abstract type has been bound.
  ///
  /// @param  string  $abstract
  /// @return bool
  ///
  bool bound(dynamic abstractP) {
    var abstract = this.normalize(abstractP);

    return Utils.isset(this.bindings[abstract]) ||
        Utils.isset(this.instances[abstract]) ||
        this.isAlias(abstract);
  }

  ///
  /// Determine if the given abstract type has been resolved.
  ///
  /// @param  string  $abstract
  /// @return bool
  ///
  bool resolved(dynamic abstract) {
    abstract = this.normalize(abstract);

    if (this.isAlias(abstract)) {
      abstract = this.getAlias(abstract);
    }

    return Utils.isset(this.resolvedProp[abstract]) ||
        Utils.isset(this.instances[abstract]);
  }

  ///
  /// Determine if a given string is an alias.
  ///
  /// @param  string  $name
  /// @return bool
  ///
  bool isAlias(String name) {
    return Utils.isset(this.aliases[this.normalize(name)]);
  }

  ///
  /// Register a binding with the container.
  ///
  /// @param  string|array  $abstract
  /// @param  Function|String|null  $concrete
  /// @param  bool  $shared
  /// @return void
  ///
  void bind(abstract, [dynamic concrete, bool shared = false]) {
    //abstract = this.normalize(abstract);
    //concrete = this.normalize(concrete);

    // If the given types are actually an array, we will assume an alias is being
    // defined and will grab this "real" abstract class name and register this
    // alias with the container so that it can be used as a shortcut for it.
    if (Utils.is_map(abstract)) {
      var res = this.extractAlias(abstract);
      abstract = res.first;
      var alias = res.last;
      this.alias(abstract, alias);
    }

    // // If no concrete type was given, we will simply set the concrete type to the
    // // abstract type. After that, the concrete type to be registered as shared
    // // without being forced to state their classes in both of the parameters.
    this.dropStaleInstances(abstract);

    if (Utils.is_null(concrete)) {
      concrete = abstract;
    }

    // // If the factory is not a Closure, it means it is just a class name which is
    // // bound into this container to the abstract type and we will just wrap it
    // // up inside its own Closure to give us more convenience when extending.
    if (!(concrete is Function)) {
      concrete = this.getClosure(abstract, concrete);
    }

    this.bindings[abstract] = {'concrete': concrete, 'shared': shared};

    // // If the abstract type was already resolved in this container we'll fire the
    // // rebound listener so that any objects which have already gotten resolved
    // // can have their copy of the object updated via the listener callbacks.
    if (this.resolved(abstract)) {
      this.rebound(abstract);
    }
  }

  ///
  /// Get the Closure to be used when building a type.
  ///
  /// @param  string  $abstract
  /// @param  string  $concrete
  /// @return \Closure
  ///
  Function getClosure(String abstract, String concrete) {
    return ($c, [parameters = const []]) {
      var methodName = (abstract == concrete) ? 'build' : 'make';
      return Utils.call_method($c, methodName, [concrete, parameters]);
      // return $c->$method(concrete, parameters);
    };
  }

  ///
  /// Add a contextual binding to the container.
  ///
  /// @param  string  $concrete
  /// @param  string  $abstract
  /// @param  \Closure|string  $implementation
  /// @return void
  ///
  void addContextualBinding(
      dynamic concrete, dynamic abstract, dynamic implementation) {
    this.contextual[this.normalize(concrete)][this.normalize(abstract)] =
        this.normalize(implementation);
  }

  ///
  /// Register a binding if it hasn't already been registered.
  ///
  /// @param  string  $abstract
  /// @param  \Closure|string|null  $concrete
  /// @param  bool  $shared
  /// @return void
  ///
  void bindIf(String abstract, [dynamic concrete, bool shared = false]) {
    if (!this.bound(abstract)) {
      this.bind(abstract, concrete, shared);
    }
  }

  ///
  /// Register a shared binding in the container.
  ///
  /// @param  string|array  $abstract
  /// @param  \Closure|string|null  $concrete
  /// @return void
  ///
  void singleton(dynamic abstract, [dynamic concrete]) {
    this.bind(abstract, concrete, true);
  }

  ///
  /// Wrap a Closure such that it is shared.
  ///
  /// @param  \Closure  $closure
  /// @return \Closure
  ///
  Function share(Function closure) {
    return (container) {
      // We'll simply declare a static variable within the Closures and if it has
      // not been set we will execute the given Closures to resolve this value
      // and return it back to these consumers of the method as an instance.

      if (Utils.is_null(object)) {
        object = closure(container);
      }

      return object;
    };
  }

  ///
  /// "Extend" an abstract type in the container.
  ///
  /// @param  string    $abstract
  /// @param  \Closure  $closure
  /// @return void
  ///
  /// @throws \InvalidArgumentException
  ///
  void extend(dynamic abstractP, Function closure) {
    var abstract = this.normalize(abstractP);

    if (Utils.isset(this.instances[abstract])) {
      this.instances[abstract] = closure(this.instances[abstract], this);
      this.rebound(abstract);
    } else {
      this.extenders[abstract] ?? [];
      this.extenders[abstract].add(closure);
    }
  }

  ///
  /// Register an existing instance as shared in the container.
  ///
  /// @param  string  $abstract
  /// @param  mixed   $instance
  /// @return void
  ///
  void instance(String abstractP, dynamic instanceP) {
    var abstract = this.normalize(abstractP);

    // First, we will extract the alias from the abstract if it is an array so we
    // are using the correct name when binding the type. If we get an alias it
    // will be registered with the container so we can resolve it out later.
    if (Utils.is_map(abstract)) {
      var res = this.extractAlias(abstract);
      abstract = res.first;
      var alias = res.last;

      this.alias(abstract, alias);
    }

    this.aliases.remove(abstract);

    // // We'll check to determine if this type has been bound before, and if it has
    // // we will fire the rebound callbacks registered with the container and it
    // // can be updated with consuming classes that have gotten resolved here.
    var bound = this.bound(abstract);

    this.instances[abstract] = instanceP;

    if (bound) {
      this.rebound(abstract);
    }
  }

  ///
  /// Assign a set of tags to a given binding.
  ///
  /// @param  array|string  $abstracts
  /// @param  array|mixed   ...$tags
  /// @return void
  ///
  void tag(List abstracts, List<String> tags) {
    //var tags = Utils.is_array(tags) ? tags : array_slice(func_get_args(), 1);

    for (var tag in tags) {
      if (!Utils.isset(this.tags[tag])) {
        this.tags[tag] = [];
      }

      for (var abstract in abstracts) {
        this.tags[tag].add(this.normalize(abstract));
      }
    }
  }

  ///
  /// Resolve all of the bindings for a given tag.
  ///
  /// @param  string  $tag
  /// @return array
  ///
  dynamic tagged(String tag) {
    var results = [];

    if (Utils.isset(this.tags[tag])) {
      for (var abstract in this.tags[tag]) {
        results.add(this.make(abstract));
      }
    }

    return results;
  }

  ///
  /// Alias a type to a different name.
  ///
  /// @param  string  $abstract
  /// @param  string  $alias
  /// @return void
  ///
  void alias(String abstract, String alias) {
    this.aliases[alias] = this.normalize(abstract);
  }

  ///
  /// Extract the type and alias from a given definition.
  ///
  /// @param  array  $definition
  /// @return array
  ///
  List extractAlias(Map<String, dynamic> definition) {
    //current($definition)
    return [definition.entries.first.key, definition.entries.first.value];
  }

  ///
  /// Bind a new callback to an abstract's rebind event.
  ///
  /// @param  string    $abstract
  /// @param  \Closure  $callback
  /// @return mixed
  ///
  dynamic rebinding(String abstract, Function callback) {
    var key = this.normalize(abstract);
    this.reboundCallbacks[key] ?? [];
    this.reboundCallbacks[key].add(callback);

    if (this.bound(abstract)) {
      return this.make(abstract);
    }
  }

  ///
  /// Refresh an instance on the given target and method.
  ///
  /// @param  string  $abstract
  /// @param  mixed   $target
  /// @param  string  $method
  /// @return mixed
  ///
  dynamic refresh(abstract, target, String methodName) {
    return this.rebinding(this.normalize(abstract), (app, instance) {
      // target->{$method}($instance);
      Utils.call_method(target, methodName, [instance]);
    });
  }

  ///
  /// Fire the "rebound" callbacks for the given abstract type.
  ///
  /// @param  string  $abstract
  /// @return void
  ///
  void rebound(abstract) {
    var instance = this.make(abstract);

    for (var callback in this.getReboundCallbacks(abstract)) {
      callback(this, instance);
    }
  }

  ///
  /// Get the rebound callbacks for a given type.
  ///
  /// @param  string  $abstract
  /// @return array
  ///
  dynamic getReboundCallbacks(abstract) {
    if (Utils.isset(this.reboundCallbacks[abstract])) {
      return this.reboundCallbacks[abstract];
    }

    return [];
  }

  ///
  /// Wrap the given closure such that its dependencies will be injected when executed.
  ///
  /// @param  \Closure  $callback
  /// @param  array  $parameters
  /// @return \Closure
  ///
  Function wrap(Function callback, [List parameters = const []]) {
    return () {
      return this.call(callback, parameters);
    };
  }

  ///
  /// Call the given Closure / class@method and inject its dependencies.
  ///
  /// @param  callable|string  $callback
  /// @param  array  $parameters
  /// @param  string|null  $defaultMethod
  /// @return mixed
  ///
  dynamic call(dynamic callback,
      [parameters = const [], String? defaultMethod]) {
    if (this.isCallableWithAtSign(callback) || defaultMethod != null) {
      return this.callClass(callback, parameters, defaultMethod);
    }

    var dependencies = this.getMethodDependencies(callback, parameters);

    return callback(dependencies);
  }

  ///
  /// Determine if the given string is in Class@method syntax.
  ///
  /// @param  mixed  $callback
  /// @return bool
  ///
  bool isCallableWithAtSign(dynamic callback) {
    return Utils.is_string(callback) && Utils.strpos(callback, '@') != false;
  }

  ///
  /// Get all dependencies for a given method.
  ///
  /// @param  callable|string  $callback
  /// @param  array  $parameters
  /// @return array
  ///
  dynamic getMethodDependencies(dynamic callback, [parameters = const []]) {
    // var dependencies = [];

    // for (this.getCallReflector(callback)->getParameters() as $parameter) {
    //     this.addDependencyForCallParameter($parameter, $parameters, $dependencies);
    // }

    // return array_merge($dependencies, $parameters);
  }

  ///
  /// Get the proper reflection instance for the given callback.
  ///
  /// @param  callable|string  $callback
  /// @return \ReflectionFunctionAbstract
  ///
  dynamic getCallReflector($callback) {
    // if (is_string($callback) && strpos($callback, '::') !== false) {
    //     $callback = explode('::', $callback);
    // }

    // if (is_array($callback)) {
    //     return new ReflectionMethod($callback[0], $callback[1]);
    // }

    // return new ReflectionFunction($callback);
  }

  ///
  /// Call a string reference to a class using Class@method syntax.
  ///
  /// @param  string  $target
  /// @param  array  $parameters
  /// @param  string|null  $defaultMethod
  /// @return mixed
  ///
  /// @throws \InvalidArgumentException
  ///
  dynamic callClass($target, [$parameters = const [], String? defaultMethod]) {
    var segments = Utils.explode('@', $target);

    // If the listener has an @ sign, we will assume it is being used to delimit
    // the class name from the handle method name. This allows for handlers
    // to run multiple handler methods in a single class for convenience.
    var method = Utils.count(segments) == 2 ? segments[1] : defaultMethod;

    if (Utils.is_null(method)) {
      throw InvalidArgumentException('Method not provided.');
    }

    return this.call([this.make(segments[0]), method], $parameters);
  }

  ///
  /// Resolve the given type from the container.
  ///
  /// @param  string  $abstract
  /// @param  array   $parameters
  /// @return mixed
  ///
  dynamic make(abstract, [dynamic parameters]) {
    abstract = this.getAlias(this.normalize(abstract));

    // If an instance of the type is currently being managed as a singleton we'll
    // just return an existing instance instead of instantiating new instances
    // so the developer can keep using the same objects instance every time.
    if (Utils.isset(this.instances[abstract])) {
      return this.instances[abstract];
    }

    var concrete = this.getConcrete(abstract);

    var objectL;
    // We're ready to instantiate an instance of the concrete type registered for
    // the binding. This will instantiate the types, as well as resolve any of
    // its "nested" dependencies recursively until all have gotten resolved.
    if (this.isBuildable(concrete, abstract)) {
      objectL = this.build(concrete, parameters);
    } else {
      objectL = this.make(concrete, parameters);
    }

    // If we defined any extenders for this type, we'll need to spin through them
    // and apply them to the object being built. This allows for the extension
    // of services, such as changing configuration or decorating the object.
    for (var extender in this.getExtenders(abstract)) {
      objectL = extender(objectL, this);
    }

    // If the requested type is registered as a singleton we'll want to cache off
    // the instances in "memory" so we can return it later without creating an
    // entirely new instance of an object on each subsequent request for it.
    if (this.isShared(abstract)) {
      this.instances[abstract] = objectL;
    }

    this.fireResolvingCallbacks(abstract, objectL);

    this.resolvedProp[abstract] = true;

    return objectL;
  }

  ///
  /// Get the concrete type for a given abstract.
  ///
  /// @param  string  $abstract
  /// @return mixed   $concrete
  ///
  dynamic getConcrete(String abstract) {
    var concrete = this.getContextualConcrete(abstract);
    if (!Utils.is_null(concrete)) {
      return concrete;
    }

    // If we don't have a registered resolver or concrete for the type, we'll just
    // assume each type is a concrete name and will attempt to resolve it as is
    // since the container should be able to resolve concretes automatically.
    if (!Utils.isset(this.bindings[abstract])) {
      return abstract;
    }

    return this.bindings[abstract]['concrete'];
  }

  ///
  /// Get the contextual concrete binding for the given abstract.
  ///
  /// @param  string  $abstract
  /// @return string|null
  ///
  String? getContextualConcrete(String abstract) {
    if (this.contextual[Utils.array_end(this.buildStack)] != null &&
        Utils.isset(
            this.contextual[Utils.array_end(this.buildStack)][abstract])) {
      return this.contextual[Utils.array_end(this.buildStack)][abstract];
    }

    return null;
  }

  ///
  /// Normalize the given class name by removing leading slashes.
  ///
  /// @param  mixed  $service
  /// @return mixed
  ///
  dynamic normalize(service) {
    // remove Backslash start of string
    return Utils.is_string(service) ? Utils.ltrim(service, '\\\\') : service;
  }

  ///
  /// Get the extender callbacks for a given type.
  ///
  /// @param  string  $abstract
  /// @return array
  ///
  dynamic getExtenders(dynamic abstract) {
    if (Utils.isset(this.extenders[abstract])) {
      return this.extenders[abstract];
    }

    return [];
  }

  ///
  /// Instantiate a concrete instance of the given type.
  ///
  /// @param  string  $concrete
  /// @param  array   $parameters
  /// @return mixed
  ///
  /// @throws \Illuminate\Contracts\Container\BindingResolutionException
  ///
  dynamic build(dynamic concrete, [dynamic parameters]) {
    // If the concrete type is actually a Closure, we will just execute it and
    // hand back the results of the functions, which allows functions to be
    // used as resolvers for more fine-tuned resolution of these objects.
    if (concrete is Function) {
      return concrete(parameters);
    }

    //var reflector = new ReflectionClass(concrete);
    // var reflector = reflect(concrete);

    // If the type is not instantiable, the developer is attempting to resolve
    // an abstract type such as an Interface of Abstract Class and there is
    // no binding registered for the abstractions so we need to bail out.
    // if (! $reflector->isInstantiable()) {
    //     if (! empty($this->buildStack)) {
    //         $previous = implode(', ', this. buildStack);

    //         $message = "Target [$concrete] is not instantiable while building [$previous].";
    //     } else {
    //         $message = "Target [$concrete] is not instantiable.";
    //     }

    //     throw new BindingResolutionException($message);
    // }

    // this.buildStack.add(concrete);

    // var constructor = $reflector->getConstructor();

    // // If there are no constructors, that means there are no dependencies then
    // // we can just resolve the instances of the objects right away, without
    // // resolving any other types or dependencies out of these containers.
    // if (Utils.is_null(constructor)) {
    //     Utils.array_pop(this.buildStack);

    //     return new $concrete;
    // }

    // $dependencies = $constructor->getParameters();

    // // Once we have all the constructor's parameters we can create each of the
    // // dependency instances and then use the reflection instances to make a
    // // new instance of this class, injecting the created dependencies in.
    // $parameters = this. keyParametersByArgument(
    //     $dependencies, $parameters
    // );

    // $instances = this. getDependencies(
    //     $dependencies, $parameters
    // );

    // array_pop($this->buildStack);

    // return $reflector->newInstanceArgs($instances);
  }

  ///
  /// Resolve all of the dependencies from the ReflectionParameters.
  ///
  /// @param  array  $parameters
  /// @param  array  $primitives
  /// @return array
  ///
  dynamic getDependencies(dynamic $parameters, [dynamic $primitives]) {
    // $dependencies = [];

    // foreach ($parameters as $parameter) {
    //     $dependency = $parameter->getClass();

    //     // If the class is null, it means the dependency is a string or some other
    //     // primitive type which we can not resolve since it is not a class and
    //     // we will just bomb out with an error since we have no-where to go.
    //     if (array_key_exists($parameter->name, $primitives)) {
    //         $dependencies[] = $primitives[$parameter->name];
    //     } elseif (is_null($dependency)) {
    //         $dependencies[] = this. resolveNonClass($parameter);
    //     } else {
    //         $dependencies[] = this. resolveClass($parameter);
    //     }
    // }

    // return $dependencies;
  }

  ///
  /// Resolve a non-class hinted dependency.
  ///
  /// @param  \ReflectionParameter  $parameter
  /// @return mixed
  ///
  /// @throws \Illuminate\Contracts\Container\BindingResolutionException
  ///
  dynamic resolveNonClass(dynamic $parameter) {
    // if (! is_null($concrete = this. getContextualConcrete('$'.$parameter->name))) {
    //     if ($concrete instanceof Closure) {
    //         return call_user_func($concrete, $this);
    //     } else {
    //         return $concrete;
    //     }
    // }

    // if ($parameter->isDefaultValueAvailable()) {
    //     return $parameter->getDefaultValue();
    // }

    // $message = "Unresolvable dependency resolving [$parameter] in class {$parameter->getDeclaringClass()->getName()}";

    // throw new BindingResolutionException($message);
  }

  ///
  /// Resolve a class based dependency from the container.
  ///
  /// @param  \ReflectionParameter  $parameter
  /// @return mixed
  ///
  /// @throws \Illuminate\Contracts\Container\BindingResolutionException
  ///
  dynamic resolveClass(dynamic $parameter) {
    // try {
    //     return this. make($parameter->getClass()->name);
    // }

    // // If we can not resolve the class instance, we will check to see if the value
    // // is optional, and if it is we will return the optional parameter value as
    // // the value of the dependency, similarly to how we do this with scalars.
    // catch (BindingResolutionException $e) {
    //     if ($parameter->isOptional()) {
    //         return $parameter->getDefaultValue();
    //     }

    //     throw $e;
    // }
  }

  ///
  /// If extra parameters are passed by numeric ID, rekey them by argument name.
  ///
  /// @param  array  $dependencies
  /// @param  array  $parameters
  /// @return array
  ///
  dynamic keyParametersByArgument(dynamic $dependencies, dynamic $parameters) {
    // foreach ($parameters as $key => $value) {
    //     if (is_numeric($key)) {
    //         unset($parameters[$key]);

    //         $parameters[$dependencies[$key]->name] = $value;
    //     }
    // }

    // return $parameters;
  }

  ///
  /// Register a new resolving callback.
  ///
  /// @param  string    $abstract
  /// @param  \Closure|null  $callback
  /// @return void
  ///
  dynamic resolving(abstract, [Function? callback]) {
    // if ($callback == null && $abstract instanceof Closure) {
    //     this. resolvingCallback($abstract);
    // } else {
    //     this. resolvingCallbacks[$this->normalize($abstract)][] = $callback;
    // }
  }

  ///
  /// Register a new after resolving callback for all types.
  ///
  /// @param  string   $abstract
  /// @param  \Closure|null $callback
  /// @return void
  ///
  dynamic afterResolving(abstract, [Function? callback]) {
    // if ($abstract instanceof Closure && $callback === null) {
    //     this. afterResolvingCallback($abstract);
    // } else {
    //     this. afterResolvingCallbacks[$this->normalize($abstract)][] = $callback;
    // }
  }

  ///
  /// Register a new resolving callback by type of its first argument.
  ///
  /// @param  \Closure  $callback
  /// @return void
  ///
  void resolvingCallback(Function $callback) {
    // $abstract = this. getFunctionHint($callback);

    // if ($abstract) {
    //     this. resolvingCallbacks[$abstract][] = $callback;
    // } else {
    //     this. globalResolvingCallbacks[] = $callback;
    // }
  }

  ///
  /// Register a new after resolving callback by type of its first argument.
  ///
  /// @param  \Closure  $callback
  /// @return void
  ///
  dynamic afterResolvingCallback(Function $callback) {
    // $abstract = this. getFunctionHint($callback);

    // if ($abstract) {
    //     this. afterResolvingCallbacks[$abstract][] = $callback;
    // } else {
    //     this. globalAfterResolvingCallbacks[] = $callback;
    // }
  }

  ///
  /// Get the type hint for this closure's first argument.
  ///
  /// @param  \Closure  $callback
  /// @return mixed
  ///
  dynamic getFunctionHint(Function $callback) {
    // $function = new ReflectionFunction($callback);

    // if ($function->getNumberOfParameters() == 0) {
    //     return;
    // }

    // $expected = $function->getParameters()[0];

    // if (! $expected->getClass()) {
    //     return;
    // }

    // return $expected->getClass()->name;
  }

  ///
  /// Fire all of the resolving callbacks.
  ///
  /// @param  string  $abstract
  /// @param  mixed   $object
  /// @return void
  ///
  dynamic fireResolvingCallbacks($abstract, $object) {
    // this. fireCallbackArray($object, this. globalResolvingCallbacks);

    // this. fireCallbackArray(
    //     $object, this. getCallbacksForType(
    //         $abstract, $object, this. resolvingCallbacks
    //     )
    // );

    // this. fireCallbackArray($object, this. globalAfterResolvingCallbacks);

    // this. fireCallbackArray(
    //     $object, this. getCallbacksForType(
    //         $abstract, $object, this. afterResolvingCallbacks
    //     )
    // );
  }

  ///
  /// Get all callbacks for a given type.
  ///
  /// @param  string  $abstract
  /// @param  object  $object
  /// @param  array   $callbacksPerType
  ///
  /// @return array
  ///
  dynamic getCallbacksForType($abstract, $object, dynamic $callbacksPerType) {
    // $results = [];

    // foreach ($callbacksPerType as $type => $callbacks) {
    //     if ($type === $abstract || $object instanceof $type) {
    //         $results = array_merge($results, $callbacks);
    //     }
    // }

    // return $results;
  }

  ///
  /// Fire an array of callbacks with an object.
  ///
  /// @param  mixed  $object
  /// @param  array  $callbacks
  /// @return void
  ///
  dynamic fireCallbackArray($object, $callbacks) {
    // foreach ($callbacks as $callback) {
    //     $callback($object, $this);
    // }
  }

  ///
  /// Determine if a given type is shared.
  ///
  /// @param  string  $abstract
  /// @return bool
  ///
  bool isShared(abstract) {
    abstract = this.normalize(abstract);

    if (this.instances[abstract] != null) {
      return true;
    }

    if (!Utils.isset(this.bindings[abstract]['shared'])) {
      return false;
    }

    return this.bindings[abstract]['shared'] == true;
  }

  ///
  /// Determine if the given concrete is buildable.
  ///
  /// @param  mixed   $concrete
  /// @param  string  $abstract
  /// @return bool
  ///
  bool isBuildable(concrete, abstract) {
    return concrete == abstract || concrete is Function;
  }

  ///
  /// Get the alias for an abstract if available.
  ///
  /// @param  string  $abstract
  /// @return string
  ///
  dynamic getAlias(abstract) {
    if (!Utils.isset(this.aliases[abstract])) {
      return abstract;
    }

    return this.getAlias(this.aliases[abstract]);
  }

  ///
  /// Get the container's bindings.
  ///
  /// @return array
  ///
  dynamic getBindings() {
    return this.bindings;
  }

  ///
  /// Drop all of the stale instances and aliases.
  ///
  /// @param  string  $abstract
  /// @return void
  ///
  void dropStaleInstances(abstract) {
    this.instances.remove(abstract);
    this.aliases.remove(abstract);
    // unset(this.instances[abstract], this.aliases[abstract]);
  }

  ///
  /// Remove a resolved instance from the instance cache.
  ///
  /// @param  string  $abstract
  /// @return void
  ///
  dynamic forgetInstance(abstract) {
    //unset(this.instances[this.normalize(abstract)]);

    this.instances.remove(this.normalize(abstract));
  }

  ///
  /// Clear all of the instances from the container.
  ///
  /// @return void
  ///
  dynamic forgetInstances() {
    this.instances = {};
  }

  ///
  /// Flush the container of all bindings and resolved instances.
  ///
  /// @return void
  ///
  dynamic flush() {
    this.aliases = {};
    this.resolvedProp = {};
    this.bindings = {};
    this.instances = {};
  }

  ///
  /// Set the globally available instance of the container.
  ///
  /// @return static
  ///
  dynamic getInstance() {
    return Container.instanceProp;
  }

  ///
  /// Set the shared instance of the container.
  ///
  /// @param  \Illuminate\Contracts\Container\Container  $container
  /// @return void
  ///
  dynamic setInstance(Container container) {
    Container.instanceProp = container;
  }

  ///
  /// Determine if a given offset exists.
  ///
  /// @param  string  $key
  /// @return bool
  ///
  bool offsetExists(String key) {
    return this.bound(key);
  }

  ///
  /// Get the value at a given offset.
  ///
  /// @param  string  $key
  /// @return mixed
  ///
  dynamic offsetGet(String key) {
    return this.make(key);
  }

  ///
  /// Set the value at a given offset.
  ///
  /// @param  string  $key
  /// @param  mixed   $value
  /// @return void
  ///
  void offsetSet(String key, dynamic value) {
    // If the value is not a Closure, we will make it one. This simply gives
    // more "drop-in" replacement functionality for the Pimple which this
    // container's simplest functions are base modeled and built after.
    if (!value is Function) {
      value = () {
        return value;
      };
    }

    this.bind(key, value);
  }

  operator [](String key) => offsetGet(key); // get
  operator []=(String key, dynamic value) => offsetSet(key, value); // set

  ///
  /// Unset the value at a given offset.
  ///
  /// @param  string  $key
  /// @return void
  ///
  void offsetUnset(String key) {
    key = this.normalize(key);
    this.bindings.remove(key);
    this.instances.remove(key);
    this.resolvedProp.remove(key);
    //unset($this->bindings[$key], $this->instances[$key], $this->resolved[$key]);
  }

  /**
     * Dynamically access container services.
     *
     * @param  string  $key
     * @return mixed
     */
  //  dynamic __get($key)
  //   {
  //       return $this[$key];
  //   }

  /**
     * Dynamically set container services.
     *
     * @param  string  $key
     * @param  mixed   $value
     * @return void
     */
  // dynamic __set($key, $value)
  // {
  //     $this[$key] = $value;
  // }
}

import 'package:eloquent/eloquent.dart';
import 'contextual_binding_builder.dart';

/// A type cannot be resolved: nothing is bound to it, or it is bound to
/// itself (without reflection the container cannot build a class by name).
class BindingResolutionException implements Exception {
  BindingResolutionException(this.message);

  final String message;

  @override
  String toString() => 'BindingResolutionException: $message';
}

/// IoC container (a port of Laravel 5.2's), without reflection.
///
/// A binding is a factory function, called with `()`, `(container)` or
/// `(container, parameters)` according to the parameters it declares.
/// Callbacks (extenders, resolving callbacks) get `(value)` or
/// `(value, container)`.
///
/// ```dart
/// final c = Container()
///   ..singleton('db', (Container c) => Database(c.make('config')))
///   ..instance('config', {'host': 'localhost'});
/// final db = c.make('db');
/// ```
class Container {
  /// The globally available container, set by [setInstance].
  static Container? instanceProp;

  /// The abstracts that have been resolved.
  Map<String, dynamic> resolvedProp = {};

  /// The bindings: abstract → `{'concrete': factory, 'shared': bool}`.
  Map<String, dynamic> bindings = {};

  /// The shared instances.
  Map<String, dynamic> instances = {};

  /// The aliases: alias → abstract.
  Map<String, dynamic> aliases = {};

  /// The extender callbacks of each abstract.
  Map<String, dynamic> extenders = {};

  /// The abstracts of each tag.
  Map<String, dynamic> tags = {};

  /// The abstracts being built, innermost last.
  List buildStack = [];

  /// The contextual bindings: building abstract → needed abstract →
  /// implementation.
  Map contextual = {};

  /// The rebound callbacks of each abstract.
  Map reboundCallbacks = {};

  /// The resolving callbacks for every abstract.
  List globalResolvingCallbacks = [];

  /// The after resolving callbacks for every abstract.
  List globalAfterResolvingCallbacks = [];

  /// The resolving callbacks of each abstract.
  Map<String, List<Function>> resolvingCallbacks = {};

  /// The after resolving callbacks of each abstract.
  Map<String, List<Function>> afterResolvingCallbacks = {};

  /// Starts a contextual binding: what [concrete] gets when its factory
  /// makes another abstract.
  ///
  /// ```dart
  /// c.when('report').needs('logger').give('memory_logger');
  /// ```
  ContextualBindingBuilder when(String concrete) {
    concrete = this.normalize(concrete);
    return ContextualBindingBuilder(this, concrete);
  }

  /// Whether [abstractP] has a binding, an instance or is an alias.
  bool bound(dynamic abstractP) {
    var abstract = this.normalize(abstractP);

    // containsKey: an instance may be null or an empty collection.
    return this.bindings.containsKey(abstract) ||
        this.instances.containsKey(abstract) ||
        this.isAlias(abstract);
  }

  /// Whether [abstract] has been resolved or has an instance.
  bool resolved(dynamic abstract) {
    abstract = this.normalize(abstract);

    if (this.isAlias(abstract)) {
      abstract = this.getAlias(abstract);
    }

    return this.resolvedProp[abstract] == true ||
        this.instances.containsKey(abstract);
  }

  /// Whether [name] is an alias.
  bool isAlias(String name) {
    return this.aliases.containsKey(this.normalize(name));
  }

  /// Binds [abstract] to [concrete]: a factory function, or the name of
  /// another abstract to resolve. A map `{abstract: alias}` also registers
  /// the alias. With [shared] the first value made is kept (see [singleton]).
  void bind(abstract, [dynamic concrete, bool shared = false]) {
    if (Utils.is_map(abstract)) {
      var res = this.extractAlias(abstract);
      abstract = res.first;
      var alias = res.last;
      this.alias(abstract, alias);
    }
    abstract = this.normalize(abstract);
    concrete = this.normalize(concrete);

    this.dropStaleInstances(abstract);

    if (Utils.is_null(concrete)) {
      concrete = abstract;
    }

    // A name is wrapped in a factory that resolves it, so extenders work the
    // same for every binding.
    if (concrete is! Function) {
      concrete = this.getClosure(abstract, concrete);
    }

    this.bindings[abstract] = {'concrete': concrete, 'shared': shared};

    // Objects that already resolved [abstract] are told about the new one.
    if (this.resolved(abstract)) {
      this.rebound(abstract);
    }
  }

  /// The factory of a binding to the name [concrete]: it resolves
  /// [concrete], or throws when [concrete] is [abstract] itself.
  Function getClosure(String abstract, String concrete) {
    return (Container c, [dynamic parameters]) {
      // Laravel builds a class bound to itself by reflection; here there is
      // nothing to build.
      if (abstract == concrete) {
        throw BindingResolutionException(
            'Target [$concrete] is not instantiable: bind a factory function.');
      }
      return c.make(concrete, parameters);
    };
  }

  /// When [concrete] is being built, [abstract] resolves to
  /// [implementation] (a factory or a name). See [when].
  void addContextualBinding(
      dynamic concrete, dynamic abstract, dynamic implementation) {
    (this.contextual[this.normalize(concrete)] ??=
        {})[this.normalize(abstract)] = this.normalize(implementation);
  }

  /// [bind] only when [abstract] is not bound yet.
  void bindIf(String abstract, [dynamic concrete, bool shared = false]) {
    if (!this.bound(abstract)) {
      this.bind(abstract, concrete, shared);
    }
  }

  /// [bind] with the first value made kept and returned from then on.
  void singleton(dynamic abstract, [dynamic concrete]) {
    this.bind(abstract, concrete, true);
  }

  /// Wraps [closure] so it runs once and its value is returned from then on.
  Function share(Function closure) {
    var resolved = false;
    dynamic object;
    return (Container container) {
      if (!resolved) {
        object = _callFactory(closure, container, null);
        resolved = true;
      }

      return object;
    };
  }

  /// Decorates [abstractP] with [closure], which gets `(value)` or
  /// `(value, container)` and returns the new value: right away for an
  /// instance, otherwise each time it is made.
  void extend(dynamic abstractP, Function closure) {
    var abstract = this.normalize(abstractP);

    if (this.instances.containsKey(abstract)) {
      this.instances[abstract] =
          _callWithContainer(closure, this.instances[abstract]);
      this.rebound(abstract);
    } else {
      (this.extenders[abstract] ??= []).add(closure);
    }
  }

  /// Registers [instanceP] as the shared value of [abstractP].
  void instance(String abstractP, dynamic instanceP) {
    var abstract = this.normalize(abstractP);

    this.aliases.remove(abstract);

    var bound = this.bound(abstract);

    this.instances[abstract] = instanceP;

    if (bound) {
      this.rebound(abstract);
    }
  }

  /// Adds [abstracts] to each of [tags].
  void tag(List abstracts, List<String> tags) {
    for (var tag in tags) {
      if (!Utils.isset(this.tags[tag])) {
        this.tags[tag] = [];
      }

      for (var abstract in abstracts) {
        this.tags[tag].add(this.normalize(abstract));
      }
    }
  }

  /// The values of the abstracts tagged [tag].
  List tagged(String tag) {
    var results = [];

    if (Utils.isset(this.tags[tag])) {
      for (var abstract in this.tags[tag]) {
        results.add(this.make(abstract));
      }
    }

    return results;
  }

  /// Makes [alias] another name for [abstract].
  void alias(String abstract, String alias) {
    this.aliases[alias] = this.normalize(abstract);
  }

  /// `[abstract, alias]` from a `{abstract: alias}` [definition].
  List extractAlias(Map<String, dynamic> definition) {
    return [definition.entries.first.key, definition.entries.first.value];
  }

  /// Runs [callback] with `(container, value)` each time [abstract] is bound
  /// again, and returns its current value when it is bound.
  dynamic rebinding(String abstract, Function callback) {
    var key = this.normalize(abstract);
    (this.reboundCallbacks[key] ??= []).add(callback);

    if (this.bound(abstract)) {
      return this.make(abstract);
    }
    return null;
  }

  /// Not supported: Laravel calls [methodName] on [target] by name, which
  /// needs reflection. Use [rebinding] with a callback instead.
  dynamic refresh(abstract, target, String methodName) {
    throw UnsupportedError('refresh() calls a method by name; use '
        'rebinding(abstract, (container, instance) => target.$methodName(instance)).');
  }

  /// Runs the rebound callbacks of [abstract] with its new value.
  void rebound(abstract) {
    var instance = this.make(abstract);

    for (var callback in this.getReboundCallbacks(abstract)) {
      callback(this, instance);
    }
  }

  /// Calls a binding [factory] with the arguments it declares: `()`,
  /// `(container)` or `(container, parameters)`.
  dynamic _callFactory(Function factory, Container container, parameters) {
    final dynamic f = factory;
    if (factory is dynamic Function(Never, Never)) {
      return f(container, parameters);
    }
    if (factory is dynamic Function(Never)) return f(container);
    if (factory is dynamic Function()) return f();
    throw ArgumentError.value(factory, 'factory',
        'Expected (), (container) or (container, parameters).');
  }

  /// Calls [callback] with `(value, container)` or `(value)`, as PHP ignores
  /// the arguments a closure does not declare.
  dynamic _callWithContainer(Function callback, dynamic value) {
    final dynamic f = callback;
    if (callback is dynamic Function(Never, Never)) return f(value, this);
    return f(value);
  }

  /// The rebound callbacks of [abstract].
  List getReboundCallbacks(abstract) {
    return this.reboundCallbacks[abstract] ?? [];
  }

  /// A function that [call]s [callback] with [parameters].
  Function wrap(Function callback, [List parameters = const []]) {
    return () {
      return this.call(callback, parameters);
    };
  }

  /// Calls [callback] with [parameters] as its positional arguments.
  ///
  /// Without reflection the dependencies are not injected, and
  /// `Class@method` strings (or a [defaultMethod]) are not supported.
  dynamic call(dynamic callback,
      [parameters = const [], String? defaultMethod]) {
    if (this.isCallableWithAtSign(callback) || defaultMethod != null) {
      return this.callClass(callback, parameters, defaultMethod);
    }

    return Function.apply(callback as Function, List.of(parameters as List));
  }

  /// Whether [callback] is a `Class@method` string.
  bool isCallableWithAtSign(dynamic callback) {
    return Utils.is_string(callback) && Utils.strpos(callback, '@') != false;
  }

  /// Not supported: calling a method by name (`Class@method`) needs
  /// reflection.
  dynamic callClass(target, [parameters = const [], String? defaultMethod]) {
    throw UnsupportedError('Class@method callbacks are not supported '
        '($target${defaultMethod == null ? '' : ', $defaultMethod'}); pass a '
        'Function.');
  }

  /// Resolves [abstract]: its instance, or the value of its factory (with
  /// [parameters]), decorated by its extenders. A shared binding keeps the
  /// value. Throws [BindingResolutionException] when nothing is bound.
  dynamic make(abstract, [dynamic parameters]) {
    abstract = this.getAlias(this.normalize(abstract));

    if (this.instances.containsKey(abstract)) {
      return this.instances[abstract];
    }

    var concrete = this.getConcrete(abstract);

    var objectL;
    // The abstract being built is on the build stack, so the types its
    // factory makes use its contextual bindings (when(abstract).needs(...)).
    this.buildStack.add(abstract);
    try {
      if (this.isBuildable(concrete, abstract)) {
        objectL = this.build(concrete, parameters);
      } else {
        objectL = this.make(concrete, parameters);
      }
    } finally {
      this.buildStack.removeLast();
    }

    for (var extender in this.getExtenders(abstract)) {
      objectL = _callWithContainer(extender, objectL);
    }

    if (this.isShared(abstract)) {
      this.instances[abstract] = objectL;
    }

    this.fireResolvingCallbacks(abstract, objectL);

    this.resolvedProp[abstract] = true;

    return objectL;
  }

  /// What [abstract] resolves to: its contextual binding, its factory, or
  /// [abstract] itself when nothing is bound.
  dynamic getConcrete(String abstract) {
    var concrete = this.getContextualConcrete(abstract);
    if (!Utils.is_null(concrete)) {
      return concrete;
    }

    if (!this.bindings.containsKey(abstract)) {
      return abstract;
    }

    return this.bindings[abstract]['concrete'];
  }

  /// The contextual binding of [abstract] for the abstract being built, or
  /// null.
  dynamic getContextualConcrete(String abstract) {
    if (this.buildStack.isEmpty) return null;
    return this.contextual[this.buildStack.last]?[abstract];
  }

  /// [service] without leading backslashes (PHP class names).
  dynamic normalize(service) {
    return Utils.is_string(service) ? Utils.ltrim(service, '\\\\') : service;
  }

  /// The extender callbacks of [abstract].
  List getExtenders(dynamic abstract) {
    return this.extenders[abstract] ?? [];
  }

  /// Calls the factory [concrete] with [parameters]. Throws
  /// [BindingResolutionException] for a name: Laravel instantiates the class
  /// by reflection, which Dart does not have.
  dynamic build(dynamic concrete, [dynamic parameters]) {
    if (concrete is Function) {
      return _callFactory(concrete, this, parameters);
    }

    final building = this.buildStack.length > 1
        ? ' while building [${this.buildStack.sublist(0, this.buildStack.length - 1).join(', ')}]'
        : '';
    throw BindingResolutionException(
        'Target [$concrete] is not bound or instantiable$building.');
  }

  /// Runs [callback] each time [abstract] is resolved; with only a function,
  /// for every abstract. The callback gets `(value)` or `(value, container)`.
  void resolving(abstract, [Function? callback]) {
    if (callback == null && abstract is Function) {
      this.resolvingCallback(abstract);
    } else {
      (this.resolvingCallbacks[this.normalize(abstract)] ??= []).add(callback!);
    }
  }

  /// Like [resolving], after the resolving callbacks.
  void afterResolving(abstract, [Function? callback]) {
    if (callback == null && abstract is Function) {
      this.afterResolvingCallback(abstract);
    } else {
      (this.afterResolvingCallbacks[this.normalize(abstract)] ??= [])
          .add(callback!);
    }
  }

  /// Runs [callback] each time any abstract is resolved. (Laravel picks the
  /// type from the closure's type hint, which needs reflection.)
  void resolvingCallback(Function callback) {
    this.globalResolvingCallbacks.add(callback);
  }

  /// Runs [callback] after any abstract is resolved.
  void afterResolvingCallback(Function callback) {
    this.globalAfterResolvingCallbacks.add(callback);
  }

  /// Runs the global and [abstract]'s resolving callbacks, then the after
  /// resolving ones, with [object].
  void fireResolvingCallbacks(abstract, object) {
    this.fireCallbackArray(object, this.globalResolvingCallbacks);

    this.fireCallbackArray(object,
        this.getCallbacksForType(abstract, object, this.resolvingCallbacks));

    this.fireCallbackArray(object, this.globalAfterResolvingCallbacks);

    this.fireCallbackArray(
        object,
        this.getCallbacksForType(
            abstract, object, this.afterResolvingCallbacks));
  }

  /// The callbacks of [abstract] in [callbacksPerType] (by name only:
  /// Laravel also matches the object's class, which needs reflection).
  List<Function> getCallbacksForType(
      abstract, object, Map<String, List<Function>> callbacksPerType) {
    return callbacksPerType[abstract] ?? const [];
  }

  /// Runs each of [callbacks] with [object].
  void fireCallbackArray(object, List callbacks) {
    for (final callback in callbacks) {
      _callWithContainer(callback as Function, object);
    }
  }

  /// Whether [abstract] has an instance or a shared binding.
  bool isShared(abstract) {
    abstract = this.normalize(abstract);

    if (this.instances.containsKey(abstract)) {
      return true;
    }

    final binding = this.bindings[abstract];
    return binding != null && binding['shared'] == true;
  }

  /// Whether [concrete] is built directly (a factory, or [abstract] itself)
  /// instead of being resolved as another name.
  bool isBuildable(concrete, abstract) {
    return concrete == abstract || concrete is Function;
  }

  /// The abstract [abstract] is an alias of (following chains), or
  /// [abstract] itself.
  dynamic getAlias(abstract) {
    if (!this.aliases.containsKey(abstract)) {
      return abstract;
    }

    return this.getAlias(this.aliases[abstract]);
  }

  /// The bindings.
  Map<String, dynamic> getBindings() {
    return this.bindings;
  }

  /// Removes the instance and the alias named [abstract].
  void dropStaleInstances(abstract) {
    this.instances.remove(abstract);
    this.aliases.remove(abstract);
  }

  /// Removes the instance of [abstract].
  void forgetInstance(abstract) {
    this.instances.remove(this.normalize(abstract));
  }

  /// Removes every instance.
  void forgetInstances() {
    this.instances = {};
  }

  /// Removes the aliases, bindings, instances and resolved marks.
  void flush() {
    this.aliases = {};
    this.resolvedProp = {};
    this.bindings = {};
    this.instances = {};
  }

  /// The global container set by [setInstance].
  Container? getInstance() {
    return Container.instanceProp;
  }

  /// Sets the global container.
  void setInstance(Container container) {
    Container.instanceProp = container;
  }

  /// Whether [key] is [bound].
  bool offsetExists(String key) {
    return this.bound(key);
  }

  /// [make] of [key].
  dynamic offsetGet(String key) {
    return this.make(key);
  }

  /// Binds [key] to [value]; a value that is not a function is returned as
  /// is.
  void offsetSet(String key, dynamic value) {
    if (value is! Function) {
      final shared = value;
      value = () => shared;
    }

    this.bind(key, value);
  }

  /// [make] of [key].
  operator [](String key) => offsetGet(key);

  /// Binds [key] to [value] (see [offsetSet]).
  operator []=(String key, dynamic value) => offsetSet(key, value);

  /// Removes the binding, instance and resolved mark of [key].
  void offsetUnset(String key) {
    key = this.normalize(key);
    this.bindings.remove(key);
    this.instances.remove(key);
    this.resolvedProp.remove(key);
  }
}

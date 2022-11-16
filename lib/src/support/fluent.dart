import 'dart:convert';

import '../utils/utils.dart';

class Fluent {
  ///
  /// All of the attributes set on the container.
  ///
  /// @var array
  ///
  Map<String, dynamic> attributes = {};

  ///
  /// Create a new fluent container instance.
  ///
  /// @param  array|object    $attributes
  /// @return void
  ///
  Fluent([Map<String, dynamic>? attributesP]) {
    if (attributesP != null) {
      for (var at in attributesP.entries) {
        attributes.addAll({at.key: at.value});
      }
    }
  }

  operator [](String key) => offsetGet(key); // get
  operator []=(String key, dynamic value) => offsetSet(key, value); // set

  ///
  /// Get an attribute from the container.
  ///
  /// @param  string  $key
  /// @param  mixed   $default
  /// @return mixed
  ///
  dynamic get(String key, [dynamic defaultP]) {
    // for (var item in attributes.entries) {
    //   if (item.key == key) {
    //     return item;
    //   }
    // }
    if (attributes.containsKey(key)) {
      return attributes[key];
    }

    return Utils.value(defaultP);
  }

  ///
  /// Get the attributes from the container.
  ///
  /// @return array
  ///
  Map getAttributes() {
    return attributes;
  }

  ///
  /// Convert the Fluent instance to JSON.
  ///
  /// @param  int  $options
  /// @return string
  ///
  String toJson() {
    return jsonEncode(attributes);
  }

  ///
  /// Determine if the given offset exists.
  ///
  /// @param  string  $offset
  /// @return bool
  ///
  bool offsetExists(String offset) {
    // return isset($this->{$offset});
    return this.attributes.containsKey(offset);
  }

  ///
  /// Get the value for a given offset.
  ///
  /// @param  string  $offset
  /// @return mixed
  ///
  dynamic offsetGet(String offset) {
    //return $this->{$offset};
    //return false;
    return get(offset);
  }

  ///
  /// Set the value at the given offset.
  ///
  /// @param  string  $offset
  /// @param  mixed   $value
  /// @return void
  ///
  void offsetSet(String offset, dynamic value) {
    //$this->{$offset} = $value;
    this.attributes[offset] = value;
  }

  ///
  /// Unset the value at the given offset.
  ///
  /// @param  string  $offset
  /// @return void
  ///
  void offsetUnset(String offset) {
    //unset($this->{$offset});
    this.attributes.remove(offset);
  }

  ///
  /// Handle dynamic calls to the container to set attributes.
  ///
  /// @param  string  $method
  /// @param  array   $parameters
  /// @return $this
  ///
  //  __call($method, $parameters)
  // {
  //     $this->attributes[$method] = count($parameters) > 0 ? $parameters[0] : true;
  //     return $this;
  // }

  ///
  /// Dynamically set the value of an attribute.
  ///
  /// @param  string  $key
  /// @param  mixed   $value
  /// @return void
  ///
  void set(String key, dynamic value) {
    attributes[key] = value;
  }

  ///
  /// Dynamically check if an attribute is set.
  ///
  /// @param  string  $key
  /// @return bool
  ///
  bool isset(String key) {
    return attributes.containsKey(key);
  }

  ///
  /// Dynamically unset an attribute.
  ///
  /// @param  string  $key
  /// @return void
  ///
  void unset(String key) {
    attributes.remove(key);
  }
}

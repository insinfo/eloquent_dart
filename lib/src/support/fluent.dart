import 'dart:convert';

import '../utils/utils.dart';

class Fluent {
  /// The attributes set on this container.
  Map<String, dynamic> attributes = {};

  /// Creates a container with a copy of [attributesP], if given.
  Fluent([Map<String, dynamic>? attributesP]) {
    if (attributesP != null) {
      for (var at in attributesP.entries) {
        attributes.addAll({at.key: at.value});
      }
    }
  }

  operator [](String key) => offsetGet(key); // get
  operator []=(String key, dynamic value) => offsetSet(key, value); // set

  /// Returns the attribute [key], or [defaultP] when it is not set (called
  /// first when it is a function).
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

  /// Returns [attributes] itself, not a copy as in PHP.
  Map getAttributes() {
    return attributes;
  }

  /// Encodes [attributes] as JSON.
  ///
  /// It returns a String, as Laravel's `toJson`, so `jsonEncode(fluent)`
  /// gives a JSON string, not an object: encode [attributes] instead.
  String toJson() {
    return jsonEncode(attributes);
  }

  /// Returns whether the attribute [offset] is set and not null, as PHP's
  /// `isset`.
  bool offsetExists(String offset) {
    return this.attributes[offset] != null;
  }

  /// Returns the attribute [offset], or null when it is not set.
  dynamic offsetGet(String offset) {
    return get(offset);
  }

  /// Sets the attribute [offset] to [value].
  void offsetSet(String offset, dynamic value) {
    this.attributes[offset] = value;
  }

  /// Removes the attribute [offset].
  void offsetUnset(String offset) {
    this.attributes.remove(offset);
  }

  /// Sets the attribute [key] to [value].
  void set(String key, dynamic value) {
    attributes[key] = value;
  }

  /// Returns whether the attribute [key] is set and not null, as PHP's
  /// `isset`.
  bool isset(String key) {
    return attributes[key] != null;
  }

  /// Removes the attribute [key].
  void unset(String key) {
    attributes.remove(key);
  }
}

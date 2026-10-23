//import 'dart:mirrors';
import 'package:intl/intl.dart';

import 'dart:math';

enum StringCase { CASE_UPPER, CASE_LOWER }

class Utils {
  static const int intMinValueNative = -9223372036854775808;
  static const int intMaxValueNative = 9223372036854775807;

  static const int intMinValueJS = -9007199254740992;
  static const int intMaxValueJS = 9007199254740992;

  /// Converts a camelCase or PascalCase [input] to snake_case.
  static String toSnakeCase(String input) {
    // Insert "_" before each upper-case letter that follows a lower-case
    // letter or a digit.
    final RegExp exp = RegExp(r'(?<=[a-z0-9])([A-Z])');
    return input
        .replaceAllMapped(exp, (Match m) => '_${m.group(0)}')
        .toLowerCase();
  }

  /// Returns the results of calling [callback] on each element of [values].
  static List array_map(Function callback, List values) {
    var result = [];

    values.forEach((element) {
      result.add(callback(element));
    });

    return result;
  }

  /// Returns the elements of [array] for which [callback] returns true.
  static List array_filter(List array, Function callback) {
    var result = [];

    array.forEach((element) {
      if (callback(element)) {
        result.add(element);
      }
    });

    return result;
  }

  /// Returns whether [array] contains [needle].
  static bool in_array(dynamic needle, List array) {
    return array.contains(needle);
  }

  /// Joins [pieces] into a string, separated by [glue].
  static String implode(String glue, List pieces) {
    return pieces.join(glue);
  }

  /// Replaces every occurrence of [search] in [subject] with [replace].
  ///
  /// [search] is a [Pattern] or a list of patterns.
  static String str_replace(dynamic search, String replace, String subject) {
    var result = subject;
    if (search is List) {
      for (var s in search) {
        result = result.replaceAll(s, replace);
      }
    } else {
      result = result.replaceAll(search, replace);
    }

    return result;
  }

  /// Returns [value], or the result of calling it when it is a function.
  static dynamic value(dynamic value) {
    return value is Function ? value() : value;
  }

  /// Converts [str] to lower case.
  static String strtolower(String str) {
    return str.toLowerCase();
  }

  /// Returns the index of the first occurrence of [needle] in [str], or
  /// `false` when there is none (as PHP's `strpos`).
  static dynamic strpos(String str, Pattern needle) {
    var index = str.indexOf(needle);
    if (index == -1) {
      return false;
    }
    return index;
  }

  /// Splits [string] at each [separator].
  ///
  /// With [limit], only the first [limit] pieces are returned: unlike PHP,
  /// the rest of the string is dropped, not kept in the last piece. A
  /// [limit] of 0 or less returns an empty list.
  static List explode(Pattern separator, String string, [int? limit]) {
    var items = string.split(separator);
    if (limit == null) {
      return items;
    } else {
      limit = limit > items.length ? items.length : limit;
      var result = [];
      for (var i = 0; i < limit; i++) {
        result.add(items[i]);
      }
      return result;
    }
  }

  /// Returns the number of elements in [items].
  static int count(Iterable items) {
    return items.length;
  }

  /// Returns [string] with its first character in upper case.
  static String ucfirst(String string) {
    if (string.length == 0) {
      return string;
    } else if (string.length == 1) {
      return string[0].toUpperCase();
    }

    return string[0].toUpperCase() + string.substring(1);
  }

  /// Splits the [valueP] and [keyP] arguments of [array_pluck] into paths
  /// and returns `[value, key]`.
  ///
  /// Strings are trimmed and split at the dots; lists are kept, their string
  /// segments trimmed. A null [keyP] stays null.
  static List explodePluckParameters(dynamic valueP, dynamic keyP) {
    // Trim valueP when it is a String.
    if (valueP is String) {
      valueP = valueP.trim();
    }
    // Trim keyP when it is a String.
    if (keyP is String) {
      keyP = keyP.trim();
    }

    var value = is_string(valueP) ? explode('.', valueP) : valueP;
    var key = is_null(keyP) || is_array(keyP) ? keyP : explode('.', keyP);

    // Now, when 'value' or 'key' is a list, trim each String segment.
    if (value is List) {
      value = value.map((segment) {
        if (segment is String) return segment.trim();
        return segment;
      }).toList();
    }

    if (key is List) {
      key = key.map((segment) {
        if (segment is String) return segment.trim();
        return segment;
      }).toList();
    }

    return [value, key];
  }

  /// Returns the value at the path [valueP] in each item of [arrayP] (a List,
  /// or the values of a Map), like Laravel's `Arr::pluck`.
  ///
  /// Without [keyP] the result is a List; with [keyP] it is a Map from the
  /// value at the path [keyP] in each item to the value plucked from it. An
  /// item without a value at [keyP] is its own key.
  static array_pluck(dynamic arrayP, dynamic valueP, [dynamic keyP]) {
    if (arrayP == null) {
      return keyP != null ? <dynamic, dynamic>{} : <dynamic>[];
    }

    var results = keyP != null ? <dynamic, dynamic>{} : <dynamic>[];

    // Split "valueP" and "keyP" into paths.
    var re = explodePluckParameters(valueP, keyP);
    var valuePath = re[0];
    var keyPath = re[1];

    if (arrayP is List) {
      for (var item in arrayP) {
        var itemValue = data_get(item, valuePath);

        if (keyPath == null) {
          (results as List).add(itemValue);
        } else {
          var itemKey = data_get(item, keyPath);

          // Without a key, the whole item is the key.
          if (itemKey == null) {
            itemKey = item;
          }

          (results as Map)[itemKey] = itemValue;
        }
      }
    } else if (arrayP is Map) {
      for (var entry in arrayP.entries) {
        var itemValue = data_get(entry.value, valuePath);

        if (keyPath == null) {
          (results as List).add(itemValue);
        } else {
          var itemKey = data_get(entry.value, keyPath);

          if (itemKey == null) {
            itemKey = entry.value;
          }

          (results as Map)[itemKey] = itemValue;
        }
      }
    }

    return results;
  }

  /// Changes the case of the keys of [map] in place, nested
  /// `Map<String, dynamic>` values included, and returns [map].
  static Map<String, dynamic> map_change_key_case_sd(Map<String, dynamic> map,
      [StringCase typeCase = StringCase.CASE_LOWER]) {
    final entries = map.entries.toList();
    map.clear();
    for (final entry in entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        map_change_key_case_sd(value, typeCase);
      }
      final key = typeCase == StringCase.CASE_LOWER
          ? entry.key.toLowerCase()
          : entry.key.toUpperCase();
      map[key] = value;
    }
    return map;
  }

  /// Returns `array[key]`, or [defaultP] (called first when it is a
  /// function) when [array] is not a List or Map or has no such key.
  ///
  /// Like Laravel's `Arr::get`, without "dot" notation: [key] is a top-level
  /// key.
  static dynamic array_get(dynamic array, String key, [dynamic defaultP]) {
    if (!array_accessible(array)) {
      return value(defaultP);
    }

    // Return the key when it exists at the top level, else the default.
    if (array_exists(array, key)) {
      return array[key];
    }

    return value(defaultP);
  }

  /// Returns the value at the "dot" path [originalKey] in [target], or
  /// [defaultP] (called first when it is a function) when the path is
  /// missing.
  ///
  /// [originalKey] is a dotted String or a list of segments; null returns
  /// [target]. A `*` segment plucks the rest of the path from every element
  /// of a List.
  static dynamic data_get(dynamic target, dynamic originalKey,
      [dynamic defaultP]) {
    if (is_null(originalKey)) {
      return target;
    }

    // A String 'originalKey' is split at the dots; a List is copied so that
    // it is not modified:
    List<dynamic> segments;
    if (is_array(originalKey)) {
      segments = List.of(originalKey); // cria cópia
    } else {
      segments = explode('.', originalKey.toString());
    }

    while (segments.isNotEmpty) {
      var segment = segments.removeAt(0); // array_shift
      if (segment == '*') {
        if (!is_array(target)) {
          return value(defaultP);
        }
        var result = array_pluck(target, segments);
        return in_array('*', segments) ? array_collapse(result) : result;
      }

      if (array_accessible(target) && array_exists(target, segment)) {
        target = target[segment];
      } else {
        return value(defaultP);
      }
    }

    return target;
  }

  /// Returns whether [value] is a List or a Map.
  static bool array_accessible(dynamic value) {
    return is_array(value) ||
        is_map(value); // || $value instanceof ArrayAccess;
  }

  static bool is_object(dynamic value) {
    return value is Object;
  }

  /// Collapses a list of lists into one list.
  ///
  /// Elements that are not lists are skipped.
  static dynamic array_collapse(dynamic array) {
    var results = array is List ? [] : <String, dynamic>{};

    for (var values in array) {
      if (!is_array(values)) {
        continue;
      }
      if (results is List) {
        results = array_merge(results, values);
      } else if (results is Map<String, dynamic>) {
        results = map_merge_sd(results, values);
      }
    }

    return results;
  }

  /// Removes and returns the first element of a List, or the first entry
  /// (a [MapEntry]) of a Map.
  ///
  /// Returns null when [array] is empty or neither.
  static dynamic array_shift(dynamic array) {
    if (array is List && array.length > 0) {
      var fistItem = array.first;
      array.removeAt(0);
      return fistItem;
    } else if (array is Map && array.isNotEmpty) {
      var fistItem = array.entries.first;
      array.remove(fistItem.key);
      return fistItem;
    }

    return null;
  }

  /// Returns whether [key] exists in [array]: a key of a Map, or a valid
  /// index of a List.
  ///
  /// Throws an [Exception] when [array] is neither.
  static bool array_exists(dynamic array, dynamic key) {
    if (array is Map) {
      return map_key_exists(key, array);
    } else if (array is List) {
      return key >= 0 && array.length > key;
    }
    throw Exception('array is not List or Map');
  }

  /// Returns whether [haystack] contains any of [needles]; empty needles
  /// never match.
  static bool string_contains(String haystack, List<String> needles) {
    for (var needle in needles) {
      if (needle != '' && haystack.indexOf(needle) != -1) {
        return true;
      }
    }

    return false;
  }

  /// Returns the elements of [array1] followed by those of [array2]; null
  /// counts as an empty list.
  static List array_merge(List? array1, List? array2) {
    var a1 = array1;
    var a2 = array2;
    if (a1 == null) {
      a1 = [];
    }
    if (a2 == null) {
      a2 = [];
    }
    return [...a1, ...a2];
  }

  /// Returns the elements of [array1] followed by those of [array2].
  static List<String> array_merge_ss(List<String> array1, List<String> array2) {
    return [...array1, ...array2];
  }

  /// Returns the elements of [array1] followed by those of [array2].
  static List<Map<String, dynamic>> array_merge_ms(
      List<Map<String, dynamic>> array1, List<Map<String, dynamic>> array2) {
    return [...array1, ...array2];
  }

  /// Returns the elements of [array1] followed by those of [array2].
  ///
  /// Throws an [Exception] when either is null.
  static List<String> array_merge_sa(
      List<String>? array1, List<String>? array2) {
    if (array1 == null) {
      throw Exception(
          'array_merge(): Expected parameter 1 to be an array, null given');
    }
    if (array2 == null) {
      throw Exception(
          'array_merge(): Expected parameter 2 to be an array, null given');
    }
    return [...array1, ...array2];
  }

  /// Flattens the nested lists of [array] into one list, down to [depth]
  /// levels.
  static List array_flatten(List array, [int depth = intMaxValueNative]) {
    var result = [];

    for (var item in array) {
      //var item = itemP is Collection ? item.all() : item;

      if (is_array(item)) {
        if (depth == 1) {
          result = array_merge(result, item);
          continue;
        }

        result = array_merge(result, array_flatten(item, depth - 1));
        continue;
      }

      result.add(item);
    }

    return result;
  }

  /// Returns a new map with the entries of [firstMap] and [secondMap], the
  /// latter winning, as PHP's `array_merge` on associative arrays.
  ///
  /// ```dart
  /// var map1 = {'driver': 'pgsql', 'host': 'localhost'};
  /// var map2 = {'driver': 'mysql', 'host': '127.0.0.1'};
  /// print(map_merge_sd(map1, map2)); // {driver: mysql, host: 127.0.0.1}
  /// ```
  static Map<String, dynamic> map_merge_sd(
      Map<String, dynamic> firstMap, Map<String, dynamic> secondMap) {
    return {
      ...firstMap,
      ...secondMap,
    };
  }

  /// Sets [key] to [value] in [map] unless [key] is already there, and
  /// returns [map].
  static Map<String, dynamic> map_add_sd(
      Map<String, dynamic> map, String key, dynamic value) {
    if (map.containsKey(key)) {
      return map;
    }
    map[key] = value;

    return map;
  }

  /// Removes [keys] (a String or a `List<String>`) from [map] and its nested
  /// maps, in place, and returns [map].
  ///
  /// A key whose value is a map is not removed: its map is searched instead.
  /// Throws an [Exception] when [keys] is neither a String nor a
  /// `List<String>`.
  ///
  /// ```dart
  /// var map = {
  ///   'driver': 'mysql',
  ///   'host': '127.0.0.1',
  ///   'level1': {
  ///     'read': true,
  ///     'write': false,
  ///     'level2': {'banana': 'good'}
  ///   }
  /// };
  /// map_except_sd(map, ['read', 'write']);
  /// // {driver: mysql, host: 127.0.0.1, level1: {level2: {banana: good}}}
  /// ```
  static Map<String, dynamic> map_except_sd(
      Map<String, dynamic> map, dynamic keys) {
    if (keys is List<String>) {
      for (var key in keys) {
        map_unset_deep_sd(map, key);
      }
    } else if (keys is String) {
      map_unset_deep_sd(map, keys);
    } else {
      throw Exception('keys is not List<String> or String');
    }
    return map;
  }

  /// Removes [key] from [map] and its nested maps; see [map_except_sd].
  static void map_unset_deep_sd(Map<String, dynamic> map, String key) {
    var clone = <String, dynamic>{}..addAll(map);
    var length = clone.entries.length;
    var entries = clone.entries.toList();
    for (var i = 0; i < length; i++) {
      var entry = entries[i];
      if (entry.value is Map) {
        map_unset_deep_sd(map[entry.key], key);
      } else {
        if (entry.key == key) {
          map.remove(key);
        }
      }
    }
  }

  static int array_unshift(List array, dynamic value) {
    //var result = [...array, value];
    array.insert(0, value);
    return array.length;
  }

  /// Returns [numero] random indexes of [array], as PHP's `array_rand` picks
  /// random keys.
  ///
  /// The result is always a list, even for one index, and an index can
  /// repeat. Throws when [array] is empty.
  static dynamic array_rand(List array, [int numero = 1]) {
    var rng = Random();
    var len = array.length;

    var list = [];
    for (var i = 0; i < numero; i++) {
      list.add(rng.nextInt(len));
    }
    return list;
  }

  /// Returns whether [value] is a List.
  static bool is_array(dynamic value) {
    return value is List;
  }

  static bool is_map(dynamic value) {
    return value is Map;
  }

  /// Returns whether [value] is a bool.
  static bool is_bool(dynamic value) {
    return value is bool;
  }

  /// Returns whether [value] is a String.
  static bool is_string(dynamic value) {
    return value is String;
  }

  static bool array_is_empty(List val) {
    return val.isEmpty;
  }

  /// Returns whether [val] is `''`, null or 0, like PHP's `empty` (which
  /// also counts `false`, `'0'` and empty arrays).
  static bool empty(dynamic val) {
    if (val == '') {
      return true;
    } else if (val == null) {
      return true;
    } else if (val == 0) {
      return true;
    }
    return false;
  }

  /// Returns whether [val] is null.
  static bool is_null(dynamic val) {
    return val == null;
  }

  /// Returns whether [val] is null or an empty List or Map.
  static bool is_null_or_empty(dynamic val) {
    if (val is List) {
      return val.isEmpty;
    } else if (val is Map) {
      return val.isEmpty;
    }
    return val == null;
  }

  /// Returns whether [val] is set: false for null and for an empty List or
  /// Map.
  static bool isset(dynamic val) {
    if (val == null) {
      return false;
    } else if (val is List && val.isEmpty) {
      return false;
    } else if (val is Map && val.isEmpty) {
      return false;
    }
    return true;
  }

  static String trim(String str) {
    return str.trim();
  }

  static String strval(dynamic val) {
    return val.toString();
  }

  static bool map_key_exists(dynamic key, Map map) {
    return map.containsKey(key);
  }

  static dynamic map_first_key(Map map) {
    return map.entries.first.key;
  }

  /// Returns the last element of [array], or false when it is empty.
  static dynamic array_end(List array) {
    return array.isEmpty ? false : array.last;
  }

  static void var_dump(dynamic val) {
    print(val);
  }

  static int str_length(String str) {
    return str.length;
  }

  /// Returns whether [haystack] ends with [needles], a String or any element
  /// of a List.
  static bool endsWith(String haystack, dynamic needles) {
    if (needles is List) {
      for (var needle in needles) {
        if (needle == substr(haystack, -str_length(needle))) {
          return true;
        }
      }
    } else if (needles is String) {
      return haystack.endsWith(needles);
    }
    return false;
  }

  /// Removes the characters in [chars] from the start of [string]; null
  /// [chars] removes whitespace.
  ///
  /// [chars] goes into a regular expression character class as written, so
  /// `]`, `\`, `^` and `-` must be escaped.
  static ltrim(String string, [String? chars = " \n\r\t"]) {
    //chars =chars.replaceAll('from', replace)
    var pattern = chars != null ? RegExp('^[$chars]+') : RegExp(r'^\s+');
    return string.replaceAll(pattern, '');
  }

  /// Removes the last element of a List or the last entry of a Map.
  ///
  /// Unlike PHP's `array_pop`, it returns nothing. Throws a [StateError]
  /// when [array] is empty.
  static void array_pop(dynamic array) {
    var last;
    if (array is Map) {
      last = array.entries.last;
      array.remove(last.key);
    } else if (array is List) {
      last = array.last;
      array.removeLast();
    }
  }

  /// Returns the values of [map] as a list (PHP's `array_values`).
  static List map_values(Map map) {
    return map.values.toList();
  }

  /// Returns the part of [str] from [offset] on, at most [length] characters,
  /// as PHP's `substr`.
  ///
  /// A negative [offset] counts from the end. Unlike PHP, a negative
  /// [length] or an [offset] past the end throws a [RangeError].
  ///
  /// ```dart
  /// substr('abcdef', -2, 10); // 'ef'
  /// ```
  static String substr(String str, int offset, [int? length]) {
    // With length: take `length` characters from offset.
    if (length != null) {
      // Non-negative offset: the end is offset + length.
      if (offset >= 0) {
        length = offset + length;
        if (length > str.length) length = str.length;
        return str.substring(offset, length);
      } else {
        // Negative offset: start at str.length + offset.
        int start =
            str.length + offset; // por ex. offset=-2 => start = str.length-2
        int end = start + length;
        if (start < 0) start = 0;
        if (end > str.length) end = str.length;
        return str.substring(start, end);
      }
    } else {
      // Without length: from offset to the end.
      if (offset >= 0) {
        return str.substring(offset);
      } else {
        int start = str.length + offset;
        if (start < 0) start = 0;
        return str.substring(start);
      }
    }
  }

  /// Returns the larger of [value1] and [value2].
  static int_max(int value1, int value2) {
    return value1 > value2 ? value1 : value2;
  }

  static reset(List array) {
    return array.isEmpty ? false : array.first;
  }

  /// Returns the current time in microseconds since the Unix epoch.
  ///
  /// PHP's `microtime(true)` returns seconds instead.
  static int microtime() {
    return DateTime.now().microsecondsSinceEpoch;
  }

  static dynamic round(num numero) {
    return numero.round();
  }

  static String formatDate(DateTime dt, [String format = 'yyyy-MM-dd']) {
    final formatter = DateFormat(format);
    final formatted = formatter.format(dt);
    return formatted;
  }

  // Whether object_or_class has a method methodName (needs dart:mirrors).
  // Example:
  // class FooBar {
  //  String showMessage(String msg) {
  //    print("message $msg");
  //    return msg;
  //  }
  // }
  // var c = FooBar();
  // var result = Utils.method_exists(c, 'showMessage');
  // print(result);
  // true
  // static bool method_exists(dynamic object_or_class, String methodName) {
  //   var mirror = reflect(object_or_class);
  //   return mirror.type.instanceMembers.values
  //       .map((MethodMirror method) => MirrorSystem.getName(method.simpleName))
  //       .contains(methodName);
  // }

  // Whether object_or_class has a property propName (needs dart:mirrors).
  // static bool property_exists(dynamic object_or_class, String propName) {
  //   var mirror = reflect(object_or_class);
  //   return mirror.type.declarations.values
  //       .map((value) => MirrorSystem.getName(value.simpleName))
  //       .contains(propName);
  // }

  // Calls the method methodName of object_or_class (needs dart:mirrors).
  // Only tested with methods that do not return a Future.
  // static dynamic call_method(
  //   dynamic object_or_class,
  //   String methodName, [
  //   List<dynamic>? positionalArguments,
  //   Map<Symbol, dynamic> namedArguments = const <Symbol, dynamic>{},
  // ]) {
  //   var mirror = reflect(object_or_class);
  //   var methods = mirror.type.instanceMembers.entries;
  //   //print(methods);
  //   for (var m in methods) {
  //     //print(MirrorSystem.getName(m.value.simpleName));
  //     if (MirrorSystem.getName(m.value.simpleName) == methodName) {
  //       var result = mirror.invoke(
  //           m.value.simpleName,
  //           positionalArguments == null ? [] : positionalArguments,
  //           namedArguments);

  //       //var resultValue = await (result.reflectee as Future<MyData>);
  //       var resultValue = (result.reflectee as dynamic);

  //       return resultValue;
  //     }
  //   }
  // }

  static List array_fill(int start_index, int count, dynamic value) {
    return List.generate(count, (v) => value);
  }
}

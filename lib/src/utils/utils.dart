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
  static List arrayMap(Function callback, List values) {
    var result = [];

    values.forEach((element) {
      result.add(callback(element));
    });

    return result;
  }

  /// Returns the elements of [array] for which [callback] returns true.
  static List arrayFilter(List array, Function callback) {
    var result = [];

    array.forEach((element) {
      if (callback(element) as bool) {
        result.add(element);
      }
    });

    return result;
  }

  /// Returns whether [array] contains [needle].
  static bool inArray(dynamic needle, List array) {
    return array.contains(needle);
  }

  /// Joins [pieces] into a string, separated by [glue].
  static String implode(String glue, List pieces) {
    return pieces.join(glue);
  }

  /// Replaces every occurrence of [search] in [subject] with [replace].
  ///
  /// [search] is a [Pattern] or a list of patterns.
  static String strReplace(dynamic search, String replace, String subject) {
    var result = subject;
    if (search is List) {
      for (var s in search) {
        result = result.replaceAll(s as Pattern, replace);
      }
    } else {
      result = result.replaceAll(search as Pattern, replace);
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

  /// Splits [string] at each [separator], as PHP's `explode`.
  ///
  /// A positive [limit] returns at most [limit] pieces, the last one holding
  /// the rest of the string; 0 counts as 1. A negative [limit] leaves out
  /// that many pieces at the end.
  static List<String> explode(Pattern separator, String string, [int? limit]) {
    if (limit == null) {
      return string.split(separator);
    }
    if (limit < 0) {
      var items = string.split(separator);
      return items.length + limit <= 0
          ? <String>[]
          : items.sublist(0, items.length + limit);
    }
    // Split at the first limit - 1 separators only; empty matches are not
    // separators here.
    var result = <String>[];
    var start = 0;
    for (var match in separator.allMatches(string)) {
      if (result.length >= limit - 1) break;
      if (match.end == match.start) continue;
      result.add(string.substring(start, match.start));
      start = match.end;
    }
    result.add(string.substring(start));
    return result;
  }

  /// Returns the number of elements in [items].
  static int count(Iterable items) {
    return items.length;
  }

  /// Returns [string] with its first character in upper case.
  static String ucfirst(String string) {
    if (string.isEmpty) {
      return string;
    } else if (string.length == 1) {
      return string[0].toUpperCase();
    }

    return string[0].toUpperCase() + string.substring(1);
  }

  /// Splits the [valueP] and [keyP] arguments of [arrayPluck] into paths
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

    var value = valueP is String ? explode('.', valueP) : valueP;
    var key =
        keyP == null || keyP is List ? keyP : explode('.', keyP as String);

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
  /// item without a value at [keyP] is keyed by null (PHP uses `''`), so a
  /// later one replaces it.
  static arrayPluck(dynamic arrayP, dynamic valueP, [dynamic keyP]) {
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
        var itemValue = dataGet(item, valuePath);

        if (keyPath == null) {
          (results as List).add(itemValue);
        } else {
          // An item without a key value is keyed by null.
          (results as Map)[dataGet(item, keyPath)] = itemValue;
        }
      }
    } else if (arrayP is Map) {
      for (var entry in arrayP.entries) {
        var itemValue = dataGet(entry.value, valuePath);

        if (keyPath == null) {
          (results as List).add(itemValue);
        } else {
          (results as Map)[dataGet(entry.value, keyPath)] = itemValue;
        }
      }
    }

    return results;
  }

  /// Changes the case of the keys of [map] in place, nested
  /// `Map<String, dynamic>` values included, and returns [map].
  static Map<String, dynamic> mapChangeKeyCaseSd(Map<String, dynamic> map,
      [StringCase typeCase = StringCase.CASE_LOWER]) {
    final entries = map.entries.toList();
    map.clear();
    for (final entry in entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        mapChangeKeyCaseSd(value, typeCase);
      }
      final key = typeCase == StringCase.CASE_LOWER
          ? entry.key.toLowerCase()
          : entry.key.toUpperCase();
      map[key] = value;
    }
    return map;
  }

  /// Returns the value at the "dot" path [key] in [array], or [defaultP]
  /// (called first when it is a function) when [array] is not a List or Map
  /// or the path is missing, as Laravel's `Arr::get`.
  ///
  /// A top-level key that holds dots is found first; a List index may be a
  /// numeric String (`'items.0.id'`).
  static dynamic arrayGet(dynamic array, String key, [dynamic defaultP]) {
    if (!arrayAccessible(array)) {
      return value(defaultP);
    }

    // A top-level key wins, even when it has dots.
    if (arrayExists(array, key)) {
      return _offsetGet(array, key);
    }

    for (var segment in key.split('.')) {
      if (arrayAccessible(array) && arrayExists(array, segment)) {
        array = _offsetGet(array, segment);
      } else {
        return value(defaultP);
      }
    }

    return array;
  }

  /// Returns the value at the "dot" path [originalKey] in [target], or
  /// [defaultP] (called first when it is a function) when the path is
  /// missing.
  ///
  /// [originalKey] is a dotted String or a list of segments; null returns
  /// [target]. A List index may be a numeric String. A `*` segment plucks the
  /// rest of the path from every element of a List or value of a Map.
  static dynamic dataGet(dynamic target, dynamic originalKey,
      [dynamic defaultP]) {
    if (isNull(originalKey)) {
      return target;
    }

    // A String 'originalKey' is split at the dots; a List is copied so that
    // it is not modified:
    List<dynamic> segments;
    if (isArray(originalKey)) {
      segments = List.of(originalKey as List);
    } else {
      segments = explode('.', originalKey.toString());
    }

    while (segments.isNotEmpty) {
      var segment = segments.removeAt(0); // array_shift
      if (segment == '*') {
        if (!arrayAccessible(target)) {
          return value(defaultP);
        }
        var result = arrayPluck(target, segments);
        return inArray('*', segments) ? arrayCollapse(result) : result;
      }

      if (arrayAccessible(target) && arrayExists(target, segment)) {
        target = _offsetGet(target, segment);
      } else {
        return value(defaultP);
      }
    }

    return target;
  }

  /// Returns whether [value] is a List or a Map.
  static bool arrayAccessible(dynamic value) {
    return isArray(value) || isMap(value); // || $value instanceof ArrayAccess;
  }

  static bool isObject(dynamic value) {
    return value is Object;
  }

  /// Collapses the lists and maps in [array] (a List, or the values of a
  /// Map) into one, as Laravel's `Arr::collapse`; other elements are
  /// skipped.
  ///
  /// The result is a List when no element is a Map. Otherwise it is a Map,
  /// merged as PHP's `array_merge`: later String keys win and the elements
  /// of lists (and int keys) get the next int keys.
  static dynamic arrayCollapse(dynamic array) {
    var merged = <dynamic, dynamic>{};
    var nextIndex = 0;
    var hasMap = false;

    for (var values in array is Map ? array.values : array as Iterable) {
      if (values is List) {
        for (var item in values) {
          merged[nextIndex++] = item;
        }
      } else if (values is Map) {
        hasMap = true;
        values.forEach((key, item) {
          merged[key is int ? nextIndex++ : key] = item;
        });
      }
    }

    return hasMap ? merged : merged.values.toList();
  }

  /// Removes and returns the first element of a List, or the value of the
  /// first entry of a Map, as PHP's `array_shift`.
  ///
  /// Returns null when [array] is empty or neither.
  static dynamic arrayShift(dynamic array) {
    if (array is List && array.isNotEmpty) {
      return array.removeAt(0);
    } else if (array is Map && array.isNotEmpty) {
      return array.remove(array.keys.first);
    }

    return null;
  }

  /// Returns whether [key] exists in [array]: a key of a Map, or a valid
  /// index of a List (an int or, as in PHP, a numeric String).
  ///
  /// Throws an [Exception] when [array] is neither.
  static bool arrayExists(dynamic array, dynamic key) {
    if (array is Map) {
      return mapKeyExists(key, array);
    } else if (array is List) {
      var index = _listIndex(key);
      return index != null && index >= 0 && index < array.length;
    }
    throw Exception('array is not List or Map');
  }

  /// Returns [key] as a List index: an int, or a String holding one as PHP
  /// writes it (`'1'`, not `'01'`); else null.
  static int? _listIndex(dynamic key) {
    if (key is int) return key;
    if (key is String) {
      var index = int.tryParse(key);
      if (index != null && index.toString() == key) return index;
    }
    return null;
  }

  /// Returns `array[key]`, [key] being a List index as [arrayExists]
  /// accepts it.
  static dynamic _offsetGet(dynamic array, dynamic key) {
    return array is List ? array[_listIndex(key)!] : array[key];
  }

  /// Returns whether [haystack] contains any of [needles]; empty needles
  /// never match.
  static bool stringContains(String haystack, List<String> needles) {
    for (var needle in needles) {
      if (needle != '' && haystack.indexOf(needle) != -1) {
        return true;
      }
    }

    return false;
  }

  /// Returns the elements of [array1] followed by those of [array2]; null
  /// counts as an empty list.
  static List arrayMerge(List? array1, List? array2) {
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
  static List<String> arrayMergeSs(List<String> array1, List<String> array2) {
    return [...array1, ...array2];
  }

  /// Returns the elements of [array1] followed by those of [array2].
  static List<Map<String, dynamic>> arrayMergeMs(
      List<Map<String, dynamic>> array1, List<Map<String, dynamic>> array2) {
    return [...array1, ...array2];
  }

  /// Returns the elements of [array1] followed by those of [array2].
  ///
  /// Throws an [Exception] when either is null.
  static List<String> arrayMergeSa(List<String>? array1, List<String>? array2) {
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
  static List arrayFlatten(List array, [int depth = intMaxValueNative]) {
    var result = [];

    for (var item in array) {
      //var item = itemP is Collection ? item.all() : item;

      if (item is List) {
        if (depth == 1) {
          result = arrayMerge(result, item);
          continue;
        }

        result = arrayMerge(result, arrayFlatten(item, depth - 1));
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
  /// print(mapMergeSd(map1, map2)); // {driver: mysql, host: 127.0.0.1}
  /// ```
  static Map<String, dynamic> mapMergeSd(
      Map<String, dynamic> firstMap, Map<String, dynamic> secondMap) {
    return {
      ...firstMap,
      ...secondMap,
    };
  }

  /// Sets [key] to [value] in [map] unless [key] already holds a value that
  /// is not null (as Laravel's `Arr::add`, without "dot" notation), and
  /// returns [map].
  static Map<String, dynamic> mapAddSd(
      Map<String, dynamic> map, String key, dynamic value) {
    if (map[key] != null) {
      return map;
    }
    map[key] = value;

    return map;
  }

  /// Removes [keys] (a String or a `List<String>`) from [map] and its nested
  /// maps, in place, and returns [map]: unlike Laravel's `Arr::except`, it
  /// does not copy [map], and nested maps are searched too.
  ///
  /// A matching key is removed whatever its value; the other values that are
  /// `Map<String, dynamic>` are searched. Throws an [Exception] when [keys]
  /// is neither a String nor a `List<String>`.
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
  /// mapExceptSd(map, ['read', 'write']);
  /// // {driver: mysql, host: 127.0.0.1, level1: {level2: {banana: good}}}
  /// ```
  static Map<String, dynamic> mapExceptSd(
      Map<String, dynamic> map, dynamic keys) {
    if (keys is List<String>) {
      for (var key in keys) {
        mapUnsetDeepSd(map, key);
      }
    } else if (keys is String) {
      mapUnsetDeepSd(map, keys);
    } else {
      throw Exception('keys is not List<String> or String');
    }
    return map;
  }

  /// Removes [key] from [map] and its nested maps; see [mapExceptSd].
  static void mapUnsetDeepSd(Map<String, dynamic> map, String key) {
    map.remove(key);
    for (var value in map.values) {
      if (value is Map<String, dynamic>) {
        mapUnsetDeepSd(value, key);
      }
    }
  }

  static int arrayUnshift(List array, dynamic value) {
    //var result = [...array, value];
    array.insert(0, value);
    return array.length;
  }

  /// Returns a random index of [array] or, when [numero] is more than 1, a
  /// list of [numero] distinct random indexes in ascending order, as PHP's
  /// `array_rand`.
  ///
  /// Throws an [ArgumentError] when [numero] is not between 1 and the length
  /// of [array].
  static dynamic arrayRand(List array, [int numero = 1]) {
    if (numero < 1 || numero > array.length) {
      throw ArgumentError.value(numero, 'numero',
          'Must be between 1 and the number of elements (${array.length})');
    }
    var rng = Random();
    if (numero == 1) {
      return rng.nextInt(array.length);
    }
    var indexes = List.generate(array.length, (i) => i)..shuffle(rng);
    return indexes.sublist(0, numero)..sort();
  }

  /// Returns whether [value] is a List.
  static bool isArray(dynamic value) {
    return value is List;
  }

  static bool isMap(dynamic value) {
    return value is Map;
  }

  /// Returns whether [value] is a bool.
  static bool isBool(dynamic value) {
    return value is bool;
  }

  /// Returns whether [value] is a String.
  static bool isString(dynamic value) {
    return value is String;
  }

  static bool arrayIsEmpty(List val) {
    return val.isEmpty;
  }

  /// Returns whether [val] is empty as PHP's `empty` sees it: null, `false`,
  /// 0, `''`, `'0'` or an empty List or Map.
  static bool empty(dynamic val) {
    if (val == null || val == false || val == 0 || val == '' || val == '0') {
      return true;
    } else if (val is List) {
      return val.isEmpty;
    } else if (val is Map) {
      return val.isEmpty;
    }
    return false;
  }

  /// Returns whether [val] is null.
  static bool isNull(dynamic val) {
    return val == null;
  }

  /// Returns whether [val] is null or an empty List or Map.
  static bool isNullOrEmpty(dynamic val) {
    if (val is List) {
      return val.isEmpty;
    } else if (val is Map) {
      return val.isEmpty;
    }
    return val == null;
  }

  /// Returns whether [val] is set: false for null and for an empty List or
  /// Map (PHP's `isset` is true for an empty array).
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

  /// Returns [val] as a String, as PHP's `strval`: null and `false` give
  /// `''`, `true` gives `'1'`.
  static String strval(dynamic val) {
    if (val == null || val == false) return '';
    if (val == true) return '1';
    return val.toString();
  }

  static bool mapKeyExists(dynamic key, Map map) {
    return map.containsKey(key);
  }

  /// Returns the first key of [map], or null when it is empty (PHP's
  /// `array_key_first`).
  static dynamic mapFirstKey(Map map) {
    return map.isEmpty ? null : map.keys.first;
  }

  /// Returns the last element of [array], or false when it is empty.
  static dynamic arrayEnd(List array) {
    return array.isEmpty ? false : array.last;
  }

  static void varDump(dynamic val) {
    print(val);
  }

  static int strLength(String str) {
    return str.length;
  }

  /// Returns whether [haystack] ends with [needles], a String or any element
  /// of a List, as Laravel's `Str::endsWith`; an empty needle never matches.
  static bool endsWith(String haystack, dynamic needles) {
    for (var needle in needles is List ? needles : [needles]) {
      if (needle is String && needle != '' && haystack.endsWith(needle)) {
        return true;
      }
    }
    return false;
  }

  /// Removes the characters in [chars] from the start of [string], as PHP's
  /// `ltrim`; null [chars] stands for PHP's default list: space, `\n`, `\r`,
  /// `\t`, `\v` and `\0`.
  ///
  /// Each character of [chars] counts as written: PHP's `a..z` ranges are
  /// not supported.
  static String ltrim(String string, [String? chars = _phpTrimChars]) {
    var set = (chars ?? _phpTrimChars).codeUnits.toSet();
    var start = 0;
    while (start < string.length && set.contains(string.codeUnitAt(start))) {
      start++;
    }
    return string.substring(start);
  }

  /// The characters PHP's `trim` functions remove by default.
  static const String _phpTrimChars = ' \n\r\t\v\x00';

  /// Removes and returns the last element of a List or the value of the
  /// last entry of a Map, as PHP's `array_pop`.
  ///
  /// Returns null when [array] is empty or neither.
  static dynamic arrayPop(dynamic array) {
    if (array is List && array.isNotEmpty) {
      return array.removeLast();
    } else if (array is Map && array.isNotEmpty) {
      return array.remove(array.keys.last);
    }
    return null;
  }

  /// Returns the values of [map] as a list (PHP's `array_values`).
  static List mapValues(Map map) {
    return map.values.toList();
  }

  /// Returns the part of [str] from [offset] on, at most [length] characters,
  /// as PHP's `substr`.
  ///
  /// A negative [offset] counts from the end, and a negative [length] leaves
  /// out that many characters at the end. As in PHP 8, an [offset] past the
  /// end gives `''`.
  ///
  /// ```dart
  /// substr('abcdef', -2, 10); // 'ef'
  /// substr('abcdef', 1, -1); // 'bcde'
  /// ```
  static String substr(String str, int offset, [int? length]) {
    var start = offset < 0 ? max(0, str.length + offset) : offset;
    if (start >= str.length) return '';

    var end = length == null
        ? str.length
        : length < 0
            ? str.length + length
            : min(str.length, start + length);
    return end <= start ? '' : str.substring(start, end);
  }

  /// Returns the larger of [value1] and [value2].
  static intMax(int value1, int value2) {
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

  // Whether objectOrClass has a method methodName (needs dart:mirrors).
  // Example:
  // class FooBar {
  //  String showMessage(String msg) {
  //    print("message $msg");
  //    return msg;
  //  }
  // }
  // var c = FooBar();
  // var result = Utils.methodExists(c, 'showMessage');
  // print(result);
  // true
  // static bool methodExists(dynamic objectOrClass, String methodName) {
  //   var mirror = reflect(objectOrClass);
  //   return mirror.type.instanceMembers.values
  //       .map((MethodMirror method) => MirrorSystem.getName(method.simpleName))
  //       .contains(methodName);
  // }

  // Whether objectOrClass has a property propName (needs dart:mirrors).
  // static bool propertyExists(dynamic objectOrClass, String propName) {
  //   var mirror = reflect(objectOrClass);
  //   return mirror.type.declarations.values
  //       .map((value) => MirrorSystem.getName(value.simpleName))
  //       .contains(propName);
  // }

  // Calls the method methodName of objectOrClass (needs dart:mirrors).
  // Only tested with methods that do not return a Future.
  // static dynamic callMethod(
  //   dynamic objectOrClass,
  //   String methodName, [
  //   List<dynamic>? positionalArguments,
  //   Map<Symbol, dynamic> namedArguments = const <Symbol, dynamic>{},
  // ]) {
  //   var mirror = reflect(objectOrClass);
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

  /// Returns a list of [count] copies of [value].
  ///
  /// Unlike PHP's `array_fill`, [startIndex] is ignored: the indexes of a
  /// List always start at 0.
  static List arrayFill(int startIndex, int count, dynamic value) {
    return List.generate(count, (v) => value);
  }
}

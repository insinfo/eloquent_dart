/// Array Map Utils
class ArrUtils {
  /// Flatten a multi-dimensional map into a single level.  
  static List<dynamic> flattenMap(Map<dynamic, dynamic> map, [int depth = -1]) {
    List<dynamic> result = [];

    void recursiveFlatten(dynamic item, int currentDepth) {
      if (item is Map) {
        if (currentDepth == 1) {
          result.addAll(item.values);
        } else if (currentDepth < 0 || currentDepth > 1) {
          item.forEach((key, value) {
            recursiveFlatten(value, currentDepth - 1);
          });
        }
      } else {
        result.add(item);
      }
    }

    map.forEach((key, value) {
      recursiveFlatten(value, depth);
    });

    return result;
  }

  /// Flatten a multi-dimensional List into a single level. 
  /// Example usage:
  /// ```dart
  /// List<dynamic> multiDimensionalArray = [
  ///   [1, 2, [3, 4, [5, 6]]],
  ///   [7, 8],
  ///   9,
  ///   [10]
  /// ];
  ///
  /// List<dynamic> flattenedArray = flatten(multiDimensionalArray);
  /// print('Original: $multiDimensionalArray');
  /// print('Flattened: $flattenedArray');
  /// ```
  static List<dynamic> flattenList(dynamic array, [int depth = 0]) {
    List<dynamic> result = [];

    if (array is List) {
      for (dynamic item in array) {
        if (item is List || item is Iterable) {
          if (depth == 1) {
            result.addAll(item);
          } else {
            result.addAll(flattenList(item, depth - 1));
          }
        } else {
          result.add(item);
        }
      }
    } else if (array is Iterable) {
      for (dynamic item in array) {
        if (item is Iterable) {
          if (depth == 1) {
            result.addAll(item);
          } else {
            result.addAll(flattenList(item, depth - 1));
          }
        } else {
          result.add(item);
        }
      }
    } else {
      result.add(array);
    }

    return result;
  }

  /// Get all of the given array except for a specified array of keys.
  /// Obtenha todo o map fornecido, exceto um map especificado pela chave.
  /// [keys] array|string
  static exceptMap(Map<String, dynamic> map, dynamic keys) {
    forgetMap(map, keys);
    return map;
  }

  static void forgetMap(Map<String, dynamic> map, dynamic keys) {
    Map<String, dynamic>? original = {...map};

    if (keys is String) {
      keys = [keys];
    }

    if (keys is! List<String> || keys.isEmpty) {
      return;
    }

    for (var key in keys) {
      // if the exact key exists in the top-level, remove it
      if (exists(map, key)) {
        map.remove(key);
        continue;
      }

      List<String> parts = key.split('.');

      // clean up before each pass
      map = original;

      while (parts.length > 1) {
        String part = parts.removeAt(0);

        if (map.containsKey(part) && map[part] is Map<String, dynamic>) {
          map = map[part];
        } else {
          continue;
        }
      }

      map.remove(parts.removeAt(0));
    }
  }

  /// Determine if the given key exists in the provided map using dot notation.
  static bool exists(Map<String, dynamic> map, String key) {
    final parts = key.split('.');

    for (String part in parts) {
      if (map.containsKey(part) && map[part] is Map<String, dynamic>) {
        map = map[part];
      } else {
        return false;
      }
    }

    return true;
  }

  /// Flatten a multi-dimensional associative array/map with dots.
  Map<String, dynamic> dot(Map<String, dynamic> array, [String prepend = '']) {
    Map<String, dynamic> results = {};

    array.forEach((key, value) {
      if (value is Map<String, dynamic> && value.isNotEmpty) {
        results.addAll(dot(value, '$prepend$key.'));
      } else {
        results['$prepend$key'] = value;
      }
    });

    return results;
  }
}

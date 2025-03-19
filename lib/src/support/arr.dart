class Arr {
  /// Verifica se [value] pode ser acessado como array (List ou Map).
  static bool accessible(dynamic value) => value is List || value is Map;

  /// Determina se a chave [key] existe num Map ou List.
  static bool exists(dynamic array, dynamic key) {
    if (array is Map) {
      return array.containsKey(key);
    } else if (array is List) {
      // Para List, somente índices do tipo int são válidos.
      if (key is int) {
        return key >= 0 && key < array.length;
      }
      return false;
    }
    return false;
  }

  /// Retorna o primeiro elemento do array (ou [defaultValue] se vazio).
  static dynamic first(dynamic array,
      {bool Function(dynamic key, dynamic value)? callback,
      dynamic defaultValue}) {
    if (!accessible(array)) {
      return defaultValue;
    }
    if (callback == null) {
      if (array is List) {
        return array.isEmpty ? defaultValue : array.first;
      } else if (array is Map) {
        return array.isEmpty ? defaultValue : array.values.first;
      }
      return defaultValue;
    }
    if (array is List) {
      for (var i = 0; i < array.length; i++) {
        if (callback(i, array[i])) {
          return array[i];
        }
      }
      return defaultValue;
    } else if (array is Map) {
      for (var k in array.keys) {
        if (callback(k, array[k])) {
          return array[k];
        }
      }
      return defaultValue;
    }
    return defaultValue;
  }

  /// Retorna o último elemento do array (ou [defaultValue] se vazio).
  static dynamic last(dynamic array,
      {bool Function(dynamic key, dynamic value)? callback,
      dynamic defaultValue}) {
    if (!accessible(array)) {
      return defaultValue;
    }
    if (callback == null) {
      if (array is List) {
        return array.isEmpty ? defaultValue : array.last;
      } else if (array is Map) {
        return array.isEmpty ? defaultValue : array.values.last;
      }
      return defaultValue;
    }
    if (array is List) {
      for (var i = array.length - 1; i >= 0; i--) {
        if (callback(i, array[i])) {
          return array[i];
        }
      }
      return defaultValue;
    } else if (array is Map) {
      var ks = array.keys.toList();
      for (var i = ks.length - 1; i >= 0; i--) {
        var k = ks[i];
        if (callback(k, array[k])) {
          return array[k];
        }
      }
      return defaultValue;
    }
    return defaultValue;
  }

  /// Remove um ou mais itens de [array] usando "dot notation".
  static dynamic forget(dynamic array, dynamic keys) {
    if (!accessible(array)) {
      return array;
    }
    // Se a chave for int, não a convertemos para string.
    List<dynamic> keyList;
    if (keys is List) {
      keyList = keys;
    } else {
      keyList = [keys];
    }
    for (var key in keyList) {
      if (array is Map) {
        if (array.containsKey(key)) {
          array.remove(key);
          continue;
        }
      } else if (array is List) {
        if (key is int) {
          if (key >= 0 && key < array.length) {
            array.removeAt(key);
          }
          continue;
        }
      }
      // Se não foi removido diretamente, tenta a dot notation.
      var segments = key.toString().split('.');
      dynamic current = array;
      for (var i = 0; i < segments.length; i++) {
        var segment = segments[i];
        if (i == segments.length - 1) {
          if (current is Map) {
            current.remove(segment);
          } else if (current is List) {
            var idx = int.tryParse(segment);
            if (idx != null && idx >= 0 && idx < current.length) {
              current.removeAt(idx);
            }
          }
        } else {
          if (current is Map && current.containsKey(segment)) {
            current = current[segment];
          } else if (current is List) {
            var idx = int.tryParse(segment);
            if (idx == null || idx < 0 || idx >= current.length) break;
            current = current[idx];
          } else {
            break;
          }
        }
      }
    }
    return array;
  }

  /// Retorna valor de [array] usando "dot notation".
  static dynamic get(dynamic array, String? key, [dynamic defaultValue]) {
    if (!accessible(array)) {
      return defaultValue;
    }
    if (key == null) {
      return array;
    }
    // Para List, somente aceita chave do tipo int
    if (exists(array, key)) {
      if (array is Map) {
        return array[key];
      } else if (array is List && key is int) {
        return array[key as int];
      }
    }
    // Processa dot notation
    var segments = key.split('.');
    dynamic current = array;
    for (var segment in segments) {
      if (!accessible(current) || !exists(current, segment)) {
        return defaultValue;
      }
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        var idx = int.tryParse(segment);
        if (idx == null || idx < 0 || idx >= current.length) {
          return defaultValue;
        }
        current = current[idx];
      } else {
        return defaultValue;
      }
    }
    return current;
  }

  /// Verifica se [key] existe em [array] usando "dot notation".
  static bool has(dynamic array, dynamic key) {
    if (!accessible(array) || key == null) {
      return false;
    }
    // Se array for List e a chave for int, usamos a verificação simples.
    if (array is List && key is int) {
      return exists(array, key);
    }
    List<String> keys;
    if (key is List) {
      keys = key.map((e) => e.toString()).toList();
    } else if (key is String) {
      keys = [key];
    } else {
      keys = [key.toString()];
    }
    for (var k in keys) {
      dynamic current = array;
      var segments = k.split('.');
      bool found = true;
      for (var segment in segments) {
        if (!accessible(current) || !exists(current, segment)) {
          found = false;
          break;
        }
        if (current is Map) {
          current = current[segment];
        } else if (current is List) {
          var idx = int.tryParse(segment);
          if (idx == null || idx < 0 || idx >= current.length) {
            found = false;
            break;
          }
          current = current[idx];
        } else {
          found = false;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  /// Achatamento superficial de array multi-dimensional.
  /// Se [depth] for 1, achata somente um nível.
  static List flatten(dynamic array, [int depth = 1]) {
    final result = <dynamic>[];
    if (array is! List) return result;
    for (var item in array) {
      if (item is List) {
        if (depth == 1) {
          result.addAll(item);
        } else {
          result.addAll(flatten(item, depth - 1));
        }
      } else {
        result.add(item);
      }
    }
    return result;
  }

  /// Pluck: extrai valores de [value] e opcionalmente define
  /// a chave do array usando [key], ambos podem ser dot notation.
  /// Se [key] for fornecido, retorna Map; caso contrário, retorna List.
  static dynamic pluck(dynamic array, dynamic value, [dynamic key]) {
    var results = key == null ? <dynamic>[] : <dynamic, dynamic>{};
    var exploded = explodePluckParameters(value, key);
    var valuePath = exploded[0];
    var keyPath = exploded[1];

    if (array is List) {
      for (var item in array) {
        var itemValue = dataGet(item, valuePath);
        if (keyPath == null) {
          (results as List).add(itemValue);
        } else {
          var itemKey = dataGet(item, keyPath);
          if (itemKey == null) {
            itemKey = item;
          }
          (results as Map)[itemKey] = itemValue;
        }
      }
    } else if (array is Map) {
      for (var entry in array.entries) {
        var itemValue = dataGet(entry.value, valuePath);
        if (keyPath == null) {
          (results as List).add(itemValue);
        } else {
          var itemKey = dataGet(entry.value, keyPath);
          if (itemKey == null) {
            itemKey = entry.value;
          }
          (results as Map)[itemKey] = itemValue;
        }
      }
    }
    return results;
  }

  /// Converte [value] e [key] de string para lista via split('.') se necessário.
  static List explodePluckParameters(dynamic value, dynamic key) {
    var val = value is String ? value.split('.') : value;
    var ky = (key == null || key is List) ? key : key.split('.');
    return [val, ky];
  }

  /// Equivalente ao data_get do Laravel.
  static dynamic dataGet(dynamic target, dynamic path) {
    if (path == null) return target;
    if (path is String) path = path.split('.');
    for (var segment in path) {
      if (!accessible(target) || !exists(target, segment)) {
        return null;
      }
      if (target is Map) {
        target = target[segment];
      } else if (target is List) {
        var idx = int.tryParse(segment);
        if (idx == null || idx < 0 || idx >= target.length) {
          return null;
        }
        target = target[idx];
      } else {
        return null;
      }
    }
    return target;
  }

  /// Retorna um subset do [array] com apenas as [keys].
  static Map only(Map array, List<String> keys) {
    Map result = {};
    for (var k in keys) {
      if (array.containsKey(k)) {
        result[k] = array[k];
      }
    }
    return result;
  }

  /// Remove do array as chaves [keys].
  static Map except(Map array, dynamic keys) {
    if (keys is String) keys = [keys];
    for (var k in keys) {
      forget(array, k);
    }
    return array;
  }

  /// "Seta" [value] em [array] usando dot notation.
  static Map set(Map array, String key, dynamic value) {
    var segments = key.split('.');
    var current = array;
    for (var i = 0; i < segments.length; i++) {
      var segment = segments[i];
      if (i == segments.length - 1) {
        current[segment] = value;
      } else {
        if (!current.containsKey(segment) || current[segment] is! Map) {
          current[segment] = <String, dynamic>{};
        }
        current = current[segment];
      }
    }
    return array;
  }

  /// Colapsa sub-listas em uma única lista.
  static List collapse(List array) {
    var results = <dynamic>[];
    for (var values in array) {
      if (values is List) {
        results.addAll(values);
      }
    }
    return results;
  }

  /// Mescla duas listas.
  static List arrayMerge(List a1, List a2) {
    return [...a1, ...a2];
  }

  /// "Prepend" – coloca um [value] no início da lista ou, se [key] não for nulo,
  /// cria um Map {key: value} concatenado com o array.
  static dynamic prepend(dynamic array, dynamic value, [dynamic key]) {
    if (array is List) {
      if (key == null) {
        array.insert(0, value);
      } else {
        var map = <dynamic, dynamic>{key: value};
        return {...map, ..._listToMap(array)};
      }
      return array;
    } else if (array is Map) {
      if (key == null) {
        var newMap = <dynamic, dynamic>{value: null};
        newMap.addAll(array);
        return newMap;
      } else {
        return {key: value, ...array};
      }
    }
    return array;
  }

  /// Converte List em Map<int, dynamic>, indexando cada elemento.
  static Map<int, dynamic> _listToMap(List arr) {
    var m = <int, dynamic>{};
    for (var i = 0; i < arr.length; i++) {
      m[i] = arr[i];
    }
    return m;
  }

  /// "Pull" = get + forget.
  static dynamic pull(dynamic array, String key, [dynamic defaultValue]) {
    var val = get(array, key, defaultValue);
    forget(array, key);
    return val;
  }
}

//import 'dart:mirrors';
import 'package:intl/intl.dart';

import 'dart:math';

enum StringCase { CASE_UPPER, CASE_LOWER }

class Utils {
  static const int intMinValueNative = -9223372036854775808;
  static const int intMaxValueNative = 9223372036854775807;

  static const int intMinValueJS = -9007199254740992;
  static const int intMaxValueJS = 9007199254740992;

  ///  Aplica o retorno de chamada aos elementos dos arrays fornecidos
  static List array_map(Function callback, List values) {
    var result = [];

    values.forEach((element) {
      result.add(callback(element));
    });

    return result;
  }

  /// Filtra elementos de um array utilizando uma função callback
  static List array_filter(List array, Function callback) {
    var result = [];

    array.forEach((element) {
      if (callback(element)) {
        result.add(element);
      }
    });

    return result;
  }

  /// in_array — Verifica se existe um valor em um array
  static bool in_array(dynamic needle, List array) {
    return array.contains(needle);
  }

  /// implode — Junta elementos de uma matriz em uma string
  static String implode(String glue, List pieces) {
    return pieces.join(glue);
  }

  ///  Substitui todas as ocorrências da string de pesquisa pela string de substituição
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

  ///
  /// Return the default value of the given value.
  ///
  /// @param  mixed  $value
  /// @return mixed
  ///
  static dynamic value(dynamic value) {
    return value is Function ? value() : value;
  }

  /// Converte uma string para minúsculas
  static String strtolower(String str) {
    return str.toLowerCase();
  }

  /// Encontra a posição da primeira ocorrência de uma substring em uma string
  /// return int|false
  static dynamic strpos(String str, Pattern needle) {
    var index = str.indexOf(needle);
    if (index == -1) {
      return false;
    }
    return index;
  }

  /// Dividir uma string por uma string
  ///
  /// PHP_INT_MAX = 9223372036854775807 [int limit = 9223372036854775807]
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

  /// Conta todos os elementos em uma matriz ou em um objeto Countable
  static int count(Iterable items) {
    return items.length;
  }

  /// Torna o primeiro caractere de uma string maiúsculo
  static String ucfirst(String string) {
    if (string.length == 0) {
      return string;
    } else if (string.length == 1) {
      return string[0].toUpperCase();
    }

    return string[0].toUpperCase() + string.substring(1);
  }

  ///
  /// Explode the "value" and "key" arguments passed to "pluck".
  ///
  /// @param  string|array  $value
  /// @param  string|array|null  $key
  /// @return array return [value, key];
  ///
  static List explodePluckParameters(dynamic valueP, dynamic keyP) {
    var value = is_string(valueP) ? explode('.', valueP) : valueP;

    var key = is_null(keyP) || is_array(keyP) ? keyP : explode('.', keyP);

    return [value, key];
  }

  ///
  /// Pluck an array of values from an array.
  ///
  /// @param  array  $array
  /// @param  string|array  $value
  /// @param  string|array|null  $key
  /// @return array
  ///
  static array_pluck(arrayP, valueP, [keyP = null]) {
    var results = [];

    var re = explodePluckParameters(valueP, keyP);
    var value = re[0];
    var key = re[1];

    for (var item in arrayP) {
      var itemValue = data_get(item, value);

      // If the key is "null", we will just append the value to the array and keep
      // looping. Otherwise we will key the array using the value of the key we
      // received from the developer. Then we'll return the final array form.
      if (is_null(key)) {
        results.add(itemValue);
      } else {
        var itemKey = data_get(item, key);

        results[itemKey] = itemValue;
      }
    }

    return results;
  }

  /// change all keys to case defined
  static Map<String, dynamic> map_change_key_case_sd(Map<String, dynamic> map,
      [StringCase typeCase = StringCase.CASE_LOWER]) {
    var clone = <String, dynamic>{}..addAll(map);
    var length = clone.entries.length;
    var entries = clone.entries.toList();
    for (var i = 0; i < length; i++) {
      var entry = entries[i];
      if (entry.value is Map) {
        map_change_key_case_sd(map[entry.key], typeCase);
      } else {
        var key = entry.key;
        var val = map[key];
        map.remove(key);
        map[key] = val;
      }
    }
    return map;
  }

  ///
  /// Get an item from an array using "dot" notation.
  ///
  /// @param  \ArrayAccess|array  $array
  /// @param  string  $key
  /// @param  mixed   $default
  /// @return mixed
  /// equivalente a Arr::get($connections, $name)
  ///
  static dynamic array_get(array, String key, [dynamic defaultP]) {
    if (!array_accessible(array)) {
      return value(defaultP);
    }

    if (is_null(key)) {
      return array;
    }

    if (array_exists(array, key)) {
      return array[key];
    }

    for (var segment in explode('.', key)) {
      if (array_accessible(array) && array_exists(array, segment)) {
        array = array[segment];
      } else {
        return value(defaultP);
      }
    }

    return array;
  }

  ///
  /// Get an item from an array or object using "dot" notation.
  ///
  /// @param  mixed   $target
  /// @param  string|array  $key
  /// @param  mixed   $default
  /// @return mixed
  ///
  static dynamic data_get(dynamic target, dynamic key, [dynamic defaultP]) {
    if (is_null(key)) {
      return target;
    }

    key = is_array(key) ? key : explode('.', key);
    var segment;
    while ((segment = array_shift(key)) != null) {
      if (segment == '*') {
        // if ($target instanceof Collection) {
        //     $target = $target->all();
        //}

        if (!is_array(target)) {
          return value(defaultP);
        }

        var result = array_pluck(target, key);

        return in_array('*', key) ? array_collapse(result) : result;
      }

      if (array_accessible(target) && array_exists(target, segment)) {
        target = target[segment];
      }
      // else if (is_object($target) && isset($target->{$segment})) {
      //     target = target->{$segment};
      // }
      else {
        return value(defaultP);
      }
    }

    return target;
  }

  ///
  /// Determine whether the given value is array accessible.
  ///
  /// @param  mixed  $value
  /// @return bool
  ///
  static bool array_accessible(dynamic value) {
    return is_array(value) ||
        is_map(value); // || $value instanceof ArrayAccess;
  }

  static bool is_object(dynamic value) {
    return value is Object;
  }

  /**
     * Collapse an array of arrays into a single array.
     *
     * @param  array  $array
     * @return array
     */
  static dynamic array_collapse(dynamic array) {
    var results = array is List ? [] : <String, dynamic>{};

    for (var values in array) {
      // if ($values instanceof Collection) {
      //     $values = $values->all();
      // } elseif (! is_array($values)) {
      //     continue;
      // }
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

  /// desloca o primeiro valor do arrayoff e o retorna, encurtando o array
  /// por um elemento e movendo tudo para baixo. Todas as chaves de matriz
  /// numérica serão modificadas para começar a contar do zero,
  /// enquanto as chaves literais não serão afetadas.
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

  /**
     * Determine if the given key exists in the provided array or Map
     *
     * [array] @param  \ArrayAccess|array   Map | List
     * @param  string|int  $key
     * @return bool
     */
  static bool array_exists(dynamic array, dynamic key) {
    // if ($array instanceof ArrayAccess) {
    //     return $array->offsetExists($key);
    // }
    if (array is Map) {
      return map_key_exists(key, array);
    } else if (array is List) {
      return key >= 0 && array.length > key;
    }
    throw Exception('array is not List or Map');
  }

  ///
  /// Determine if a given string contains a given substring.
  ///
  /// @param  string  $haystack
  /// @param  string|array  $needles
  /// @return bool
  ///
  static bool string_contains(String haystack, List<String> needles) {
    for (var needle in needles) {
      if (needle != '' && haystack.indexOf(needle) != -1) {
        return true;
      }
    }

    return false;
  }

  /// array1 => ['A', 'B']  and array2 => ['C', 'D'] return ['A', 'B', 'C', 'D']
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

  /// mescla duas List de String Null Safety
  static List<String> array_merge_ss(List<String> array1, List<String> array2) {
    return [...array1, ...array2];
  }

  /// mescla duas List Map String dynamic Null Safety
  static List<Map<String, dynamic>> array_merge_ms(
      List<Map<String, dynamic>> array1, List<Map<String, dynamic>> array2) {
    return [...array1, ...array2];
  }

  /// mescla duas List de String anulavel
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

  ///
  /// Flatten a multi-dimensional array into a single level.
  ///
  /// @param  array  $array
  /// @param  int  $depth
  /// @return array
  ///
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

  ///
  /// esquivale ao array_merge para Array Associativo do PHP
  /// Example:
  ///  var map1 = {'driver': 'pgsql', 'host': 'localhost'};
  ///  var map2 = {'driver': 'mysql', 'host': '127.0.0.1'};
  ///  print(map_merge_sd(map1, map2));
  ///  result {driver: mysql, host: 127.0.0.1}
  static Map<String, dynamic> map_merge_sd(
      Map<String, dynamic> firstMap, Map<String, dynamic> secondMap) {
    return {
      ...firstMap,
      ...secondMap,
    };
  }

  /// Add an element to an map of String, dynamic if it doesn't exist.
  static Map<String, dynamic> map_add_sd(
      Map<String, dynamic> map, String key, dynamic value) {
    if (map.containsKey(key)) {
      return map;
    }
    map[key] = value;

    return map;
  }

  ///
  /// Get all of the given Map except for a specified Map of items.
  ///
  /// [map]  Map<String, dynamic>
  /// [keys]  List<String>|String  keys
  /// Return Map<String, dynamic>
  ///
  /// Example:
  ///  var map = {
  ///    'driver': 'mysql',
  ///    'host': '127.0.0.1',
  ///    'level1': {
  ///       'read': true,
  ///       'write': false,
  ///       'level2': {'banana': 'good'}
  ///     }
  ///   };
  /// map_except_sd(map, ['read', 'write']);
  /// result: {driver: mysql, host: 127.0.0.1, level1: {level2: {banana: good}}}
  ///
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

  /// remove um item varrendo o map recursivamente
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

  /// array_rand — Escolhe uma ou mais chaves aleatórias de um array
  /// numero Especifica quantos elementos deseja obter.
  static dynamic array_rand(List array, [int numero = 1]) {
    var rng = Random();
    var len = array.length;

    var list = [];
    for (var i = 0; i < numero; i++) {
      list.add(rng.nextInt(len));
    }
    return list;
  }

  /// verifica se value é um List
  static bool is_array(dynamic value) {
    return value is List;
  }

  static bool is_map(dynamic value) {
    return value is Map;
  }

  /// verifica se value é um bool
  static bool is_bool(dynamic value) {
    return value is bool;
  }

  /// verifica se value é um String
  static bool is_string(dynamic value) {
    return value is String;
  }

  static bool array_is_empty(List val) {
    return val.isEmpty;
  }

  /// replica o comportamento da função empty do PHP
  /// retorn true se val é 0, '' ou null;
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

  /// Informa se a variável é null
  static bool is_null(dynamic val) {
    return val == null;
  }

  /// verifica se o valor é nulo
  /// e se val for um List ou Map verifica se esta vazio
  static bool is_null_or_empty(dynamic val) {
    if (val is List) {
      return val.isEmpty;
    } else if (val is Map) {
      return val.isEmpty;
    }
    return val == null;
  }

  /// Verifica se a variável é definida.
  /// se val == null => FALSE
  /// se val is List empty => FALSE
  /// se val is Map empty => FALSE
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

  /// if array is Empty return false
  static dynamic array_end(List array) {
    return array.isEmpty ? false : array.last;
  }

  static void var_dump(dynamic val) {
    print(val);
  }

  static int str_length(String str) {
    return str.length;
  }

  ///
  /// Determine if a given string ends with a given substring.
  ///
  /// @param  string  $haystack
  /// @param  string|array  $needles
  /// @return bool
  ///
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

  /// trim characters from the left-side of the input
  /// chars = " \n\r\t\v\x00"
  static ltrim(String string, [String? chars = " \n\r\t"]) {
    //chars =chars.replaceAll('from', replace)
    var pattern = chars != null ? RegExp('^[$chars]+') : RegExp(r'^\s+');
    return string.replaceAll(pattern, '');
  }

  /// array_pop — Pop the element off the end of array
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

  /// equivale ao array_values do PHP para Array Associativo
  static List map_values(Map map) {
    return map.values.toList();
  }

  ///
  /// Example:
  ///  echo(substr("abcdef", -2,10));
  ///  ef
  static String substr(String str, int offset, [int? length]) {
    if (length != null && length > str.length) {
      length = str.length;
    }
    if (offset >= 0) {
      return str.substring(offset, length);
    } else {
      var reverStr = str.substring(str.length - offset.abs(), length);
      return reverStr;
    }
  }

  /// max — Find highest value
  static int_max(int value1, int value2) {
    return value1 > value2 ? value1 : value2;
  }

  static reset(List array) {
    return array.isEmpty ? false : array.first;
  }

  /// microtime() retorna o timestamp atual do Unix com microssegundos.
  /// Esta função está disponível apenas em sistemas
  /// operacionais que suportam a chamada de sistema gettimeofday().
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

  /// Verifica se o método da classe existe
  /// this use  dart:mirrors
  /// Example:
  /// class FooBar {
  ///  String showMessage(String msg) {
  ///    print("message $msg");
  ///    return msg;
  ///  }
  /// }
  /// var c = FooBar();
  /// var result = Utils.method_exists(c, 'showMessage');
  /// print(result);
  /// true
  // static bool method_exists(dynamic object_or_class, String methodName) {
  //   var mirror = reflect(object_or_class);
  //   return mirror.type.instanceMembers.values
  //       .map((MethodMirror method) => MirrorSystem.getName(method.simpleName))
  //       .contains(methodName);
  // }

  /// Verifica se uma propriedade da classe existe
  /// this use  dart:mirrors
  // static bool property_exists(dynamic object_or_class, String propName) {
  //   var mirror = reflect(object_or_class);
  //   return mirror.type.declarations.values
  //       .map((value) => MirrorSystem.getName(value.simpleName))
  //       .contains(propName);
  // }

  /// callMethod of class
  /// somente testado em metodos sem Future
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

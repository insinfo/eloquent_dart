// lib/src/support/str.dart
import 'dart:convert';
import 'dart:math';

/// String manipulation utility class.
/// Mirrors functionality from Illuminate\Support\Str.
class Str {
  // Static caches
  static final Map<String, String> _snakeCache = {};
  static final Map<String, String> _camelCache = {};
  static final Map<String, String> _studlyCache = {};

  /// Transliterate a UTF-8 value to ASCII.
  static String ascii(String value) {
    String tempValue = value;
    _charsArray().forEach((key, List<String> val) {
      tempValue = tempValue.replaceAll(RegExp('[${val.join()}]'), key);
    });
    // Remove remaining non-basic-ASCII characters
    return tempValue.replaceAll(RegExp(r'[^\x00-\x7F]+'), '');
    // PHP version used [^\x20-\x7E], which excludes control chars.
    // If you need that exact behavior:
    // return tempValue.replaceAll(RegExp(r'[^\x20-\x7E]+'), '');
  }

  /// Convert a value to camel case.
  /// Example: 'hello_world' -> 'helloWorld'
  static String camel(String value) {
    if (_camelCache.containsKey(value)) {
      return _camelCache[value]!;
    }
    String result = studly(value);
    if (result.isEmpty) {
        _camelCache[value] = '';
        return '';
    }
    result = result[0].toLowerCase() + result.substring(1);
    _camelCache[value] = result;
    return result;
  }

   /// Convert a value to studly caps case (PascalCase).
   /// Example: 'hello_world' -> 'HelloWorld'
  static String studly(String value) {
    final key = value;
    if (_studlyCache.containsKey(key)) {
      return _studlyCache[key]!;
    }
    // Replace hyphens and underscores with spaces, then capitalize words
    String tempValue = value.replaceAll(RegExp(r'[-_]+'), ' ');
    tempValue = tempValue.split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join('');

    _studlyCache[key] = tempValue;
    return tempValue;
  }

  /// Determine if a given string contains a given substring or any of a list of substrings.
  static bool contains(String haystack, dynamic needles) {
    if (needles is String) {
      return needles.isNotEmpty && haystack.contains(needles);
    } else if (needles is List<String>) {
      for (final needle in needles) {
        if (needle.isNotEmpty && haystack.contains(needle)) {
          return true;
        }
      }
      return false;
    }
    return false;
  }

  /// Determine if a given string ends with a given substring or any of a list of substrings.
  static bool endsWith(String haystack, dynamic needles) {
    if (needles is String) {
      return haystack.endsWith(needles);
    } else if (needles is List<String>) {
      for (final needle in needles) {
        if (haystack.endsWith(needle)) {
          return true;
        }
      }
      return false;
    }
    return false;
  }

  /// Cap a string with a single instance of a given value.
  /// Example: finish('test', '/') -> 'test/'
  /// Example: finish('test/', '/') -> 'test/'
  static String finish(String value, String cap) {
     final quoted = RegExp.escape(cap);
     // Remove one or more occurrences of cap from the end, then add it back once.
     return value.replaceAll(RegExp('(?:$quoted)+\$'), '') + cap;
  }

  /// Determine if a given string matches a given pattern (simple wildcard *).
  static bool isPattern(String pattern, String value) {
    if (pattern == value) return true;
    if (pattern == '*') return true; // Wildcard matches anything

    // Escape special regex characters in the pattern, then replace * with .*
    String escapedPattern = RegExp.escape(pattern).replaceAll(r'\*', '.*');

    // Check if the value matches the regex pattern exactly
    return RegExp('^$escapedPattern\$').hasMatch(value);
  }

  /// Return the length of the given string (character count).
  static int length(String value) {
    return value.runes.length; // Use runes for multi-byte character count
  }

  /// Limit the number of characters in a string.
  static String limit(String value, [int limit = 100, String end = '...']) {
    if (value.runes.length <= limit) {
      return value;
    }
    // Take runes, convert back to string, trim trailing space, add end
    String truncated = String.fromCharCodes(value.runes.take(limit));
    // Simple trim right for spaces common after truncation
    truncated = truncated.replaceAll(RegExp(r'\s+$'), '');
    return truncated + end;
  }

  /// Convert the given string to lower-case.
  static String lower(String value) {
    return value.toLowerCase();
  }

  /// Limit the number of words in a string.
  static String words(String value, [int words = 100, String end = '...']) {
     // Match start, then up to 'words' non-space sequences followed by optional space
    final regex = RegExp(r'^\s*(\S+\s*){1,' + words.toString() + r'}');
    final match = regex.firstMatch(value);

    if (match == null || length(value) == length(match.group(0)!)) {
       return value;
    }

    // Trim trailing whitespace from the matched portion
    return match.group(0)!.replaceAll(RegExp(r'\s+$'), '') + end;
  }

  /// Parse a Class@method style callback into class and method.
  static List<String> parseCallback(String callback, String? defaultMethod) {
    return contains(callback, '@')
        ? callback.split('@') // Dart split doesn't need limit for this case
        : [callback, if(defaultMethod != null) defaultMethod];
  }

  /// Get the plural form of an English word. (Requires external library)
  static String plural(String value, [int count = 2]) {
    // Requires a pluralization library like 'inflection' package
    // return Pluralizer.plural(value, count); // Example using a hypothetical Pluralizer
    throw UnimplementedError("Pluralization requires an external library.");
  }

  /// Get the singular form of an English word. (Requires external library)
  static String singular(String value) {
    // Requires a pluralization library
    // return Pluralizer.singular(value); // Example using a hypothetical Pluralizer
    throw UnimplementedError("Singularization requires an external library.");
  }

  /// Generate a more truly "random" alpha-numeric string.
  static String random([int length = 16]) {
    final random = Random.secure();
    // Generate enough bytes (3 bytes -> 4 base64 chars)
    final byteLength = (length * 3 / 4).ceil();
    final randomBytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    // Encode using URL-safe base64, remove padding, take required length
    return base64UrlEncode(randomBytes).replaceAll('=', '').substring(0, length);
  }

  /// Generate a "random" alpha-numeric string (non-cryptographically secure).
  static String quickRandom([int length = 16]) {
    const String pool = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random();
    return List.generate(length, (_) => pool[random.nextInt(pool.length)]).join('');
  }

  /// Replace the first occurrence of a given value in the string.
  static String replaceFirst(String search, String replace, String subject) {
     return subject.replaceFirst(search, replace);
  }

  /// Replace the last occurrence of a given value in the string.
  static String replaceLast(String search, String replace, String subject) {
     final int pos = subject.lastIndexOf(search);
     if (pos == -1) {
       return subject; // Not found
     }
     return subject.substring(0, pos) + replace + subject.substring(pos + search.length);
  }

  /// Convert the given string to upper-case.
  static String upper(String value) {
    return value.toUpperCase();
  }

  /// Convert the given string to title case.
  static String title(String value) {
     if (value.isEmpty) return '';
     // Split by whitespace, capitalize each part, join back
     // Handles multiple spaces better than simple split(' ')
     return value.splitMapJoin(
        RegExp(r'\s+'), // Split on one or more whitespace chars
        onMatch: (m) => m.group(0)!, // Keep the whitespace
        onNonMatch: (n) => n.isEmpty ? '' : n[0].toUpperCase() + n.substring(1).toLowerCase()
     );
     // Simpler alternative for basic cases:
     // return value.split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase()).join(' ');
  }

  /// Generate a URL friendly "slug" from a given string.
  static String slug(String title, [String separator = '-']) {
    // 1. Transliterate to ASCII
    String slug = ascii(title);

    // 2. Convert to lowercase
    slug = slug.toLowerCase();

    // 3. Remove unwanted characters (not letters, numbers, whitespace, or the separator)
    final safeSeparator = RegExp.escape(separator);
    slug = slug.replaceAll(RegExp('[^a-z0-9\\s$safeSeparator]+'), '');

    // 4. Replace whitespace and sequences of the separator with a single separator
    slug = slug.replaceAll(RegExp('[\\s$safeSeparator]+'), separator);

    // 5. Trim leading/trailing separators
    return slug.replaceAll(RegExp('^$safeSeparator+|$safeSeparator+\$'), '');
  }

  /// Convert a string to snake case.
  /// Example: 'helloWorld' -> 'hello_world'
  static String snake(String value, [String delimiter = '_']) {
    final key = '$value$delimiter'; // Cache key includes delimiter
    if (_snakeCache.containsKey(key)) {
      return _snakeCache[key]!;
    }

    // Regex to find lowercase/digit followed by uppercase or multiple uppercase together
    final regex1 = RegExp(r'([a-z\d])([A-Z])');
    final regex2 = RegExp(r'([A-Z]+)([A-Z][a-z])');

    // Insert delimiter before uppercase letters preceded by lowercase/digit
    String result = value.replaceAllMapped(regex1, (m) => '${m.group(1)}$delimiter${m.group(2)}');
    // Insert delimiter between consecutive uppercase letters followed by lowercase
    result = result.replaceAllMapped(regex2, (m) => '${m.group(1)}$delimiter${m.group(2)}');
    // Replace spaces/hyphens with delimiter and convert to lowercase
    result = result.replaceAll(RegExp(r'[-\s]+'), delimiter).toLowerCase();

    _snakeCache[key] = result;
    return result;
  }

  /// Determine if a given string starts with a given substring or any of a list of substrings.
  static bool startsWith(String haystack, dynamic needles) {
    if (needles is String) {
      return needles.isNotEmpty && haystack.startsWith(needles);
    } else if (needles is List<String>) {
      for (final needle in needles) {
        if (needle.isNotEmpty && haystack.startsWith(needle)) {
          return true;
        }
      }
      return false;
    }
    return false;
  }

  /// Returns the portion of string specified by the start and length parameters (character-based).
  static String substr(String string, int start, [int? length]) {
     final runes = string.runes.toList();
     final runeLength = runes.length;

     // Adjust negative start index
     int actualStart = (start < 0) ? runeLength + start : start;
     // Clamp start index to bounds
     if (actualStart < 0) actualStart = 0;
     if (actualStart > runeLength) actualStart = runeLength;

     // Determine end index based on length
     int? actualEnd;
     if (length == null) {
       actualEnd = runeLength; // To the end of the string
     } else if (length >= 0) {
       actualEnd = actualStart + length;
       // Clamp end index to bounds
       if (actualEnd > runeLength) actualEnd = runeLength;
     } else { // Negative length means up to 'length' characters from the end
       actualEnd = runeLength + length;
       // Clamp end index to bounds (must be >= start)
       if (actualEnd < actualStart) actualEnd = actualStart;
     }

     if (actualStart >= actualEnd) return ''; // Return empty if start >= end

     return String.fromCharCodes(runes.sublist(actualStart, actualEnd));
  }

  /// Make a string's first character uppercase.
  static String ucfirst(String string) {
    if (string.isEmpty) return '';
    return string[0].toUpperCase() + string.substring(1);
  }

  /// Returns the replacements for the ascii method.
  static Map<String, List<String>> _charsArray() {
     // Cache the map to avoid recreating it every time
     return const {
            '0': ['°', '₀', '۰'],
            '1': ['¹', '₁', '۱'],
            '2': ['²', '₂', '۲'],
            '3': ['³', '₃', '۳'],
            '4': ['⁴', '₄', '۴', '٤'],
            '5': ['⁵', '₅', '۵', '٥'],
            '6': ['⁶', '₆', '۶', '٦'],
            '7': ['⁷', '₇', '۷'],
            '8': ['⁸', '₈', '۸'],
            '9': ['⁹', '₉', '۹'],
            'a': ['à', 'á', 'ả', 'ã', 'ạ', 'ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ', 'â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ', 'ā', 'ą', 'å', 'α', 'ά', 'ἀ', 'ἁ', 'ἂ', 'ἃ', 'ἄ', 'ἅ', 'ἆ', 'ἇ', 'ᾀ', 'ᾁ', 'ᾂ', 'ᾃ', 'ᾄ', 'ᾅ', 'ᾆ', 'ᾇ', 'ὰ', 'ά', 'ᾰ', 'ᾱ', 'ᾲ', 'ᾳ', 'ᾴ', 'ᾶ', 'ᾷ', 'а', 'أ', 'အ', 'ာ', 'ါ', 'ǻ', 'ǎ', 'ª', 'ა', 'अ', 'ا'],
            'b': ['б', 'β', 'Ъ', 'Ь', 'ب', 'ဗ', 'ბ'],
            'c': ['ç', 'ć', 'č', 'ĉ', 'ċ'],
            'd': ['ď', 'ð', 'đ', 'ƌ', 'ȡ', 'ɖ', 'ɗ', 'ᵭ', 'ᶁ', 'ᶑ', 'д', 'δ', 'د', 'ض', 'ဍ', 'ဒ', 'დ'],
            'e': ['é', 'è', 'ẻ', 'ẽ', 'ẹ', 'ê', 'ế', 'ề', 'ể', 'ễ', 'ệ', 'ë', 'ē', 'ę', 'ě', 'ĕ', 'ė', 'ε', 'έ', 'ἐ', 'ἑ', 'ἒ', 'ἓ', 'ἔ', 'ἕ', 'ὲ', 'έ', 'е', 'ё', 'э', 'є', 'ə', 'ဧ', 'ေ', 'ဲ', 'ე', 'ए', 'إ', 'ئ'],
            'f': ['ф', 'φ', 'ف', 'ƒ', 'ფ'],
            'g': ['ĝ', 'ğ', 'ġ', 'ģ', 'г', 'ґ', 'γ', 'ဂ', 'გ', 'گ'],
            'h': ['ĥ', 'ħ', 'η', 'ή', 'ح', 'ه', 'ဟ', 'ှ', 'ჰ'],
            'i': ['í', 'ì', 'ỉ', 'ĩ', 'ị', 'î', 'ï', 'ī', 'ĭ', 'į', 'ı', 'ι', 'ί', 'ϊ', 'ΐ', 'ἰ', 'ἱ', 'ἲ', 'ἳ', 'ἴ', 'ἵ', 'ἶ', 'ἷ', 'ὶ', 'ί', 'ῐ', 'ῑ', 'ῒ', 'ΐ', 'ῖ', 'ῗ', 'і', 'ї', 'и', 'ဣ', 'ိ', 'ီ', 'ည်', 'ǐ', 'ი', 'इ'],
            'j': ['ĵ', 'ј', 'Ј', 'ჯ', 'ج'],
            'k': ['ķ', 'ĸ', 'к', 'κ', 'Ķ', 'ق', 'ك', 'က', 'კ', 'ქ', 'ک'],
            'l': ['ł', 'ľ', 'ĺ', 'ļ', 'ŀ', 'л', 'λ', 'ل', 'လ', 'ლ'],
            'm': ['м', 'μ', 'م', 'မ', 'მ'],
            'n': ['ñ', 'ń', 'ň', 'ņ', 'ŉ', 'ŋ', 'ν', 'н', 'ن', 'န', 'ნ'],
            'o': ['ó', 'ò', 'ỏ', 'õ', 'ọ', 'ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ', 'ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ', 'ø', 'ō', 'ő', 'ŏ', 'ο', 'ὀ', 'ὁ', 'ὂ', 'ὃ', 'ὄ', 'ὅ', 'ὸ', 'ό', 'о', 'و', 'θ', 'ို', 'ǒ', 'ǿ', 'º', 'ო', 'ओ'],
            'p': ['п', 'π', 'ပ', 'პ', 'پ'],
            'q': ['ყ'],
            'r': ['ŕ', 'ř', 'ŗ', 'р', 'ρ', 'ر', 'რ'],
            's': ['ś', 'š', 'ş', 'с', 'σ', 'ș', 'ς', 'س', 'ص', 'စ', 'ſ', 'ს'],
            't': ['ť', 'ţ', 'т', 'τ', 'ț', 'ت', 'ط', 'ဋ', 'တ', 'ŧ', 'თ', 'ტ'],
            'u': ['ú', 'ù', 'ủ', 'ũ', 'ụ', 'ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự', 'û', 'ū', 'ů', 'ű', 'ŭ', 'ų', 'µ', 'у', 'ဉ', 'ု', 'ူ', 'ǔ', 'ǖ', 'ǘ', 'ǚ', 'ǜ', 'უ', 'उ'],
            'v': ['в', 'ვ', 'ϐ'],
            'w': ['ŵ', 'ω', 'ώ', 'ဝ', 'ွ'],
            'x': ['χ', 'ξ'],
            'y': ['ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ', 'ÿ', 'ŷ', 'й', 'ы', 'υ', 'ϋ', 'ύ', 'ΰ', 'ي', 'ယ'],
            'z': ['ź', 'ž', 'ż', 'з', 'ζ', 'ز', 'ဇ', 'ზ'],
            'aa': ['ع', 'आ', 'آ'],
            'ae': ['ä', 'æ', 'ǽ'],
            'ai': ['ऐ'],
            'at': ['@'],
            'ch': ['ч', 'ჩ', 'ჭ', 'چ'],
            'dj': ['ђ', 'đ'],
            'dz': ['џ', 'ძ'],
            'ei': ['ऍ'],
            'gh': ['غ', 'ღ'],
            'ii': ['ई'],
            'ij': ['ĳ'],
            'kh': ['х', 'خ', 'ხ'],
            'lj': ['љ'],
            'nj': ['њ'],
            'oe': ['ö', 'œ', 'ؤ'],
            'oi': ['ऑ'],
            'oii': ['ऒ'],
            'ps': ['ψ'],
            'sh': ['ш', 'შ', 'ش'],
            'shch': ['щ'],
            'ss': ['ß'],
            'sx': ['ŝ'],
            'th': ['þ', 'ϑ', 'ث', 'ذ', 'ظ'],
            'ts': ['ц', 'ც', 'წ'],
            'ue': ['ü'],
            'uu': ['ऊ'],
            'ya': ['я'],
            'yu': ['ю'],
            'zh': ['ж', 'ჟ', 'ژ'],
            '(c)': ['©'],
            'A': ['Á', 'À', 'Ả', 'Ã', 'Ạ', 'Ă', 'Ắ', 'Ằ', 'Ẳ', 'Ẵ', 'Ặ', 'Â', 'Ấ', 'Ầ', 'Ẩ', 'Ẫ', 'Ậ', 'Å', 'Ā', 'Ą', 'Α', 'Ά', 'Ἀ', 'Ἁ', 'Ἂ', 'Ἃ', 'Ἄ', 'Ἅ', 'Ἆ', 'Ἇ', 'ᾈ', 'ᾉ', 'ᾊ', 'ᾋ', 'ᾌ', 'ᾍ', 'ᾎ', 'ᾏ', 'Ᾰ', 'Ᾱ', 'Ὰ', 'Ά', 'ᾼ', 'А', 'Ǻ', 'Ǎ'],
            'B': ['Б', 'Β', 'ब'],
            'C': ['Ç', 'Ć', 'Č', 'Ĉ', 'Ċ'],
            'D': ['Ď', 'Ð', 'Đ', 'Ɖ', 'Ɗ', 'Ƌ', 'ᴅ', 'ᴆ', 'Д', 'Δ'],
            'E': ['É', 'È', 'Ẻ', 'Ẽ', 'Ẹ', 'Ê', 'Ế', 'Ề', 'Ể', 'Ễ', 'Ệ', 'Ë', 'Ē', 'Ę', 'Ě', 'Ĕ', 'Ė', 'Ε', 'Έ', 'Ἐ', 'Ἑ', 'Ἒ', 'Ἓ', 'Ἔ', 'Ἕ', 'Έ', 'Ὲ', 'Е', 'Ё', 'Э', 'Є', 'Ə'],
            'F': ['Ф', 'Φ'],
            'G': ['Ğ', 'Ġ', 'Ģ', 'Г', 'Ґ', 'Γ'],
            'H': ['Η', 'Ή', 'Ħ'],
            'I': ['Í', 'Ì', 'Ỉ', 'Ĩ', 'Ị', 'Î', 'Ï', 'Ī', 'Ĭ', 'Į', 'İ', 'Ι', 'Ί', 'Ϊ', 'Ἰ', 'Ἱ', 'Ἳ', 'Ἴ', 'Ἵ', 'Ἶ', 'Ἷ', 'Ῐ', 'Ῑ', 'Ὶ', 'Ί', 'И', 'І', 'Ї', 'Ǐ', 'ϒ'],
            'K': ['К', 'Κ'],
            'L': ['Ĺ', 'Ł', 'Л', 'Λ', 'Ļ', 'Ľ', 'Ŀ', 'ल'],
            'M': ['М', 'Μ'],
            'N': ['Ń', 'Ñ', 'Ň', 'Ņ', 'Ŋ', 'Н', 'Ν'],
            'O': ['Ó', 'Ò', 'Ỏ', 'Õ', 'Ọ', 'Ô', 'Ố', 'Ồ', 'Ổ', 'Ỗ', 'Ộ', 'Ơ', 'Ớ', 'Ờ', 'Ở', 'Ỡ', 'Ợ', 'Ø', 'Ō', 'Ő', 'Ŏ', 'Ο', 'Ό', 'Ὀ', 'Ὁ', 'Ὂ', 'Ὃ', 'Ὄ', 'Ὅ', 'Ὸ', 'Ό', 'О', 'Θ', 'Ө', 'Ǒ', 'Ǿ'],
            'P': ['П', 'Π'],
            'R': ['Ř', 'Ŕ', 'Р', 'Ρ', 'Ŗ'],
            'S': ['Ş', 'Ŝ', 'Ș', 'Š', 'Ś', 'С', 'Σ'],
            'T': ['Ť', 'Ţ', 'Ŧ', 'Ț', 'Т', 'Τ'],
            'U': ['Ú', 'Ù', 'Ủ', 'Ũ', 'Ụ', 'Ư', 'Ứ', 'Ừ', 'Ử', 'Ữ', 'Ự', 'Û', 'Ū', 'Ů', 'Ű', 'Ŭ', 'Ų', 'У', 'Ǔ', 'Ǖ', 'Ǘ', 'Ǚ', 'Ǜ'],
            'V': ['В'],
            'W': ['Ω', 'Ώ', 'Ŵ'],
            'X': ['Χ', 'Ξ'],
            'Y': ['Ý', 'Ỳ', 'Ỷ', 'Ỹ', 'Ỵ', 'Ÿ', 'Ῠ', 'Ῡ', 'Ὺ', 'Ύ', 'Ы', 'Й', 'Υ', 'Ϋ', 'Ŷ'],
            'Z': ['Ź', 'Ž', 'Ż', 'З', 'Ζ'],
            'AE': ['Ä', 'Æ', 'Ǽ'],
            'CH': ['Ч'],
            'DJ': ['Ђ'],
            'DZ': ['Џ'],
            'GX': ['Ĝ'],
            'HX': ['Ĥ'],
            'IJ': ['Ĳ'],
            'JX': ['Ĵ'],
            'KH': ['Х'],
            'LJ': ['Љ'],
            'NJ': ['Њ'],
            'OE': ['Ö', 'Œ'],
            'PS': ['Ψ'],
            'SH': ['Ш'],
            'SHCH': ['Щ'],
            'SS': ['ẞ'],
            'TH': ['Þ'],
            'TS': ['Ц'],
            'UE': ['Ü'],
            'YA': ['Я'],
            'YU': ['Ю'],
            'ZH': ['Ж'],           
            // Whitespace characters mapping (approximated)
            ' ': ["\u00A0", "\u2000", "\u2001", "\u2002", "\u2003", "\u2004", "\u2005", "\u2006", "\u2007", "\u2008", "\u2009", "\u200A", "\u202F", "\u205F", "\u3000"],
        };
  }
}
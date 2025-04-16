// File: lib/src/doctrine/platforms/keywords/keyword_list.dart

/// Abstract interface for a SQL reserved keyword dictionary.
///
/// Concrete subclasses must implement [getKeywords] to provide the list
/// of reserved words for a specific platform.
abstract class KeywordList {
  /// Internal cache for keywords, stored in uppercase for efficient lookup.
  /// Initialized lazily on the first call to [isKeyword].
  Set<String>? _keywords;

  /// Checks if the given word is a keyword of this dialect/vendor platform.
  ///
  /// Comparison is case-insensitive.
  bool isKeyword(String word) {
    // Lazily initialize the keyword set if it hasn't been already.
    // The ??= operator assigns the result of _initializeKeywords() to _keywords
    // only if _keywords is currently null.
    _keywords ??= _initializeKeywords();

    // Check if the uppercase version of the word exists in the set.
    // The ! operator asserts that _keywords is non-null after the ??= check.
    return _keywords!.contains(word.toUpperCase());
  }

  /// Initializes the internal keyword set from the list provided by [getKeywords].
  /// Converts all keywords to uppercase for case-insensitive lookup.
  ///
  /// This method is called internally by [isKeyword] when needed.
  Set<String> _initializeKeywords() {
    // Call the abstract method to get the platform-specific keywords,
    // convert them to uppercase, and store them efficiently in a Set.
    return getKeywords().map((keyword) => keyword.toUpperCase()).toSet();
  }

  /// Returns the list of keywords for the specific platform.
  ///
  /// This method MUST be implemented by concrete subclasses extending [KeywordList].
  /// The returned list should contain all reserved words for that database platform.
  List<String> getKeywords();
}
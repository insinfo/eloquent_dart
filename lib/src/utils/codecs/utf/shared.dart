import 'util.dart';

// NOTE(jmesserly): would be nice to have this on String (dartbug.com/6501).
/// Returns the Unicode code points for the provided string.
List<int> stringToCodepoints(String str) {
  // Note: str.codeUnits gives us 16-bit code units on all Dart implementations.
  // So we need to convert.
  return utf16CodeUnitsToCodepoints(str.codeUnits);
}

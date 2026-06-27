library galileo_utf.util;

import 'constants.dart';
import 'list_range.dart';
import 'utf_16_code_unit_decoder.dart';

/// Decodes UTF-16 code units to Unicode code points.
List<int> utf16CodeUnitsToCodepoints(List<int> utf16CodeUnits,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  final ListRangeIterator source =
      ListRange(utf16CodeUnits, offset, length).iterator;
  final decoder =
      Utf16CodeUnitDecoder.fromListRangeIterator(source, replacementCodepoint);
  List<int> codepoints = List<int>.filled(source.remaining, 0, growable: false);
  int i = 0;
  while (decoder.moveNext()) {
    codepoints[i++] = decoder.current;
  }
  if (i == codepoints.length) {
    return codepoints;
  } else {
    List<int> codepointTrunc = List<int>.filled(i, 0, growable: false);
    codepointTrunc.setRange(0, i, codepoints);
    return codepointTrunc;
  }
}

/// Encodes Unicode code points as UTF-16 code units.
List<int> codepointsToUtf16CodeUnits(List<int> codepoints,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  final listRange = ListRange(codepoints, offset, length);
  int encodedLength = 0;
  for (final value in listRange) {
    if ((value >= 0 && value < UNICODE_UTF16_RESERVED_LO) ||
        (value > UNICODE_UTF16_RESERVED_HI && value <= UNICODE_PLANE_ONE_MAX)) {
      encodedLength++;
    } else if (value > UNICODE_PLANE_ONE_MAX &&
        value <= UNICODE_VALID_RANGE_MAX) {
      encodedLength += 2;
    } else {
      encodedLength++;
    }
  }

  List<int> codeUnitsBuffer =
      List<int>.filled(encodedLength, 0, growable: false);
  int j = 0;
  for (final value in listRange) {
    if ((value >= 0 && value < UNICODE_UTF16_RESERVED_LO) ||
        (value > UNICODE_UTF16_RESERVED_HI && value <= UNICODE_PLANE_ONE_MAX)) {
      codeUnitsBuffer[j++] = value;
    } else if (value > UNICODE_PLANE_ONE_MAX &&
        value <= UNICODE_VALID_RANGE_MAX) {
      int base = value - UNICODE_UTF16_OFFSET;
      codeUnitsBuffer[j++] = UNICODE_UTF16_SURROGATE_UNIT_0_BASE +
          ((base & UNICODE_UTF16_HI_MASK) >> 10);
      codeUnitsBuffer[j++] =
          UNICODE_UTF16_SURROGATE_UNIT_1_BASE + (base & UNICODE_UTF16_LO_MASK);
    } else if (replacementCodepoint != null) {
      codeUnitsBuffer[j++] = replacementCodepoint;
    } else {
      throw ArgumentError("Invalid encoding");
    }
  }
  return codeUnitsBuffer;
}

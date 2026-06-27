import 'dart:convert';

part 'table.dart';

// only non-stream version

/// Big5 codec instance
///
/// Compare https://en.wikipedia.org/wiki/Big5
const Big5Codec big5 = Big5Codec();

// big5 constants.
const int _runeError = 0xFFFD;
const int _runeSelf = 0x80;

/// A Big5 compatible codec
class Big5Codec extends Encoding {
  /// Creates a new [Big5Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Big5Codec({this.allowInvalid = false});

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Converter<List<int>, String> get decoder => allowInvalid
      ? const Big5Decoder(allowInvalid: true)
      : const Big5Decoder();

  @override
  Converter<String, List<int>> get encoder => allowInvalid
      ? const Big5Encoder(allowInvalid: true)
      : const Big5Encoder();

  @override
  String get name => 'Big5';
}

/// A Big5 compatible encoder
///
/// Compare https://en.wikipedia.org/wiki/Big5
class Big5Encoder extends Converter<String, List<int>> {
  /// Creates a new [Big5Encoder]
  const Big5Encoder({this.allowInvalid = false});

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, then an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  List<int> convert(String input, [int start = 0, int? end]) {
    var runes = input.runes.toList(growable: false);
    final usedEnd = RangeError.checkValidRange(start, end, runes.length);
    if (start > 0 || usedEnd < runes.length) {
      runes = runes.sublist(start, usedEnd);
    }

    int? r = 0;
    const size = 1;
    final dst = <int>[];

    void write2(int r) {
      dst
        ..add(r >> 8)
        ..add(r % 256);
    }

    for (var nSrc = start; nSrc < usedEnd; nSrc += size) {
      r = runes[nSrc];

      // Decode a 1-byte rune.
      if (r < _runeSelf) {
        dst.add(r);
        continue;
      } else {
        // NOTE(RV) consider supporting multiple bytes.
        if (_encode0Low <= r && r < _encode0High) {
          r = _encodeTable0[r - _encode0Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode1Low <= r && r < _encode1High) {
          r = _encodeTable1[r - _encode1Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode2Low <= r && r < _encode2High) {
          r = _encodeTable2[r - _encode2Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode3Low <= r && r < _encode3High) {
          r = _encodeTable3[r - _encode3Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode4Low <= r && r < _encode4High) {
          r = _encodeTable4[r - _encode4Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode5Low <= r && r < _encode5High) {
          r = _encodeTable5[r - _encode5Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode6Low <= r && r < _encode6High) {
          r = _encodeTable6[r - _encode6Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        } else if (_encode7Low <= r && r < _encode7High) {
          r = _encodeTable7[r - _encode7Low];
          if (r != null && r != 0) {
            write2(r);
            continue;
          }
        }
        if (allowInvalid) {
          dst.add(0x3f); // ASCII '?'
        } else {
          throw FormatException(
              'Invalid character $r at position $nSrc in $input');
        }
      }
    }
    return dst;
  }
}

/// A Big5 compatible decoder
///
/// Compare https://en.wikipedia.org/wiki/Big5
class Big5Decoder extends Converter<List<int>, String> {
  /// Creates a new [Big5Decoder]
  const Big5Decoder({this.allowInvalid = false});

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, then an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  String convert(List<int> input, [int start = 0, int? end]) {
    final usedEnd = RangeError.checkValidRange(start, end, input.length);

    var r = 0;
    var size = 0;
    final nDst = StringBuffer();

    void write(int code) => nDst.write(String.fromCharCode(code));

    for (var nSrc = start; nSrc < usedEnd; nSrc += size) {
      final c0 = input[nSrc];
      if (c0 < 0x80) {
        r = c0;
        size = 1;
      } else if (0x81 <= c0 && c0 < 0xFF) {
        if (nSrc + 1 >= input.length) {
          r = _runeError;
          size = 1;
          write(r);
          continue;
        }
        final c1 = input[nSrc + 1];
        r = 0xfffd;
        size = 2;

        final i = c0 * 16 * 16 + c1;
        final s = _decodeTable[i];
        if (s != null) {
          write(s);
          continue;
        }
      } else if (allowInvalid) {
        r = _runeError;
        size = 1;
      } else {
        throw FormatException('Encountered invalid rune $c0 at position $nSrc');
      }
      write(r);
      continue;
    }
    return nDst.toString();
  }
}

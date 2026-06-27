import 'dart:convert' as dart_convert;

import 'dart:typed_data';

/// Contains base classes for 8bit codecs

/// Provides a simple decoder.
class BaseDecoder extends dart_convert.Converter<List<int>, String> {
  /// Creates a new 8bit decoder.
  ///
  /// [symbols] contain all symbols different than UTF8 from the
  /// specified [startIndex] onwards.
  ///
  /// The length of the [symbols] need to be `255` / `0xFF` minus
  /// the [startIndex].
  ///
  /// Set [allowInvalid] to true in case invalid characters sequences
  /// should be at least readable.
  const BaseDecoder(this.symbols, this.startIndex, {this.allowInvalid = false})
      : startBlock = null,
        assert(symbols.length == 255 - startIndex, 'invalid length of symbols');

  /// Creates a a base decoder with a non-ascii start block
  const BaseDecoder.withNonAsciiStartBlock(
      String startBlock, this.symbols, this.startIndex,
      {this.allowInvalid = false})
      // ignore: prefer_initializing_formals, unnecessary_this
      : this.startBlock = startBlock,
        assert(symbols.length == 255 - startIndex, 'invalid length of symbols');

  /// The start pattern for partially non-Ascii compliant character sets
  /// like DOS-Latin-1 / cp-850.
  final String? startBlock;

  /// The used symbols
  final String symbols;

  /// The index of the first non-ASCII character
  final int startIndex;

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  String convert(List<int> input, [int start = 0, int? end]) {
    final usedEnd = RangeError.checkValidRange(start, end, input.length);
    final startBlock = this.startBlock;
    final startBlockLength = startBlock?.length ?? 0;
    List<int>? modified;
    for (var i = start; i < usedEnd; i++) {
      final byte = input[i];
      if ((byte & ~0xFF) != 0) {
        if (!allowInvalid) {
          throw FormatException('Invalid value in input: $byte '
              'at position $i '
              'in "${String.fromCharCodes(input, start, usedEnd)}"');
        } else {
          modified ??= List.from(input);
          modified[i] = 0xFFFD; // unicode �
        }
      } else if (byte > startIndex) {
        final index = byte - (startIndex + 1);
        modified ??= List.from(input);
        modified[i] = symbols.codeUnitAt(index);
      } else if (byte <= startBlockLength) {
        modified ??= List.from(input);
        modified[i] = startBlock!.codeUnitAt(byte - 1);
      }
    }
    return String.fromCharCodes(modified ?? input, start, end);
  }

  @override
  dart_convert.ByteConversionSink startChunkedConversion(Sink<String> sink) {
    dart_convert.StringConversionSink stringSink;
    if (sink is dart_convert.StringConversionSink) {
      stringSink = sink;
    } else {
      stringSink = dart_convert.StringConversionSink.from(sink);
    }
    return BaseDecoderSink(stringSink, this, allowInvalid: allowInvalid);
  }
}

/// Provides a simple 8bit encoder.
class BaseEncoder extends dart_convert.Converter<String, List<int>> {
  /// Creates a new encoder.
  ///
  /// Set [allowInvalid] to true in case invalid characters should be
  /// translated to question marks.
  const BaseEncoder(
    this.encodingMap,
    this.startIndex, {
    this.allowInvalid = false,
    this.lowerEndIndex = -1,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, then an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  /// All encodings
  final Map<int, int> encodingMap;

  /// The index of the first non-ASCII character
  final int startIndex;

  /// End index of the lower block.
  ///
  /// Usually there is no lower block and this is `-1`.
  final int lowerEndIndex;

  /// Static helper function to generate a conversion map from a symbols string.
  static Map<int, int> createEncodingMap(String symbols, int startIndex) {
    final runes = symbols.runes;
    final map = <int, int>{};
    var index = 0;
    if (runes.length != 255 - startIndex) {
      print('WARNING: there are not ${255 - startIndex} symbols '
          'but ${runes.length} runes in the specified map - '
          'is the given startIndex $startIndex correct?');
    }
    for (final rune in runes) {
      if (rune != 0x3F) {
        // "?" denote an empty slot in the map
        final value = index + startIndex + 1;
        if (map.containsValue(value)) {
          final symbol = symbols.substring(index, index + 1);
          final firstIndex = symbols.indexOf(symbol);
          final lastIndex = symbols.lastIndexOf(symbol);
          throw FormatException(
              'Duplicate value $value for symbols "$symbol" at index $index '
              '- in symbols to found at $firstIndex and $lastIndex');
        }
        if (value <= startIndex) {
          final symbol = symbols.substring(index, index + 1);
          throw FormatException(
              'Invalid value $value for "$symbol" at index $index');
        }
        map[rune] = value;
        print('\t$rune: $value,');
      }
      index++;
    }
    return map;
  }

  @override
  List<int> convert(String input, [int start = 0, int? end]) {
    var runesList = input.runes.toList(growable: false);
    final usedEnd = RangeError.checkValidRange(start, end, runesList.length);
    if (start > 0 || usedEnd < runesList.length) {
      runesList = runesList.sublist(start, usedEnd);
    }
    for (var i = 0; i < runesList.length; i++) {
      final rune = runesList[i];
      if (rune > startIndex || (rune <= lowerEndIndex && rune > 0)) {
        final value = encodingMap[rune];
        if (value == null) {
          if (!allowInvalid) {
            throw FormatException(
                'Invalid value in input: "${String.fromCharCode(rune)}" '
                '/ ($rune) at index $i of "$input"');
          } else {
            runesList[i] = 0x3F; // ?
          }
        } else {
          runesList[i] = value;
        }
      }
    }
    return runesList;
  }

  @override
  dart_convert.StringConversionSink startChunkedConversion(
      Sink<List<int>> sink) {
    dart_convert.ByteConversionSink byteSink;
    if (sink is dart_convert.ByteConversionSink) {
      byteSink = sink;
    } else {
      byteSink = dart_convert.ByteConversionSink.from(sink);
    }
    return BaseEncoderSink(byteSink, this);
  }
}

/// Decoder sink for chunked conversion.
///
/// Compare `BaseDecoder.startChunkedConversion(...)`.
class BaseDecoderSink extends dart_convert.ByteConversionSinkBase {
  /// Creates a new basic decoder sink
  BaseDecoderSink(
    this.sink,
    this.decoder, {
    required this.allowInvalid,
  });

  /// The used string conversion sink
  final dart_convert.StringConversionSink sink;

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, then an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  /// The used decoder
  final BaseDecoder decoder;

  @override
  void close() {
    sink.close();
  }

  @override
  void add(List<int> chunk) {
    addSlice(chunk, 0, chunk.length, false);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    RangeError.checkValidRange(start, end, chunk.length);
    if (start == end) {
      return;
    }
    if (!allowInvalid && chunk is! Uint8List) {
      // List may contain value outside of the 0..255 range. If so, throw.
      // Technically, we could excuse Uint8ClampedList as well, but it unlikely
      // to be relevant.
      _checkValid8Bit(chunk, start, end);
    }
    _addSliceToSink(chunk, start, end, isLast);
  }

  void _addSliceToSink(List<int> source, int start, int end, bool isLast) {
    final sliceText = decoder.convert(source, start, end);
    sink.add(sliceText);
    if (isLast) {
      close();
    }
  }

  void _checkValid8Bit(List<int> source, int start, int end) {
    for (var i = start; i < end; i++) {
      final char = source[i];
      if (char < 0 || char > 0xff) {
        throw FormatException(
            'Source contains non-8-bit character '
            'code 0x${char.toRadixString(16)} at $i.',
            source,
            i);
      }
    }
  }
}

/// Encoder sink for chunked conversion.
///
/// Compare [BaseEncoder.startChunkedConversion].
class BaseEncoderSink extends dart_convert.StringConversionSinkBase {
  /// Creates a new basic encoder sink
  BaseEncoderSink(this.sink, this.encoder);

  /// The used byte conversion sink
  final dart_convert.ByteConversionSink sink;

  /// The used encoder
  final BaseEncoder encoder;

  @override
  void close() {
    sink.close();
  }

  @override
  void add(String str) {
    addSlice(str, 0, str.length, false);
  }

  @override
  void addSlice(String str, int start, int end, bool isLast) {
    RangeError.checkValidRange(start, end, str.length);
    if (start == end) {
      return;
    }

    final sliceData = encoder.convert(str, start, end);
    sink.add(sliceData);
    if (isLast) {
      close();
    }
  }
}

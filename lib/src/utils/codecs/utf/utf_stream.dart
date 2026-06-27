library galileo_utf.utf_stream;

import 'dart:async';

import 'constants.dart';
import 'util.dart';

// NOTE(floitsch): make this transformer reusable.
abstract class _StringDecoder extends StreamTransformerBase<List<int>, String>
    implements EventSink<List<int>> {
  List<int>? _carry;
  List<int>? _buffer;
  final int? _replacementChar;

  EventSink<String>? _outSink;

  _StringDecoder(this._replacementChar);

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    return Stream<String>.eventTransformed(stream, (EventSink<String> sink) {
      if (_outSink != null) {
        throw StateError("String decoder already used");
      }
      _outSink = sink;
      return this;
    });
  }

  @override
  void add(List<int> bytes) {
    try {
      final buffer = <int>[];
      _buffer = buffer;
      final carry = _carry;
      _carry = null;
      int pos = 0;
      int available = bytes.length;
      // If we have carry-over data, start from negative index, indicating carry
      // index.
      int goodChars = 0;
      if (carry != null) pos = -carry.length;
      while (pos < available) {
        int currentPos = pos;
        int? getNext() {
          if (pos < 0) {
            return carry![pos++ + carry.length];
          } else if (pos < available) {
            return bytes[pos++];
          }
          return null;
        }

        int consumed = _processBytes(getNext);
        if (consumed > 0) {
          goodChars = buffer.length;
        } else if (consumed == 0) {
          buffer.length = goodChars;
          if (currentPos < 0) {
            final newCarry = <int>[];
            if (carry != null) {
              newCarry.addAll(carry);
            }
            newCarry.addAll(bytes);
            _carry = newCarry;
          } else {
            _carry = bytes.sublist(currentPos);
          }
          break;
        } else {
          // Invalid byte at position pos - 1
          buffer.length = goodChars;
          _addChar(-1);
          goodChars = buffer.length;
        }
      }
      if (buffer.isNotEmpty) {
        // Limit to 'goodChars', if lower than actual charCodes in the buffer.
        if (goodChars < buffer.length) {
          buffer.length = goodChars;
        }
        _outSink!.add(String.fromCharCodes(buffer));
      }
      _buffer = null;
    } catch (e, stackTrace) {
      _outSink!.addError(e, stackTrace);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outSink!.addError(error, stackTrace);
  }

  @override
  void close() {
    final carry = _carry;
    if (carry != null) {
      final replacement = _replacementChar;
      if (replacement != null) {
        _outSink!.add(
            String.fromCharCodes(List<int>.filled(carry.length, replacement)));
      } else {
        throw ArgumentError('Invalid codepoint');
      }
    }
    _outSink!.close();
  }

  int _processBytes(int? Function() getNext);

  void _addChar(int char) {
    void error() {
      final replacement = _replacementChar;
      if (replacement != null) {
        char = replacement;
      } else {
        throw ArgumentError('Invalid codepoint');
      }
    }

    if (char < 0) error();
    if (char >= 0xD800 && char <= 0xDFFF) error();
    if (char > 0x10FFFF) error();
    final buffer = _buffer;
    if (buffer == null) {
      throw StateError('No buffer available');
    }
    buffer.add(char);
  }
}

/// Stream transformer that decodes UTF-8 encoded byte chunks into strings.
class Utf8DecoderTransformer extends _StringDecoder {
  Utf8DecoderTransformer(
      [int replacementChar = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : super(replacementChar);

  @override
  int _processBytes(int? Function() getNext) {
    final first = getNext();
    if (first == null) return 0;
    int value = first;
    if ((value & 0xFF) != value) return -1; // Not a byte.
    if ((value & 0x80) == 0x80) {
      int additionalBytes;
      int min;
      if ((value & 0xe0) == 0xc0) {
        // 110xxxxx
        value = value & 0x1F;
        additionalBytes = 1;
        min = 0x80;
      } else if ((value & 0xf0) == 0xe0) {
        // 1110xxxx
        value = value & 0x0F;
        additionalBytes = 2;
        min = 0x800;
      } else if ((value & 0xf8) == 0xf0) {
        // 11110xxx
        value = value & 0x07;
        additionalBytes = 3;
        min = 0x10000;
      } else if ((value & 0xfc) == 0xf8) {
        // 111110xx
        value = value & 0x03;
        additionalBytes = 4;
        min = 0x200000;
      } else if ((value & 0xfe) == 0xfc) {
        // 1111110x
        value = value & 0x01;
        additionalBytes = 5;
        min = 0x4000000;
      } else {
        return -1;
      }
      for (int i = 0; i < additionalBytes; i++) {
        final next = getNext();
        if (next == null) return 0; // Not enough chars, reset.
        if ((next & 0xc0) != 0x80 || (next & 0xff) != next) return -1;
        value = value << 6 | (next & 0x3f);
        if (additionalBytes >= 3 && i == 0 && value << 12 > 0x10FFFF) {
          _addChar(-1);
        }
      }
      // Invalid charCode if less then minimum expected.
      if (value < min) value = -1;
      _addChar(value);
      return 1 + additionalBytes;
    }
    _addChar(value);
    return 1;
  }
}

abstract class _StringEncoder extends StreamTransformerBase<String, List<int>>
    implements EventSink<String> {
  EventSink<List<int>>? _outSink;

  @override
  Stream<List<int>> bind(Stream<String> stream) {
    return Stream<List<int>>.eventTransformed(stream,
        (EventSink<List<int>> sink) {
      if (_outSink != null) {
        throw StateError("String encoder already used");
      }
      _outSink = sink;
      return this;
    });
  }

  @override
  void add(String data) {
    _outSink!.add(_processString(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outSink!.addError(error, stackTrace);
  }

  @override
  void close() {
    _outSink!.close();
  }

  List<int> _processString(String string);
}

/// Stream transformer that UTF-8 encodes a stream of strings into byte lists.
class Utf8EncoderTransformer extends _StringEncoder {
  @override
  List<int> _processString(String string) {
    var bytes = <int>[];
    List<int> codepoints = utf16CodeUnitsToCodepoints(string.codeUnits);
    int length = codepoints.length;
    for (int i = 0; i < length; i++) {
      int additionalBytes;
      int charCode = codepoints[i];
      if (charCode <= 0x007F) {
        additionalBytes = 0;
        bytes.add(charCode);
      } else if (charCode <= 0x07FF) {
        // 110xxxxx (xxxxx is top 5 bits).
        bytes.add(((charCode >> 6) & 0x1F) | 0xC0);
        additionalBytes = 1;
      } else if (charCode <= 0xFFFF) {
        // 1110xxxx (xxxx is top 4 bits)
        bytes.add(((charCode >> 12) & 0x0F) | 0xE0);
        additionalBytes = 2;
      } else {
        // 11110xxx (xxx is top 3 bits)
        bytes.add(((charCode >> 18) & 0x07) | 0xF0);
        additionalBytes = 3;
      }
      for (int i = additionalBytes; i > 0; i--) {
        // 10xxxxxx (xxxxxx is next 6 bits from the top).
        bytes.add(((charCode >> (6 * (i - 1))) & 0x3F) | 0x80);
      }
    }
    return bytes;
  }
}

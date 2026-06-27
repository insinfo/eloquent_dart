import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 8 / iso-8859-8 codec for easy encoding and decoding.
class Latin8Codec extends dart_convert.Encoding {
  /// Creates a new [Latin8Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin8Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin8Decoder get decoder => allowInvalid
      ? const Latin8Decoder(allowInvalid: true)
      : const Latin8Decoder(allowInvalid: false);

  @override
  Latin8Encoder get encoder => allowInvalid
      ? const Latin8Encoder(allowInvalid: true)
      : const Latin8Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-8';
}

/// Encodes texts into latin 8 / iso-8859-8 data
class Latin8Encoder extends LatinEncoder {
  /// Creates a new [Latin8Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin8Encoder({
    bool allowInvalid = false,
  }) : super(_latin8SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 8 /  iso-8859-8 data.
class Latin8Decoder extends LatinDecoder {
  /// Creates a new [Latin8Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin8Decoder({
    bool allowInvalid = false,
  }) : super(_latin8Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin8Symbols =
// ignore: lines_longer_than_80_chars
    '?¢£¤¥¦§¨©×«¬\u{00AD}®¯°±²³´µ¶·¸¹÷»¼½¾????????????????????????????????‗אבגדהוזחטיךכלםמןנסעףפץצקרשת??\u{8206}\u{8207}?';
const Map<int, int> _latin8SymbolMap = {
  162: 162,
  163: 163,
  164: 164,
  165: 165,
  166: 166,
  167: 167,
  168: 168,
  169: 169,
  215: 170,
  171: 171,
  172: 172,
  173: 173,
  174: 174,
  175: 175,
  176: 176,
  177: 177,
  178: 178,
  179: 179,
  180: 180,
  181: 181,
  182: 182,
  183: 183,
  184: 184,
  185: 185,
  247: 186,
  187: 187,
  188: 188,
  189: 189,
  190: 190,
  8215: 223,
  1488: 224,
  1489: 225,
  1490: 226,
  1491: 227,
  1492: 228,
  1493: 229,
  1494: 230,
  1495: 231,
  1496: 232,
  1497: 233,
  1498: 234,
  1499: 235,
  1500: 236,
  1501: 237,
  1502: 238,
  1503: 239,
  1504: 240,
  1505: 241,
  1506: 242,
  1507: 243,
  1508: 244,
  1509: 245,
  1510: 246,
  1511: 247,
  1512: 248,
  1513: 249,
  1514: 250,
  33286: 253,
  33287: 254,
};

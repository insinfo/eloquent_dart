import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 6 / iso-8859-6 codec for easy encoding and decoding.
class Latin6Codec extends dart_convert.Encoding {
  /// Creates a new [Latin6Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin6Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin6Decoder get decoder => allowInvalid
      ? const Latin6Decoder(allowInvalid: true)
      : const Latin6Decoder(allowInvalid: false);

  @override
  Latin6Encoder get encoder => allowInvalid
      ? const Latin6Encoder(allowInvalid: true)
      : const Latin6Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-6';
}

/// Encodes texts into latin 6 / iso-8859-6 data
class Latin6Encoder extends LatinEncoder {
  /// Creates a new [Latin6Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin6Encoder({
    bool allowInvalid = false,
  }) : super(_latin6SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 6 /  iso-8859-6 data.
class Latin6Decoder extends LatinDecoder {
  /// Creates a new [Latin6Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin6Decoder({
    bool allowInvalid = false,
  }) : super(_latin6Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin6Symbols =
// ignore: lines_longer_than_80_chars
    '???¤???????،\u{00AD}?????????????؛???؟?ءآأؤإئابةتثجحخدذرزسشصضطظعغ?????ـفقكلمنهوىيًٌٍَُِّْ?????????????';
const Map<int, int> _latin6SymbolMap = {
  164: 164,
  1548: 172,
  173: 173,
  1563: 187,
  1567: 191,
  1569: 193,
  1570: 194,
  1571: 195,
  1572: 196,
  1573: 197,
  1574: 198,
  1575: 199,
  1576: 200,
  1577: 201,
  1578: 202,
  1579: 203,
  1580: 204,
  1581: 205,
  1582: 206,
  1583: 207,
  1584: 208,
  1585: 209,
  1586: 210,
  1587: 211,
  1588: 212,
  1589: 213,
  1590: 214,
  1591: 215,
  1592: 216,
  1593: 217,
  1594: 218,
  1600: 224,
  1601: 225,
  1602: 226,
  1603: 227,
  1604: 228,
  1605: 229,
  1606: 230,
  1607: 231,
  1608: 232,
  1609: 233,
  1610: 234,
  1611: 235,
  1612: 236,
  1613: 237,
  1614: 238,
  1615: 239,
  1616: 240,
  1617: 241,
  1618: 242,
};

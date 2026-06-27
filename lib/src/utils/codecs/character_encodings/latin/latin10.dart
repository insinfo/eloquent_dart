import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 10 / iso-8859-10 codec for easy encoding and decoding.
class Latin10Codec extends dart_convert.Encoding {
  /// Creates a new [Latin10Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin10Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin10Decoder get decoder => allowInvalid
      ? const Latin10Decoder(allowInvalid: true)
      : const Latin10Decoder(allowInvalid: false);

  @override
  Latin10Encoder get encoder => allowInvalid
      ? const Latin10Encoder(allowInvalid: true)
      : const Latin10Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-10';
}

/// Encodes texts into latin 10 / iso-88510-10 data
class Latin10Encoder extends LatinEncoder {
  /// Creates a new [Latin10Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin10Encoder({
    bool allowInvalid = false,
  }) : super(_latin10SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 10 /  iso-88510-10 data.
class Latin10Decoder extends LatinDecoder {
  /// Creates a new [Latin10Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin10Decoder({
    bool allowInvalid = false,
  }) : super(_latin10Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin10Symbols =
// ignore: lines_longer_than_80_chars
    'ĄĒĢĪĨĶ§ĻĐŠŦŽ\u{00AD}ŪŊ°ąēģīĩķ·ļđšŧž―ūŋĀÁÂÃÄÅÆĮČÉĘËĖÍÎÏÐŅŌÓÔÕÖŨØŲÚÛÜÝÞßāáâãäåæįčéęëėíîïðņōóôõöũøųúûüýþĸ';
const Map<int, int> _latin10SymbolMap = {
  260: 161,
  274: 162,
  290: 163,
  298: 164,
  296: 165,
  310: 166,
  167: 167,
  315: 168,
  272: 169,
  352: 170,
  358: 171,
  381: 172,
  173: 173,
  362: 174,
  330: 175,
  176: 176,
  261: 177,
  275: 178,
  291: 179,
  299: 180,
  297: 181,
  311: 182,
  183: 183,
  316: 184,
  273: 185,
  353: 186,
  359: 187,
  382: 188,
  8213: 189,
  363: 190,
  331: 191,
  256: 192,
  193: 193,
  194: 194,
  195: 195,
  196: 196,
  197: 197,
  198: 198,
  302: 199,
  268: 200,
  201: 201,
  280: 202,
  203: 203,
  278: 204,
  205: 205,
  206: 206,
  207: 207,
  208: 208,
  325: 209,
  332: 210,
  211: 211,
  212: 212,
  213: 213,
  214: 214,
  360: 215,
  216: 216,
  370: 217,
  218: 218,
  219: 219,
  220: 220,
  221: 221,
  222: 222,
  223: 223,
  257: 224,
  225: 225,
  226: 226,
  227: 227,
  228: 228,
  229: 229,
  230: 230,
  303: 231,
  269: 232,
  233: 233,
  281: 234,
  235: 235,
  279: 236,
  237: 237,
  238: 238,
  239: 239,
  240: 240,
  326: 241,
  333: 242,
  243: 243,
  244: 244,
  245: 245,
  246: 246,
  361: 247,
  248: 248,
  371: 249,
  250: 250,
  251: 251,
  252: 252,
  253: 253,
  254: 254,
  312: 255,
};

import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 2 / iso-8859-2 codec for easy encoding and decoding.
class Latin2Codec extends dart_convert.Encoding {
  /// Creates a new [Latin2Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin2Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin2Decoder get decoder => allowInvalid
      ? const Latin2Decoder(allowInvalid: true)
      : const Latin2Decoder(allowInvalid: false);

  @override
  Latin2Encoder get encoder => allowInvalid
      ? const Latin2Encoder(allowInvalid: true)
      : const Latin2Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-2';
}

/// Encodes texts into latin 2 / iso-8859-2 data
class Latin2Encoder extends LatinEncoder {
  /// Creates a new [Latin2Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin2Encoder({
    bool allowInvalid = false,
  }) : super(_latin2SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 2 /  iso-8859-2 data.
class Latin2Decoder extends LatinDecoder {
  /// Creates a new [Latin2Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin2Decoder({
    bool allowInvalid = false,
  }) : super(_latin2Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin2Symbols =
// ignore: lines_longer_than_80_chars
    'Ą˘Ł¤ĽŚ§¨ŠŞŤŹ\u{00AD}ŽŻ°ą˛ł´ľśˇ¸šşťź˝žżŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇÓÔŐÖ×ŘŮÚŰÜÝŢßŕáâăäĺćçčéęëěíîďđńňóôőö÷řůúűüýţ˙';
const Map<int, int> _latin2SymbolMap = {
  260: 161,
  728: 162,
  321: 163,
  164: 164,
  317: 165,
  346: 166,
  167: 167,
  168: 168,
  352: 169,
  350: 170,
  356: 171,
  377: 172,
  173: 173,
  381: 174,
  379: 175,
  176: 176,
  261: 177,
  731: 178,
  322: 179,
  180: 180,
  318: 181,
  347: 182,
  711: 183,
  184: 184,
  353: 185,
  351: 186,
  357: 187,
  378: 188,
  733: 189,
  382: 190,
  380: 191,
  340: 192,
  193: 193,
  194: 194,
  258: 195,
  196: 196,
  313: 197,
  262: 198,
  199: 199,
  268: 200,
  201: 201,
  280: 202,
  203: 203,
  282: 204,
  205: 205,
  206: 206,
  270: 207,
  272: 208,
  323: 209,
  327: 210,
  211: 211,
  212: 212,
  336: 213,
  214: 214,
  215: 215,
  344: 216,
  366: 217,
  218: 218,
  368: 219,
  220: 220,
  221: 221,
  354: 222,
  223: 223,
  341: 224,
  225: 225,
  226: 226,
  259: 227,
  228: 228,
  314: 229,
  263: 230,
  231: 231,
  269: 232,
  233: 233,
  281: 234,
  235: 235,
  283: 236,
  237: 237,
  238: 238,
  271: 239,
  273: 240,
  324: 241,
  328: 242,
  243: 243,
  244: 244,
  337: 245,
  246: 246,
  247: 247,
  345: 248,
  367: 249,
  250: 250,
  369: 251,
  252: 252,
  253: 253,
  355: 254,
  729: 255,
};

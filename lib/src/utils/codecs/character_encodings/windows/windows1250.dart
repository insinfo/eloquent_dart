import 'dart:convert' as dart_convert;

import 'windows.dart';

/// Provides a windows 1250 / cp1250 codec for easy encoding and decoding.
class Windows1250Codec extends dart_convert.Encoding {
  /// Creates a new [Windows1250Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Windows1250Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Windows1250Decoder get decoder => allowInvalid
      ? const Windows1250Decoder(allowInvalid: true)
      : const Windows1250Decoder(allowInvalid: false);

  @override
  Windows1250Encoder get encoder => allowInvalid
      ? const Windows1250Encoder(allowInvalid: true)
      : const Windows1250Encoder(allowInvalid: false);

  @override
  String get name => 'windows-1250';
}

/// Decodes windows 1250 / cp1250 data.
class Windows1250Decoder extends WindowsDecoder {
  /// Creates a new [Windows1250Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Windows1250Decoder({
    bool allowInvalid = false,
  }) : super(_cp1250Symbols, allowInvalid: allowInvalid);
}

/// Encodes texts into windows 1250 data
class Windows1250Encoder extends WindowsEncoder {
  /// Creates a new [Windows1250Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Windows1250Encoder({
    bool allowInvalid = false,
  }) : super(_cp1250Map, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _cp1250Symbols =
// ignore: lines_longer_than_80_chars
    '€?‚?„…†‡?‰Š‹ŚŤŽŹ?‘’“”•–—?™š›śťžź\u{00A0}ˇ˘Ł¤Ą¦§¨©Ş«¬\u{00AD}®Ż°±˛ł´µ¶·¸ąş»Ľ˝ľżŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇÓÔŐÖ×ŘŮÚŰÜÝŢßŕáâăäĺćçčéęëěíîďđńňóôőö÷řůúűüýţ˙';
const Map<int, int> _cp1250Map = {
  8364: 128,
  8218: 130,
  8222: 132,
  8230: 133,
  8224: 134,
  8225: 135,
  8240: 137,
  352: 138,
  8249: 139,
  346: 140,
  356: 141,
  381: 142,
  377: 143,
  8216: 145,
  8217: 146,
  8220: 147,
  8221: 148,
  8226: 149,
  8211: 150,
  8212: 151,
  8482: 153,
  353: 154,
  8250: 155,
  347: 156,
  357: 157,
  382: 158,
  378: 159,
  160: 160,
  711: 161,
  728: 162,
  321: 163,
  164: 164,
  260: 165,
  166: 166,
  167: 167,
  168: 168,
  169: 169,
  350: 170,
  171: 171,
  172: 172,
  173: 173,
  174: 174,
  379: 175,
  176: 176,
  177: 177,
  731: 178,
  322: 179,
  180: 180,
  181: 181,
  182: 182,
  183: 183,
  184: 184,
  261: 185,
  351: 186,
  187: 187,
  317: 188,
  733: 189,
  318: 190,
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

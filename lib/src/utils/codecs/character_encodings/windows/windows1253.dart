import 'dart:convert' as dart_convert;

import 'windows.dart';

/// Provides a windows 1253 / cp1253 codec for easy encoding and decoding.
class Windows1253Codec extends dart_convert.Encoding {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Windows1253Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Windows1253Decoder get decoder => allowInvalid
      ? const Windows1253Decoder(allowInvalid: true)
      : const Windows1253Decoder(allowInvalid: false);

  @override
  Windows1253Encoder get encoder => allowInvalid
      ? const Windows1253Encoder(allowInvalid: true)
      : const Windows1253Encoder(allowInvalid: false);

  @override
  String get name => 'windows-1253';
}

/// Decodes windows 1253 / cp1253 data.
class Windows1253Decoder extends WindowsDecoder {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Windows1253Decoder({
    bool allowInvalid = false,
  }) : super(_cp1253Symbols, allowInvalid: allowInvalid);
}

/// Encodes texts into windows 1253 data
class Windows1253Encoder extends WindowsEncoder {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Windows1253Encoder({
    bool allowInvalid = false,
  }) : super(_cp1253Map, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _cp1253Symbols =
// ignore: lines_longer_than_80_chars
    '€?‚ƒ„…†‡?‰?‹?????‘’“”•–—?™?›????\u{00A0}΅Ά£¤¥¦§¨©?«¬\u{00AD}®―°±²³΄µ¶·ΈΉΊ»Ό½ΎΏΐΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡ?ΣΤΥΦΧΨΩΪΫάέήίΰαβγδεζηθικλμνξοπρςστυφχψωϊϋόύώ?';
const Map<int, int> _cp1253Map = {
  8364: 128,
  8218: 130,
  402: 131,
  8222: 132,
  8230: 133,
  8224: 134,
  8225: 135,
  8240: 137,
  8249: 139,
  8216: 145,
  8217: 146,
  8220: 147,
  8221: 148,
  8226: 149,
  8211: 150,
  8212: 151,
  8482: 153,
  8250: 155,
  160: 160,
  901: 161,
  902: 162,
  163: 163,
  164: 164,
  165: 165,
  166: 166,
  167: 167,
  168: 168,
  169: 169,
  171: 171,
  172: 172,
  173: 173,
  174: 174,
  8213: 175,
  176: 176,
  177: 177,
  178: 178,
  179: 179,
  900: 180,
  181: 181,
  182: 182,
  183: 183,
  904: 184,
  905: 185,
  906: 186,
  187: 187,
  908: 188,
  189: 189,
  910: 190,
  911: 191,
  912: 192,
  913: 193,
  914: 194,
  915: 195,
  916: 196,
  917: 197,
  918: 198,
  919: 199,
  920: 200,
  921: 201,
  922: 202,
  923: 203,
  924: 204,
  925: 205,
  926: 206,
  927: 207,
  928: 208,
  929: 209,
  931: 211,
  932: 212,
  933: 213,
  934: 214,
  935: 215,
  936: 216,
  937: 217,
  938: 218,
  939: 219,
  940: 220,
  941: 221,
  942: 222,
  943: 223,
  944: 224,
  945: 225,
  946: 226,
  947: 227,
  948: 228,
  949: 229,
  950: 230,
  951: 231,
  952: 232,
  953: 233,
  954: 234,
  955: 235,
  956: 236,
  957: 237,
  958: 238,
  959: 239,
  960: 240,
  961: 241,
  962: 242,
  963: 243,
  964: 244,
  965: 245,
  966: 246,
  967: 247,
  968: 248,
  969: 249,
  970: 250,
  971: 251,
  972: 252,
  973: 253,
  974: 254,
};

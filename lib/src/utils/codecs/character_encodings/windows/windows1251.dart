import 'dart:convert' as dart_convert;

import 'windows.dart';

/// Provides a windows 1251 / cp1251 codec for easy encoding and decoding.
class Windows1251Codec extends dart_convert.Encoding {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Windows1251Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Windows1251Decoder get decoder => allowInvalid
      ? const Windows1251Decoder(allowInvalid: true)
      : const Windows1251Decoder(allowInvalid: false);

  @override
  Windows1251Encoder get encoder => allowInvalid
      ? const Windows1251Encoder(allowInvalid: true)
      : const Windows1251Encoder(allowInvalid: false);

  @override
  String get name => 'windows-1251';
}

/// Decodes windows 1251 / cp1251 data.
class Windows1251Decoder extends WindowsDecoder {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Windows1251Decoder({
    bool allowInvalid = false,
  }) : super(_cp1251Symbols, allowInvalid: allowInvalid);
}

/// Encodes texts into windows 1251 data
class Windows1251Encoder extends WindowsEncoder {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Windows1251Encoder({
    bool allowInvalid = false,
  }) : super(_cp1251Map, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _cp1251Symbols =
// ignore: lines_longer_than_80_chars
    'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—?™љ›њќћџ\u{00A0}ЎўЈ¤Ґ¦§Ё©Є«¬\u{00AD}®Ї°±Ііґµ¶·ё№є»јЅѕїАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя';
const Map<int, int> _cp1251Map = {
  1026: 128,
  1027: 129,
  8218: 130,
  1107: 131,
  8222: 132,
  8230: 133,
  8224: 134,
  8225: 135,
  8364: 136,
  8240: 137,
  1033: 138,
  8249: 139,
  1034: 140,
  1036: 141,
  1035: 142,
  1039: 143,
  1106: 144,
  8216: 145,
  8217: 146,
  8220: 147,
  8221: 148,
  8226: 149,
  8211: 150,
  8212: 151,
  8482: 153,
  1113: 154,
  8250: 155,
  1114: 156,
  1116: 157,
  1115: 158,
  1119: 159,
  160: 160,
  1038: 161,
  1118: 162,
  1032: 163,
  164: 164,
  1168: 165,
  166: 166,
  167: 167,
  1025: 168,
  169: 169,
  1028: 170,
  171: 171,
  172: 172,
  173: 173,
  174: 174,
  1031: 175,
  176: 176,
  177: 177,
  1030: 178,
  1110: 179,
  1169: 180,
  181: 181,
  182: 182,
  183: 183,
  1105: 184,
  8470: 185,
  1108: 186,
  187: 187,
  1112: 188,
  1029: 189,
  1109: 190,
  1111: 191,
  1040: 192,
  1041: 193,
  1042: 194,
  1043: 195,
  1044: 196,
  1045: 197,
  1046: 198,
  1047: 199,
  1048: 200,
  1049: 201,
  1050: 202,
  1051: 203,
  1052: 204,
  1053: 205,
  1054: 206,
  1055: 207,
  1056: 208,
  1057: 209,
  1058: 210,
  1059: 211,
  1060: 212,
  1061: 213,
  1062: 214,
  1063: 215,
  1064: 216,
  1065: 217,
  1066: 218,
  1067: 219,
  1068: 220,
  1069: 221,
  1070: 222,
  1071: 223,
  1072: 224,
  1073: 225,
  1074: 226,
  1075: 227,
  1076: 228,
  1077: 229,
  1078: 230,
  1079: 231,
  1080: 232,
  1081: 233,
  1082: 234,
  1083: 235,
  1084: 236,
  1085: 237,
  1086: 238,
  1087: 239,
  1088: 240,
  1089: 241,
  1090: 242,
  1091: 243,
  1092: 244,
  1093: 245,
  1094: 246,
  1095: 247,
  1096: 248,
  1097: 249,
  1098: 250,
  1099: 251,
  1100: 252,
  1101: 253,
  1102: 254,
  1103: 255,
};

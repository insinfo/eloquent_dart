import 'dart:convert' as dart_convert;

import 'windows.dart';

/// Provides a windows 1256 / cp1256 codec for easy encoding and decoding.
class Windows1256Codec extends dart_convert.Encoding {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Windows1256Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Windows1256Decoder get decoder => allowInvalid
      ? const Windows1256Decoder(allowInvalid: true)
      : const Windows1256Decoder(allowInvalid: false);

  @override
  Windows1256Encoder get encoder => allowInvalid
      ? const Windows1256Encoder(allowInvalid: true)
      : const Windows1256Encoder(allowInvalid: false);

  @override
  String get name => 'windows-1256';
}

/// Decodes windows 1256 / cp1256 data.
class Windows1256Decoder extends WindowsDecoder {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Windows1256Decoder({
    bool allowInvalid = false,
  }) : super(_cp1256Symbols, allowInvalid: allowInvalid);
}

/// Encodes texts into windows 1256 data
class Windows1256Encoder extends WindowsEncoder {
  /// Creates a new []
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Windows1256Encoder({
    bool allowInvalid = false,
  }) : super(_cp1256Map, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _cp1256Symbols =
// ignore: lines_longer_than_80_chars
    '€پ‚ƒ„…†‡ˆ‰ٹ‹Œچژڈگ‘’“”•–—ک™ڑ›œ?‍ں\u{00A0}،¢£¤¥¦§¨©ھ«¬\u{00AD}®¯°±²³´µ¶·¸¹؛»¼½¾؟ہءآأؤإئابةتثجحخدذرزسشصض×طظعغـفقكàلâمنهوçèéêëىيîïًٌٍَôُِ÷ّùْûü‎‏ے';
const Map<int, int> _cp1256Map = {
  8364: 128,
  1662: 129,
  8218: 130,
  402: 131,
  8222: 132,
  8230: 133,
  8224: 134,
  8225: 135,
  710: 136,
  8240: 137,
  1657: 138,
  8249: 139,
  338: 140,
  1670: 141,
  1688: 142,
  1672: 143,
  1711: 144,
  8216: 145,
  8217: 146,
  8220: 147,
  8221: 148,
  8226: 149,
  8211: 150,
  8212: 151,
  1705: 152,
  8482: 153,
  1681: 154,
  8250: 155,
  339: 156,
  8204: 157,
  8205: 158,
  1722: 159,
  160: 160,
  1548: 161,
  162: 162,
  163: 163,
  164: 164,
  165: 165,
  166: 166,
  167: 167,
  168: 168,
  169: 169,
  1726: 170,
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
  1563: 186,
  187: 187,
  188: 188,
  189: 189,
  190: 190,
  1567: 191,
  1729: 192,
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
  215: 215,
  1591: 216,
  1592: 217,
  1593: 218,
  1594: 219,
  1600: 220,
  1601: 221,
  1602: 222,
  1603: 223,
  224: 224,
  1604: 225,
  226: 226,
  1605: 227,
  1606: 228,
  1607: 229,
  1608: 230,
  231: 231,
  232: 232,
  233: 233,
  234: 234,
  235: 235,
  1609: 236,
  1740: 237,
  1610: 237,
  238: 238,
  239: 239,
  1611: 240,
  1612: 241,
  1613: 242,
  1614: 243,
  244: 244,
  1615: 245,
  1616: 246,
  247: 247,
  1617: 248,
  249: 249,
  1618: 250,
  251: 251,
  252: 252,
  8206: 253,
  8207: 254,
  1746: 255,
};

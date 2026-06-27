import 'dart:convert' as dart_convert;

import 'dos.dart';

/// Provides a DOS-Latin1 / cp850 codec for easy encoding and decoding.
///
/// https://en.wikipedia.org/wiki/Code_page_850
class CodePage850Codec extends dart_convert.Encoding {
  /// Creates a new [CodePage850Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const CodePage850Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  CodePage850Decoder get decoder => allowInvalid
      ? const CodePage850Decoder(allowInvalid: true)
      : const CodePage850Decoder(allowInvalid: false);

  @override
  CodePage850Encoder get encoder => allowInvalid
      ? const CodePage850Encoder(allowInvalid: true)
      : const CodePage850Encoder(allowInvalid: false);

  @override
  String get name => 'cp-850';
}

/// Decodes windows 1250 / cp1250 data.
class CodePage850Decoder extends DosCodePageDecoder {
  /// Creates a new [CodePage850Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed, it will be decoded to �
  const CodePage850Decoder({
    bool allowInvalid = false,
  }) : super(
          _cp850Symbols,
          allowInvalid: allowInvalid,
        );
}

/// Encodes texts into cp-850 / DOS-Latin-1 data
class CodePage850Encoder extends DosCodePageEncoder {
  /// Creates a new [CodePage850Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed, it will be encoded to ?
  const CodePage850Encoder({
    bool allowInvalid = false,
  }) : super(_cp850Map, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _cp850Symbols =
// ignore: lines_longer_than_80_chars
    '⌂ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑªº¿®¬½¼¡«»░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐└┴┬├─┼ãÃ╚╔╩╦╠═╬¤ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀ÓßÔÒõÕµþÞÚÛÙýÝ¯´\u{00AD}±‗¾¶§÷¸°¨·¹³²■\u{00A0}';

const Map<int, int> _cp850Map = {
  // start block:
  9786: 1,
  9787: 2,
  9829: 3,
  9830: 4,
  9827: 5,
  9824: 6,
  8226: 7,
  9688: 8,
  9675: 9,
  9689: 10,
  9794: 11,
  9792: 12,
  9834: 13,
  9835: 14,
  9788: 15,
  9658: 16,
  9668: 17,
  8597: 18,
  8252: 19,
  // 182: 20,
  // 167: 21,
  9644: 22,
  8616: 23,
  8593: 24,
  8595: 25,
  8594: 26,
  8592: 27,
  8735: 28,
  8596: 29,
  9650: 30,
  9660: 31,
  // upper area:
  8962: 127,
  199: 128,
  252: 129,
  233: 130,
  226: 131,
  228: 132,
  224: 133,
  229: 134,
  231: 135,
  234: 136,
  235: 137,
  232: 138,
  239: 139,
  238: 140,
  236: 141,
  196: 142,
  197: 143,
  201: 144,
  230: 145,
  198: 146,
  244: 147,
  246: 148,
  242: 149,
  251: 150,
  249: 151,
  255: 152,
  214: 153,
  220: 154,
  248: 155,
  163: 156,
  216: 157,
  215: 158,
  402: 159,
  225: 160,
  237: 161,
  243: 162,
  250: 163,
  241: 164,
  209: 165,
  170: 166,
  186: 167,
  191: 168,
  174: 169,
  172: 170,
  189: 171,
  188: 172,
  161: 173,
  171: 174,
  187: 175,
  9617: 176,
  9618: 177,
  9619: 178,
  9474: 179,
  9508: 180,
  193: 181,
  194: 182,
  192: 183,
  169: 184,
  9571: 185,
  9553: 186,
  9559: 187,
  9565: 188,
  162: 189,
  165: 190,
  9488: 191,
  9492: 192,
  9524: 193,
  9516: 194,
  9500: 195,
  9472: 196,
  9532: 197,
  227: 198,
  195: 199,
  9562: 200,
  9556: 201,
  9577: 202,
  9574: 203,
  9568: 204,
  9552: 205,
  9580: 206,
  164: 207,
  240: 208,
  208: 209,
  202: 210,
  203: 211,
  200: 212,
  305: 213,
  205: 214,
  206: 215,
  207: 216,
  9496: 217,
  9484: 218,
  9608: 219,
  9604: 220,
  166: 221,
  204: 222,
  9600: 223,
  211: 224,
  223: 225,
  212: 226,
  210: 227,
  245: 228,
  213: 229,
  181: 230,
  254: 231,
  222: 232,
  218: 233,
  219: 234,
  217: 235,
  253: 236,
  221: 237,
  175: 238,
  180: 239,
  173: 240,
  177: 241,
  8215: 242,
  190: 243,
  182: 244,
  167: 245,
  247: 246,
  184: 247,
  176: 248,
  168: 249,
  183: 250,
  185: 251,
  179: 252,
  178: 253,
  9632: 254,
  160: 255,
};

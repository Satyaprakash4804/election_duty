// encoding_helper.dart
//
// Dart port of encodingHelper.js
// Handles:
//   1. Krutidev  → Unicode  (ASCII-mapped legacy Hindi font)
//   2. Windows-1252 / ANSI  → Unicode  (Mangal files saved as ANSI)
//   3. UTF-8 with BOM       (normal Unicode files)
//
// No external packages required — pure Dart.

// ── Full Krutidev → Unicode map ───────────────────────────────────────────────
// Order matters: longer / more-specific keys must come FIRST (greedy match).
const List<List<String>> kdMap = [
  // ── Matras / vowel signs ──
  ['kZ', 'ार्'], ['kj', 'ारज'],
  ['k+', 'ा़'],
  ['+', '़'],
  ['aa', 'आ'],
  ['vkS', 'औ'], ['vks', 'ओ'], ['vk', 'आ'],
  ['vS', 'ऐ'], ['v,', 'अए'],
  ['v©', 'औ'], ['v¨', 'ओ'],
  ['v', 'अ'],
  ['b±', 'ईं'], ['bZ', 'ई'], ['b', 'इ'],
  ['Å', 'ऊ'], ['m', 'उ'],
  [',s', 'ऐ'], [',', 'ए'],
  ['_', 'ऋ'],

  // ── Consonants (two-char combos first) ──
  ['D[k', 'क्ख'],
  ['[k', 'ख'], ['?k', 'घ'], ['Nk', 'छ'], ['>k', 'झ'],
  ['Bk', 'ठ'], ['<k', 'ढ'], ['Fk', 'थ'], ['Hk', 'भ'],
  ['"k', 'श'],
  ['Kk', 'ज्ञ'], ['K', 'ज्ञ'],
  ['Øk', 'क्रा'], ['Ø', 'क्र'],
  ['«', 'ट्र'], ['º', 'ह्'],
  ['Dr', 'क्त'], ['dk', 'का'],

  // ── Basic consonants ──
  ['d', 'क'], ['[', 'ख'], ['x', 'ग'], ['?', 'घ'], ['³', 'ङ'],
  ['p', 'च'], ['N', 'छ'], ['t', 'ज'], ['>', 'झ'], ['´', 'ञ'],
  ['V', 'ट'], ['B', 'ठ'], ['M', 'ड'], ['<', 'ढ'], [r'\.', 'ण'],
  ['r', 'त'], ['F', 'थ'], ['n', 'द'],
  ['/', 'ध'], ['u', 'न'],
  ['i', 'प'], ['Q', 'फ'], ['c', 'ब'], ['H', 'भ'], ['e', 'म'],
  ['y', 'ल'], ['G', 'ळ'],
  ['o', 'व'], ['"', 'श'], ["'k", 'श'], [';', 'य'],
  ['j', 'र'], ["'", 'ष'], ['l', 'स'], ['g', 'ह'],
  ['{k', 'क्ष'], ['{', 'क्ष'],
  ['=', 'त्र'],

  // ── Matras (vowel signs attached to consonants) ──
  ['k', 'ा'], ['f', 'ि'], ['h', 'ी'],
  ['q', 'ु'], ['w', 'ू'],
  ['s', 'े'], ['S', 'ै'],
  ['ks', 'ो'], ['kS', 'ौ'],
  ['a', 'ं'], ['°', 'ँ'], ['%', 'ः'],
  ['~', '्'], ['Z', 'र्'], ['z', '्र'],

  // ── Special / misc ──
  ['M+', 'ड़'], ['<+', 'ढ़'],
  ['j+', 'ऱ'],
  ['Á', 'प्र'], ['iz', 'प्र'],
  ['ç', 'प्र'],
  ['æ', 'द्र'],
  ['ï', 'ज्'],
  ['ô', 'ष्'],
  ['·', '।'], ['&', '-'],

  // ── Digits (Devanagari) ──
  ['0', '०'], ['1', '१'], ['2', '२'], ['3', '३'], ['4', '४'],
  ['5', '५'], ['6', '६'], ['7', '७'], ['8', '८'], ['9', '९'],
];

// ── Windows-1252 → Unicode code-point map ────────────────────────────────────
const Map<int, int> _win1252Extras = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
  0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
  0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
  0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
  0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
  0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
};

// ── 1. Krutidev → Unicode ─────────────────────────────────────────────────────
String krutidevToUnicode(String str) {
  String out = str;
  for (final pair in kdMap) {
    out = out.replaceAll(pair[0], pair[1]);
  }
  return out;
}

bool isKrutidev(String text) {
  if (text.length < 2) return false;
  final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(text);
  if (hasDevanagari) return false;
  final krutidevPattern = RegExp(r'[vkbZmÅ,tslgdjrniepQcHkyoVMBNFG{K]');
  return krutidevPattern.hasMatch(text);
}

String normalizeCell(dynamic val) {
  final str = (val ?? '').toString().trim();
  if (str.isEmpty) return str;
  if (isKrutidev(str)) return krutidevToUnicode(str);
  return str;
}

// ── 2. Decode raw bytes → String ─────────────────────────────────────────────
String decodeCsvBytes(List<int> bytes) {
  try {
    final result = _decodeUtf8Strict(bytes);
    return result.startsWith('\uFEFF') ? result.substring(1) : result;
  } catch (_) {
    final result = _decodeWindows1252(bytes);
    return result.startsWith('\uFEFF') ? result.substring(1) : result;
  }
}

String _decodeUtf8Strict(List<int> bytes) {
  final buf = StringBuffer();
  int i = 0;
  while (i < bytes.length) {
    final b = bytes[i] & 0xFF;
    if (b < 0x80) {
      buf.writeCharCode(b);
      i++;
    } else if (b < 0xC2) {
      throw FormatException('Invalid UTF-8 byte 0x${b.toRadixString(16)} at $i');
    } else if (b < 0xE0) {
      _assertContinuation(bytes, i + 1);
      final cp = ((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
      buf.writeCharCode(cp);
      i += 2;
    } else if (b < 0xF0) {
      _assertContinuation(bytes, i + 1);
      _assertContinuation(bytes, i + 2);
      final cp = ((b & 0x0F) << 12) |
          ((bytes[i + 1] & 0x3F) << 6) |
          (bytes[i + 2] & 0x3F);
      buf.writeCharCode(cp);
      i += 3;
    } else if (b < 0xF8) {
      _assertContinuation(bytes, i + 1);
      _assertContinuation(bytes, i + 2);
      _assertContinuation(bytes, i + 3);
      final cp = ((b & 0x07) << 18) |
          ((bytes[i + 1] & 0x3F) << 12) |
          ((bytes[i + 2] & 0x3F) << 6) |
          (bytes[i + 3] & 0x3F);
      buf.writeCharCode(cp);
      i += 4;
    } else {
      throw FormatException('Invalid UTF-8 byte 0x${b.toRadixString(16)} at $i');
    }
  }
  return buf.toString();
}

void _assertContinuation(List<int> bytes, int idx) {
  if (idx >= bytes.length) {
    throw FormatException('Unexpected end of UTF-8 sequence at $idx');
  }
  final b = bytes[idx] & 0xFF;
  if ((b & 0xC0) != 0x80) {
    throw FormatException('Invalid continuation byte 0x${b.toRadixString(16)} at $idx');
  }
}

String _decodeWindows1252(List<int> bytes) {
  final buf = StringBuffer();
  for (final raw in bytes) {
    final b = raw & 0xFF;
    if (_win1252Extras.containsKey(b)) {
      buf.writeCharCode(_win1252Extras[b]!);
    } else {
      buf.writeCharCode(b);
    }
  }
  return buf.toString();
}
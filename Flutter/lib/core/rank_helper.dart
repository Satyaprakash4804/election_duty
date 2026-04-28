// rank_helper.dart
//
// Rank normalization: converts any rank input
//   (Hindi/Mangal Unicode, Krutidev, English, abbreviation, mixed)
// into a canonical English value that matches the rank filter chips.
//
// Canonical values used across the app:
//   SP, ASP, DSP, Inspector, SI, ASI, Head Constable, Constable
//
// Pure Dart, no external deps. Works alongside encoding_helper.dart —
// callers should run normalizeCell() FIRST (Krutidev → Unicode), then
// pass the result here.

import 'encoding_helper.dart';

// ── Canonical rank list (must match _kAllRanks in staff_page.dart) ──────────
const List<String> kCanonicalRanks = [
  'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable',
];

// ── Alias table ────────────────────────────────────────────────────────────
//
// Each entry maps a SET of aliases → canonical English value.
// Aliases are matched case-insensitively after stripping punctuation.
// Hindi entries use Devanagari Unicode (Mangal); Krutidev input is converted
// to Unicode by the caller via normalizeCell() before lookup.
//
// IMPORTANT: order matters for substring matching — more specific patterns
// (longer Hindi phrases, "Head Constable" before "Constable", "Sub Inspector"
// before "Inspector") MUST come first.

class _RankAlias {
  final String canonical;
  final List<String> aliases;
  const _RankAlias(this.canonical, this.aliases);
}

const List<_RankAlias> _kAliases = [
  // ── SP — Superintendent of Police ──
  _RankAlias('SP', [
    'sp', 's.p.', 's.p',
    'superintendent of police', 'superintendent',
    'पुलिस अधीक्षक', 'अधीक्षक', 'एसपी', 'एस.पी.', 'एस पी',
  ]),

  // ── ASP — Additional / Assistant SP ──
  _RankAlias('ASP', [
    'asp', 'a.s.p.', 'a.s.p',
    'additional sp', 'additional superintendent',
    'assistant superintendent of police', 'assistant superintendent',
    'अपर पुलिस अधीक्षक', 'अपर अधीक्षक',
    'सहायक पुलिस अधीक्षक', 'सहायक अधीक्षक',
    'एएसपी', 'ए.एस.पी.', 'ए एस पी',
  ]),

  // ── DSP — Deputy SP ──
  _RankAlias('DSP', [
    'dsp', 'd.s.p.', 'd.s.p',
    'dy.sp', 'dy sp', 'dy. sp', 'dy.s.p.',
    'deputy superintendent of police', 'deputy superintendent', 'deputy sp',
    'उप पुलिस अधीक्षक', 'उप अधीक्षक',
    'डीएसपी', 'डी.एस.पी.', 'डी एस पी',
    'सी.ओ.', 'सीओ', 'co', 'c.o.', 'circle officer',
  ]),

  // ── Inspector ──
  _RankAlias('Inspector', [
    'inspector', 'insp', 'insp.', 'ins', 'ins.',
    'ti', 't.i.', 'station officer', 's.o.', 'so',
    'station house officer', 'sho', 's.h.o.',
    'निरीक्षक', 'इंस्पेक्टर', 'प्रभारी निरीक्षक', 'प्रभारी',
    'थानाध्यक्ष',
  ]),

  // ── SI — Sub Inspector ──
  _RankAlias('SI', [
    'si', 's.i.', 's.i',
    'sub inspector', 'sub-inspector', 'sub.inspector',
    'sub insp', 'sub insp.', 'sub-insp',
    'उप निरीक्षक', 'उप-निरीक्षक',
    'दरोगा', 'थानेदार',
    'एसआई', 'एस.आई.', 'एस आई',
  ]),

  // ── ASI — Assistant Sub Inspector ──
  _RankAlias('ASI', [
    'asi', 'a.s.i.', 'a.s.i',
    'assistant sub inspector', 'assistant sub-inspector',
    'asst sub inspector', 'asst. sub inspector', 'asst.si', 'asst si',
    'सहायक उप निरीक्षक', 'सहायक उप-निरीक्षक', 'सहायक निरीक्षक',
    'एएसआई', 'ए.एस.आई.', 'ए एस आई',
  ]),

  // ── Head Constable ──
  _RankAlias('Head Constable', [
    'head constable', 'head-constable', 'headconstable',
    'hc', 'h.c.', 'h.c', 'h/c',
    'head ct', 'head ct.', 'head-ct',
    'मुख्य आरक्षी', 'मुख्य-आरक्षी', 'मुख्य सिपाही',
    'हेड कांस्टेबल', 'हेड-कांस्टेबल', 'हेड कांस्‍टेबल',
    'हे.का.', 'हेका', 'हे का',
  ]),

  // ── Constable ──
  _RankAlias('Constable', [
    'constable', 'const', 'const.', 'ct', 'ct.', 'c.t.',
    'police constable', 'pc', 'p.c.',
    'आरक्षी', 'सिपाही', 'कांस्टेबल', 'कान्स्टेबल', 'कांस्‍टेबल',
    'का.', 'का',
  ]),
];

// ── Punctuation stripper for matching ───────────────────────────────────────
//
// Removes:
//   • ASCII punctuation: . - _ / ()
//   • Devanagari danda + double danda
//   • Multiple whitespace → single space
final RegExp _kStripPunct = RegExp(r"[.\-_/(),।॥']");
final RegExp _kCollapseWs = RegExp(r'\s+');

String _normalizeForMatch(String s) {
  var out = s.toLowerCase().trim();
  out = out.replaceAll(_kStripPunct, ' ');
  out = out.replaceAll(_kCollapseWs, ' ').trim();
  return out;
}

// Pre-built alias map for O(1) exact-match lookup
final Map<String, String> _kExactMap = (() {
  final m = <String, String>{};
  for (final entry in _kAliases) {
    for (final a in entry.aliases) {
      m[_normalizeForMatch(a)] = entry.canonical;
    }
    // Canonical also maps to itself (case-insensitive)
    m[_normalizeForMatch(entry.canonical)] = entry.canonical;
  }
  return m;
})();

// Pre-built sorted substring list for fallback matching.
// Sorted by alias length DESC so longest/most-specific match wins
// (critical: "sub inspector" must beat "inspector", "head constable"
// must beat "constable").
final List<MapEntry<String, String>> _kSubstrList = (() {
  final list = <MapEntry<String, String>>[];
  for (final entry in _kAliases) {
    for (final a in entry.aliases) {
      final ak = _normalizeForMatch(a);
      if (ak.isNotEmpty) {
        list.add(MapEntry(ak, entry.canonical));
      }
    }
  }
  list.sort((a, b) => b.key.length.compareTo(a.key.length));
  return list;
})();

// ── Public API ──────────────────────────────────────────────────────────────

/// Converts any rank value (Hindi/Mangal/Krutidev/English/abbrev) to its
/// canonical English form. Returns the input trimmed if no match is found.
///
/// Usage flow:
///   1. CSV/Excel cell → normalizeCell() (Krutidev → Unicode)
///   2. → normalizeRank() (any-language → canonical English)
///
/// Examples:
///   normalizeRank('आरक्षी')          → 'Constable'
///   normalizeRank('मुख्य आरक्षी')      → 'Head Constable'
///   normalizeRank('उप निरीक्षक')      → 'SI'
///   normalizeRank('S.I.')           → 'SI'
///   normalizeRank('Sub Inspector')  → 'SI'
///   normalizeRank('Const.')         → 'Constable'
///   normalizeRank('Head Ct')        → 'Head Constable'
///   normalizeRank('niljh{kd')       → 'Inspector'  (Krutidev "निरीक्षक")
///   normalizeRank('Driver')         → 'Driver'    (passthrough — no alias)
String normalizeRank(dynamic input) {
  if (input == null) return '';
  // Step 1: convert dynamic value → trimmed string with Krutidev handled
  final raw = normalizeCell(input);
  if (raw.isEmpty) return '';

  // Step 2: build matching key
  final key = _normalizeForMatch(raw);
  if (key.isEmpty) return '';

  // Step 3: exact-match lookup
  final exact = _kExactMap[key];
  if (exact != null) return exact;

  // Step 4: substring fallback — useful for cell values that include
  // extra text e.g. "उप निरीक्षक (LIU)", "Constable - GD", "HC Driver".
  // We iterate _kSubstrList sorted by alias length DESC so the most
  // specific match wins ("sub inspector" beats "inspector",
  // "head constable" beats "constable").
  for (final entry in _kSubstrList) {
    final ak = entry.key;
    if (key == ak ||
        key.startsWith('$ak ') ||
        key.endsWith(' $ak') ||
        key.contains(' $ak ')) {
      return entry.value;
    }
  }

  // Step 5: nothing matched — return the cleaned-up original.
  // We return the trimmed Unicode form (not the lowercased key)
  // so capitalization/script is preserved for unknown ranks.
  return raw;
}

/// Returns true if [value] resolves to a known canonical rank.
bool isKnownRank(dynamic value) {
  final c = normalizeRank(value);
  return kCanonicalRanks.contains(c);
}

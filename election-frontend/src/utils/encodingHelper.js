// ── encodingHelper.js ─────────────────────────────────────────────────────────
// No external packages needed. Handles:
//   1. Krutidev  → Unicode (ASCII-mapped legacy Hindi font)
//   2. Windows-1252 / ANSI → Unicode (Mangal files saved as ANSI)
//   3. UTF-8 with BOM (normal Unicode files)
// ─────────────────────────────────────────────────────────────────────────────

// ── Full Krutidev → Unicode map (sorted longest-key-first for greedy match) ──
const KD_MAP = [
  // ── Matras / vowel signs ──
  ['kZ', 'ार्'],  ['kj', 'ारज'],
  ['k+', 'ा़'],
  ['+', '़'],
  ['aa', 'आ'],
  ['vkS', 'औ'],  ['vks', 'ओ'],  ['vk', 'आ'],
  ['vS', 'ऐ'],  ['v,', 'अए'],
  ['v©', 'औ'],  ['v¨', 'ओ'],
  ['v', 'अ'],
  ['b±', 'ईं'],  ['bZ', 'ई'],  ['b', 'इ'],
  ['Å', 'ऊ'],  ['m', 'उ'],
  [',s', 'ऐ'],  [',', 'ए'],
  ['_', 'ऋ'],

  // ── Consonants (two-char combos first) ──
  ['D[k', 'क्ख'],
  ['[k', 'ख'],  ['?k', 'घ'],  ['Nk', 'छ'],  ['>k', 'झ'],
  ['Bk', 'ठ'],  ['<k', 'ढ'],  ['Fk', 'थ'],  ['Hk', 'भ'],
  ['\"k', 'श'], ['\"k', 'श'],
  ['Kk', 'ज्ञ'], ['K', 'ज्ञ'],
  ['Øk', 'क्रा'], ['Ø', 'क्र'],
  ['«', 'ट्र'],  ['º', 'ह्'],
  ['Dr', 'क्त'],  ['dk', 'का'],

  // ── Basic consonants ──
  ['d', 'क'],  ['[', 'ख'],  ['x', 'ग'],  ['?', 'घ'],  ['³', 'ङ'],
  ['p', 'च'],  ['N', 'छ'],  ['t', 'ज'],  ['>', 'झ'],  ['´', 'ञ'],
  ['V', 'ट'],  ['B', 'ठ'],  ['M', 'ड'],  ['<', 'ढ'],  ['\.', 'ण'],
  ['r', 'त'],  ['F', 'थ'],  ['n', 'द'],  ['?k','घ'],
  ['/', 'ध'],  ['u', 'न'],
  ['i', 'प'],  ['Q', 'फ'],  ['c', 'ब'],  ['H', 'भ'],  ['e', 'म'],
  ['y', 'ल'],  ['G', 'ळ'],
  ['o', 'व'],  ['\"', 'श'],  ['\'k', 'श'], [';', 'य'],
  ['j', 'र'],  ['\'', 'ष'],  ['l', 'स'],  ['g', 'ह'],
  ['{k', 'क्ष'], ['{', 'क्ष'],
  ['=', 'त्र'],

  // ── Matras (vowel signs attached to consonants) ──
  ['k', 'ा'],   ['f', 'ि'],   ['h', 'ी'],
  ['q', 'ु'],   ['w', 'ू'],
  ['s', 'े'],   ['S', 'ै'],
  ['ks', 'ो'],  ['kS', 'ौ'],
  ['a', 'ं'],   ['°', 'ँ'],  ['%', 'ः'],
  ['~', '्'],   ['Z', 'र्'],  ['z', '्र'],

  // ── Special / misc ──
  ['M+', 'ड़'],  ['<+', 'ढ़'],
  ['j+', 'ऱ'],
  ['Á', 'प्र'],  ['iz', 'प्र'],
  ['ç', 'प्र'],
  ['æ', 'द्र'],
  ['ï', 'ज्'],
  ['ô', 'ष्'],
  ['·', '।'],   ['&', '-'],
  ['Ø', 'क्र'],

  // ── Digits (Devanagari) ──
  ['0', '०'],  ['1', '१'],  ['2', '२'],  ['3', '३'],  ['4', '४'],
  ['5', '५'],  ['6', '६'],  ['7', '७'],  ['8', '८'],  ['9', '९'],
];

// ── Convert Krutidev string → Unicode ────────────────────────────────────────
export function krutidevToUnicode(str) {
  let out = str;
  for (const [from, to] of KD_MAP) {
    // replace all occurrences
    out = out.split(from).join(to);
  }
  return out;
}

// ── Detect if a string is likely Krutidev (no real Devanagari, has ASCII Hindi patterns) ──
export function isKrutidev(text) {
  if (!text || text.length < 2) return false;
  const hasDevanagari = /[\u0900-\u097F]/.test(text);
  if (hasDevanagari) return false; // already Unicode
  // Krutidev strings typically contain these ASCII chars used as Hindi glyphs
  const krutidevPattern = /[vkbZmÅ,tslgdjrniepQcHkyoVMBNFG{K]/;
  return krutidevPattern.test(text);
}

// ── Normalize a single cell value ────────────────────────────────────────────
export function normalizeCell(val) {
  const str = String(val ?? '').trim();
  if (!str) return str;
  if (isKrutidev(str)) return krutidevToUnicode(str);
  return str;
}

// ── Decode CSV bytes — handles UTF-8, UTF-8 BOM, and Windows-1252 (Mangal ANSI) ──
export function decodeCsvBytes(bytes) {
  try {
    // strict UTF-8 — throws if bytes are invalid UTF-8
    return new TextDecoder('utf-8', { fatal: true })
      .decode(new Uint8Array(bytes))
      .replace(/^\uFEFF/, ''); // strip BOM
  } catch {
    // fallback: Windows-1252 — used by Mangal/ANSI saved Excel/CSV files
    return new TextDecoder('windows-1252')
      .decode(new Uint8Array(bytes))
      .replace(/^\uFEFF/, '');
  }
}
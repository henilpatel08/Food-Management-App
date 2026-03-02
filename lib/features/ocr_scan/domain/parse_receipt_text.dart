// lib/features/ocr_scan/domain/parse_receipt_text.dart
//
// Store-agnostic receipt parser.
//
// Pipeline
// 1) Normalize OCR lines.
// 2) Find the dynamic "items block" using price/qty density (no store rules).
// 3) Collapse continuation fragments onto the previous item line (e.g. "@ $/kg",
//    "/kg", or a bare "0.165 kg").
// 4) Extract {name, qty, unit} and merge duplicates.
//
// Output rows match your ParsedRow model.

import 'dart:math';
import 'parsed_row.dart';

// ------------------------------- Regexes -------------------------------------

// Trailing price like: "... 2.99", "... $2.99", "... 1,234.56", "... 2.99 C"
final RegExp _priceTailRe = RegExp(
  r'(?:[$£€]\s*)?\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\s*(?:[A-Z]{1,3})?$',
);

// Any price occurrence (for density scoring as well)
final RegExp _priceAnyRe = RegExp(
  r'(?<!\w)(?:[$£€]\s*)?\d{1,3}(?:[.,]\d{3})*[.,]\d{2}(?!\w)',
);

// Inline qty+unit: "1.5 kg", "2 pcs", "3 pk", "12 ct"
final RegExp _unitInlineRe = RegExp(
  r'(?<![A-Za-z0-9])(\d+(?:[.,]\d+)?)[ ]*(kg|g|lb|oz|l|ml|pcs?|pack|pk|dozen|dz|bag|ct|count)\b',
  caseSensitive: false,
);

// Multipliers: "2 x", "x 2", "2 pcs", "3 pk"
final RegExp _xQtyRe = RegExp(
  r'\b(\d+)\s*(?:x|pcs?|pack|pk|ct|count)\b',
  caseSensitive: false,
);

// Bare qty+unit line (continuation): "0.165 kg", "2 lb"
final RegExp _bareQtyUnitLineRe = RegExp(
  r'^\s*(\d+(?:[.,]\d+)?)[ ]*(kg|g|lb|oz|l|ml)\s*$',
  caseSensitive: false,
);

// Continuation line fragments we should attach to previous item
final RegExp _atStartRe = RegExp(r'^\s*@'); // "@ $/lb"
final RegExp _perWeightRe = RegExp(r'/\s*(?:kg|lb)\b', caseSensitive: false);

// Footer / totals boundary
final RegExp _totalLikeRe = RegExp(
  r'^\s*(sub[-\s]?total|total|tender|change|balance|amount\s+due|grand\s+total|tax|gst|pst|hst|vat)\b',
  caseSensitive: false,
);

// Obvious noise (headers, loyalty, payments, separators, addresses, etc.)
final List<RegExp> _noise = <RegExp>[
  RegExp(r'^\s*([*=\-–—_]{3,})\s*$'),
  RegExp(r'^\s*(you\s+saved|points\s+earned|loyalty|savings|coupon|discount)\b',
      caseSensitive: false),
  RegExp(r'^\s*(payment|debit|credit|visa|mastercard|amex|cash)\b',
      caseSensitive: false),
  RegExp(r'^\s*(served\s+by|clerk|cashier|operator|member\s*card)\b',
      caseSensitive: false),
  RegExp(r'\(\d{3}\)\s*\d{3}[-\s]\d{4}'), // (905) 793-4867
  RegExp(r'\b\d{3}[-\s]\d{3}[-\s]\d{4}\b'), // 555-555-5555
  RegExp(r'\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b'), // Canadian postal code
  RegExp(r'\b\d{5}(?:-\d{4})?\b'), // US ZIP
  RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'), // dates
  RegExp(r'\border\s*#?\s*\w+\b', caseSensitive: false),
  RegExp(r'\b(invoice|receipt)\s*#?\s*\w+\b', caseSensitive: false),
  RegExp(r'\b(st|street|ave|avenue|rd|road|blvd|drive|dr|unit|suite)\b',
      caseSensitive: false),
];

// ----------------------------- Small helpers ---------------------------------

String _tidy(String s) {
  var out = s.trim();
  out = out.replaceAll(RegExp(r'[–—]+'), '-');
  out = out.replaceAll(RegExp(r'\s+'), ' ');
  return out;
}

bool _hasLetters(String s) => RegExp(r'[A-Za-z]').hasMatch(s);
bool _hasPriceAny(String s) => _priceAnyRe.hasMatch(s);
bool _hasPriceTail(String s) => _priceTailRe.hasMatch(s);
bool _hasInlineQty(String s) => _unitInlineRe.hasMatch(s) || _xQtyRe.hasMatch(s);
bool _isTotalLike(String s) => _totalLikeRe.hasMatch(s);

bool _isNoiseLine(String s) {
  if (s.isEmpty) return true;
  for (final r in _noise) {
    if (r.hasMatch(s)) return true;
  }
  return false;
}

// Keepers for candidate "itemish" lines during block finding.
bool _isCandidate(String s) {
  if (_isNoiseLine(s) || _isTotalLike(s)) return false;
  if (!_hasLetters(s)) return false;
  return _hasPriceTail(s) || _hasInlineQty(s) || _hasPriceAny(s);
}

// -------------------------- Items block detection ----------------------------

// Return the [start,end] indices (inclusive) of the dense "items" region.
// If nothing convincing is found, return the full span that excludes a tailing
// footer bounded by totals.
({int start, int end}) _findItemsBlock(List<String> lines) {
  final n = lines.length;
  if (n == 0) return (start: 0, end: -1);

  // Binary evidence per line.
  final evid = List<int>.generate(n, (i) => _isCandidate(lines[i]) ? 1 : 0);

  // Sliding window looking for a run with several candidates.
  const W = 8;
  int bestStart = 0, bestEnd = max(0, n - 1);
  double bestDensity = -1;

  int sum = 0;
  for (int i = 0; i < min(W, n); i++) {
    sum += evid[i];
  }

  for (int i = 0; i < n; i++) {
    final win = min(W, n - i);
    final density = win == 0 ? 0.0 : sum / win;
    if (density > bestDensity) {
      bestDensity = density;
      bestStart = i;
      bestEnd = i + win - 1;
    }
    if (i + W < n) sum += evid[i + W];
    if (i < n) sum -= evid[i];
  }

  // Expand forward until totals/footer.
  int end = bestEnd;
  for (int i = bestEnd + 1; i < n; i++) {
    final s = lines[i];
    if (_isTotalLike(s)) break;
    if (_isCandidate(s) || (!_isNoiseLine(s) && _hasLetters(s))) {
      end = i;
    } else {
      // break after a clear non-item
      break;
    }
  }

  // Back up start to avoid headers.
  int start = bestStart;
  for (int i = bestStart - 1; i >= 0; i--) {
    final s = lines[i];
    if (_isTotalLike(s)) {
      start = i + 1;
      break;
    }
    if (_isNoiseLine(s)) {
      start = i + 1;
      break;
    }
  }

  // Fallback: if density is poor, just take [firstCandidate .. before totals]
  if (bestDensity <= 0) {
    start = 0;
    while (start < n && !_isCandidate(lines[start])) {
      start++;
    }
    if (start >= n) return (start: 0, end: -1);
    end = n - 1;
    for (int i = start; i < n; i++) {
      if (_isTotalLike(lines[i])) {
        end = i - 1;
        break;
      }
    }
  }

  if (start > end) return (start: 0, end: -1);
  return (start: start, end: end);
}

// ----------------------- Collapse continuation lines -------------------------

List<String> _collapseContinuations(List<String> slice) {
  final out = <String>[];
  for (int i = 0; i < slice.length; i++) {
    final s = slice[i];

    // Continuations we should *attach* to the previous line.
    final isContinuation =
        _atStartRe.hasMatch(s) ||
            _perWeightRe.hasMatch(s) ||
            _bareQtyUnitLineRe.hasMatch(s);

    if (isContinuation && out.isNotEmpty) {
      out[out.length - 1] = '${out.last}  ${s.trim()}';
      continue;
    }
    out.add(s);
  }
  return out;
}

// ------------------------------ Cleaning -------------------------------------

String _stripPricesEtc(String s) {
  var out = s;

  // Remove any price tokens.
  out = out.replaceAll(RegExp(r'[$£€]\s*\d+(?:[.,]\d+)?'), '');
  out = out.replaceAll(RegExp(r'\b\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\b'), '');
  out = out.replaceAll(RegExp(r'\b\d+[.,]\d{2}\b'), '');

  // Remove "@ ...", "/kg", trailing codes like "HC", "C", "PTS"
  out = out.replaceAll(RegExp(r'\s*@\s*\S+'), '');
  out = out.replaceAll(RegExp(r'\s*/\s*(kg|lb)\b', caseSensitive: false), '');
  out = out.replaceAll(RegExp(r'\b(HC|C|F|PTS)\b', caseSensitive: false), '');

  // Defensive: phones/dates/order-like
  out = out.replaceAll(RegExp(r'\(\d{3}\)\s*\d{3}[-\s]\d{4}'), '');
  out = out.replaceAll(RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'), '');
  out = out.replaceAll(RegExp(r'\border\s*#?\s*\w+\b', caseSensitive: false), '');

  return _tidy(out);
}

String _cleanName(String s) {
  var out = s;
  out = out.replaceAll(_unitInlineRe, '');
  out = out.replaceAll(_xQtyRe, '');
  out = _stripPricesEtc(out);

  // Prevent address/heading leakage
  if (RegExp(r'\b(st|street|ave|rd|road|drive|dr|blvd|unit|suite|city|state)\b',
      caseSensitive: false)
      .hasMatch(out)) {
    return '';
  }

  out = _tidy(out);
  if (out.length <= 2 || !_hasLetters(out)) return '';
  return out;
}

ParsedRow _row(String name, {double? qty, String? unit}) {
  final q = (qty == null || qty.isNaN || qty <= 0) ? 1.0 : qty;
  final u = (unit == null || unit.isEmpty) ? 'pcs' : unit.toLowerCase();
  return ParsedRow(name: name, qty: q, unit: u);
}

// ------------------------------- Public APIs ---------------------------------

/// Robust, store-agnostic receipt parsing.
List<ParsedRow> parseReceiptText(String raw) {
  if (raw.trim().isEmpty) return const [];

  // 1) Normalize all lines
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .map(_tidy)
      .where((s) => s.isNotEmpty)
      .toList();

  // 2) Locate items block
  final block = _findItemsBlock(lines);
  if (block.end < block.start) return const [];

  // 3) Slice and collapse continuation fragments
  final collapsed = _collapseContinuations(lines.sublist(block.start, block.end + 1));

  // 4) Extract rows
  final rows = <ParsedRow>[];

  for (final s in collapsed) {
    // Skip obvious noise even inside the block
    if (_isNoiseLine(s) || _isTotalLike(s)) continue;

    // Source to read qty/unit from: prefer inline (same line)
    String src = s;

    double? qty;
    String? unit;

    final m1 = _unitInlineRe.firstMatch(src);
    if (m1 != null) {
      qty = double.tryParse(m1.group(1)!.replaceAll(',', '.'));
      unit = m1.group(2);
    } else {
      final m2 = _xQtyRe.firstMatch(src);
      if (m2 != null) {
        qty = double.tryParse(m2.group(1)!);
        unit = 'pcs';
      } else {
        // As a last resort, if the line *ends* with a bare qty-unit
        final bare = _bareQtyUnitLineRe.firstMatch(src);
        if (bare != null) {
          qty = double.tryParse(bare.group(1)!.replaceAll(',', '.'));
          unit = bare.group(2);
        }
      }
    }

    final name = _cleanName(src);
    if (name.isEmpty) continue;

    // Accept only itemish lines (letters + price/qty evidence)
    final looksItem = _hasLetters(name) &&
        (_hasInlineQty(s) || _hasPriceAny(s) || _hasPriceTail(s));
    if (!looksItem) continue;

    rows.add(_row(name, qty: qty, unit: unit));
  }

  // 5) Merge duplicates by (name|unit)
  final merged = <String, ParsedRow>{};
  for (final r in rows) {
    final key = '${r.name.toLowerCase()}|${r.unit.toLowerCase()}';
    final prev = merged[key];
    if (prev == null) {
      merged[key] = r;
    } else {
      merged[key] = _row(
        r.name,
        qty: (prev.qty + max<double>(0.0, r.qty)),
        unit: r.unit,
      );
    }
  }

  return merged.values.toList();
}

/// Notes (typed/handwritten lists). Much simpler but reuses cleaners.
List<ParsedRow> parseNoteText(String raw) {
  if (raw.trim().isEmpty) return const [];
  final parts = raw
      .split(RegExp(r'\r?\n|,|•|- '))
      .map(_tidy)
      .where((e) => e.isNotEmpty);

  final out = <ParsedRow>[];
  for (var line in parts) {
    var s = line;

    double? qty;
    String? unit;

    final u1 = _unitInlineRe.firstMatch(s);
    final u2 = _xQtyRe.firstMatch(s);

    if (u1 != null) {
      qty = double.tryParse(u1.group(1)!.replaceAll(',', '.'));
      unit = u1.group(2);
    } else if (u2 != null) {
      qty = double.tryParse(u2.group(1)!);
      unit = 'pcs';
    } else {
      // Leading number => pcs
      final lead =
      RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s+([A-Za-z].*)$').firstMatch(s);
      if (lead != null) {
        qty = double.tryParse(lead.group(1)!.replaceAll(',', '.'));
        unit = 'pcs';
        s = lead.group(2)!;
      }
    }

    final name = _cleanName(s);
    if (name.isEmpty) continue;

    out.add(_row(name, qty: qty, unit: unit));
  }
  return out;
}

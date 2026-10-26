import 'dart:ui' show TextDirection;

/// Direction of the first strongly-directional letter in [text], or null if
/// there is none (empty, digits, punctuation). Lets Arabic lyrics align and
/// edit right-to-left while Hausa/English stay left-to-right.
TextDirection? detectTextDirection(String text) {
  for (final rune in text.runes) {
    if (_isRtl(rune)) return TextDirection.rtl;
    if (_isLatin(rune)) return TextDirection.ltr;
  }
  return null;
}

bool _isRtl(int r) =>
    (r >= 0x0590 && r <= 0x08FF) ||
    (r >= 0xFB1D && r <= 0xFDFF) ||
    (r >= 0xFE70 && r <= 0xFEFF);

bool _isLatin(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F) ||
    (r >= 0x1E00 && r <= 0x1EFF);

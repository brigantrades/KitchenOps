/// Decodes HTML/XML character references often left in scraped recipe text.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  var s = input;
  for (var n = 0; n < 8; n++) {
    final next = _decodeHtmlEntitiesPass(s);
    if (next == s) break;
    s = next;
  }
  return s;
}

String _decodeHtmlEntitiesPass(String s) {
  var out = s.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]{1,6});'),
    (m) => _charFromUnicodeCodePoint(int.parse(m.group(1)!, radix: 16)),
  );
  out = out.replaceAllMapped(
    RegExp(r'&#([0-9]{1,7});'),
    (m) => _charFromUnicodeCodePoint(int.parse(m.group(1)!)),
  );
  out = out.replaceAllMapped(RegExp(r'&([a-zA-Z][a-zA-Z0-9]*);'), (m) {
    final k = m.group(1)!.toLowerCase();
    return _namedHtmlEntityChar(k) ?? m.group(0)!;
  });
  return out;
}

String _charFromUnicodeCodePoint(int cp) {
  if (cp < 0 || cp > 0x10FFFF) return '\uFFFD';
  if (cp > 0xFFFF) {
    cp -= 0x10000;
    final high = 0xD800 + (cp >> 10);
    final low = 0xDC00 + (cp & 0x3FF);
    return String.fromCharCodes([high, low]);
  }
  return String.fromCharCode(cp);
}

String? _namedHtmlEntityChar(String k) {
  switch (k) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
      return "'";
    case 'nbsp':
      return ' ';
    case 'frac14':
      return '\u00BC';
    case 'frac12':
      return '\u00BD';
    case 'frac34':
      return '\u00BE';
    case 'frac18':
      return '\u215B';
    case 'frac38':
      return '\u215C';
    case 'frac58':
      return '\u215D';
    case 'frac78':
      return '\u215E';
    case 'sup1':
      return '\u00B9';
    case 'sup2':
      return '\u00B2';
    case 'sup3':
      return '\u00B3';
    case 'ndash':
      return '\u2013';
    case 'mdash':
      return '\u2014';
    default:
      return null;
  }
}

/// Strips leading checkbox / empty-box glyphs (WP Recipe Maker, etc.) after decode.
String stripLeadingIngredientListDecorations(String input) {
  var s = input.trimLeft();
  while (s.isNotEmpty) {
    final runes = s.runes;
    final r = runes.first;
    if (r == 0x20 || r == 0x09 || r == 0xA0) {
      s = String.fromCharCodes(runes.skip(1));
      continue;
    }
    if (r >= 0x25A0 && r <= 0x25FF) {
      s = String.fromCharCodes(runes.skip(1));
      continue;
    }
    if (r >= 0x2610 && r <= 0x2612) {
      s = String.fromCharCodes(runes.skip(1));
      continue;
    }
    break;
  }
  return s.trimLeft();
}

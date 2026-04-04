import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/recipes/recipe_web_import_fetcher.dart';
import 'package:plateplan/core/strings/html_entities.dart';

void main() {
  group('parseRecipePageUrl', () {
    test('accepts https URL', () {
      final r = parseRecipePageUrl('https://example.com/recipe');
      expect(r.isOk, isTrue);
      expect(r.uri.toString(), 'https://example.com/recipe');
    });

    test('prepends https when scheme missing', () {
      final r = parseRecipePageUrl('allrecipes.com/recipe/123');
      expect(r.isOk, isTrue);
      expect(r.uri!.scheme, 'https');
    });

    test('rejects empty', () {
      final r = parseRecipePageUrl('  ');
      expect(r.isOk, isFalse);
    });

    test('rejects non-http schemes', () {
      final r = parseRecipePageUrl('file:///etc/passwd');
      expect(r.isOk, isFalse);
    });
  });

  group('htmlToPlainRecipeText', () {
    test('strips tags and script', () {
      final html = '''
<html><head><script>evil()</script></head>
<body><p>Hello <b>World</b></p></body></html>''';
      expect(htmlToPlainRecipeText(html), contains('Hello'));
      expect(htmlToPlainRecipeText(html), contains('World'));
      expect(htmlToPlainRecipeText(html), isNot(contains('evil')));
    });

    test('decodes numeric and fraction entities in body text', () {
      final html =
          '<li>&#9634; &frac14; cup orange juice concentrate</li>';
      final plain = htmlToPlainRecipeText(html);
      expect(plain, isNot(contains('&#')));
      expect(plain, isNot(contains('&frac14;')));
      expect(plain, contains('¼'));
      expect(plain, contains('cup orange juice'));
    });

    test('keeps block tags as line breaks for section detection', () {
      final html = '''
<body>
<h2>Ingredients</h2>
<p>For the sauce</p>
<ul><li>1 cup water</li></ul>
<h2>Instructions</h2>
<p>Mix.</p>
</body>''';
      final plain = htmlToPlainRecipeText(html);
      expect(plain.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty),
          orderedEquals([
            'Ingredients',
            'For the sauce',
            '1 cup water',
            'Instructions',
            'Mix.',
          ]));
    });
  });

  group('decodeHtmlEntities', () {
    test('numeric decimal, frac named, and chained amp', () {
      expect(
        decodeHtmlEntities('&#9634; &frac14; cup'),
        contains('¼'),
      );
      expect(decodeHtmlEntities('&amp;frac12;'), '½');
    });

    test('stripLeadingIngredientListDecorations removes box after decode', () {
      expect(
        stripLeadingIngredientListDecorations(
          decodeHtmlEntities('&#9634; &frac14; cup orange juice'),
        ),
        '¼ cup orange juice',
      );
    });
  });

  group('extractRecipeImageUrlFromHtml', () {
    test('reads Recipe.image string from JSON-LD (Food.com style)', () {
      final html = '''
<!DOCTYPE html><html><head>
<script type="application/ld+json">
{"@context":"http://schema.org","@type":"Recipe","name":"Test Smoothie",
"image":"https://img.sndimg.com/food/image/upload/v1/x.jpg"}
</script>
</head><body>Hi</body></html>''';
      expect(
        extractRecipeImageUrlFromHtml(html),
        'https://img.sndimg.com/food/image/upload/v1/x.jpg',
      );
    });

    test('reads ImageObject url when image is an object', () {
      final html = r'''
<script type="application/ld+json">
{"@type":"Recipe","name":"X","image":{"@type":"ImageObject","url":"https://cdn.example.com/p.jpg"}}
</script>''';
      expect(
        extractRecipeImageUrlFromHtml(html),
        'https://cdn.example.com/p.jpg',
      );
    });

    test('falls back to og:image when JSON-LD has no recipe image', () {
      final html = '''
<meta property="og:image" content="https://site.com/og.jpg" />
''';
      expect(
        extractRecipeImageUrlFromHtml(html),
        'https://site.com/og.jpg',
      );
    });
  });

  group('encode/decodeWebRecipeImportPayload', () {
    test('roundtrip', () {
      const url = 'https://example.com/r';
      const body = 'Ingredients:\n2 cups flour';
      const notes = 'Use GF flour';
      final encoded = encodeWebRecipeImportPayload(
        canonicalUrl: url,
        pageText: body,
        notes: notes,
      );
      final decoded = decodeWebRecipeImportPayload(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.canonicalUrl, url);
      expect(decoded.pageText, body);
      expect(decoded.notes, notes);
    });

    test('decode returns null for non-payload', () {
      expect(decodeWebRecipeImportPayload('just some text'), isNull);
    });
  });
}

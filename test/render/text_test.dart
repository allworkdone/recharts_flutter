// getWordsByLines expectations ported from test/component/Text.spec.tsx. The
// specs mock getBoundingClientRect, so every measured string has the mocked
// width; debugTextMeasurerOverride plays that role here.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/render/svg_text.dart';

const style = TextStyle(fontSize: 12);

List<TextLineWords> lines(String text, {double? width, bool scaleToFit = false, int? maxLines}) =>
    getWordsByLines(text, width: width, scaleToFit: scaleToFit, maxLines: maxLines, style: style);

/// Records compare their List fields by identity; compare `[...words, width]` instead.
List<List<Object?>> flat(List<TextLineWords> lines) => [for (final l in lines) [...l.words, l.width]];

void main() {
  tearDown(() => debugTextMeasurerOverride = null);

  group('<Text /> with every string 25px wide', () {
    setUp(() => debugTextMeasurerOverride = (_, _) => const Size(25, 17));

    test('Does not wrap long text if enough width', () {
      expect(lines('This is really long text', width: 300), hasLength(1));
    });

    test('Wraps long text if not enough width', () {
      expect(lines('This is really long text for 200px', width: 200), hasLength(2));
    });

    test('Does not perform word length calculation if width or scaleToFit props not set', () {
      expect(flat(lines('This is really long text')), [
        ['This', 'is', 'really', 'long', 'text', null],
      ]);
    });

    test('limits the output to maxLines', () {
      const text = '''Lorem ratione omnis fuga dignissimos in amet. Minus quam architecto non ea iste!
        Nihil amet in itaque error velit. Corporis autem sequi aut temporibus placeat.
        Perferendis quos veritatis quasi pariatur!''';
      expect(lines(text, width: 200, maxLines: 2), hasLength(2));
    });

    test('adds an ellipsis at the end of the truncated line', () {
      const text = '''Sit totam suscipit aliquid suscipit eius, cupiditate Aut excepturi ipsum ut suscipit
        facilis debitis Provident impedit a distinctio neque quaerat Optio quo quibusdam possimus
        provident accusantium. Molestiae similique nemo labore''';
      final last = lines(text, width: 200, maxLines: 2).last.words.join(' ');
      expect(last[last.length - 1], '…');
    });
  });

  group('getWordsByLines', () {
    const widths = {
      'M': 2.0,
      'Ma': 4.0,
      'M…': 5.0,
      'Mar': 6.0,
      'Ma…': 7.0,
      'Marc': 8.0,
      'Mar…': 9.0,
      'March': 10.0,
      'Marc…': 11.0,
      '\u00A0': 1.0,
    };
    setUp(() => debugTextMeasurerOverride = (text, _) => Size(widths[text]!, 0));

    test('returns the original text if it does not overflow', () {
      expect(flat(lines('March', width: 11, maxLines: 1)), [
        ['March', 10],
      ]);
    });

    test('returns the original text if it does not overflow and an additional character is narrower than the suffix', () {
      expect(flat(lines('March', width: 10, maxLines: 1)), [
        ['March', 10],
      ]);
    });

    test('truncates the text if it overflows and find the largest string with ellipsis that fits', () {
      expect(flat(lines('March', width: 7, maxLines: 1)), [
        ['Ma…', 7],
      ]);
    });
  });

  test('scaleToFit=true keeps one line; Text scales it by width / line width', () {
    // The spec mocks 50px, but its nbsp width (25px) comes from getStringSize's
    // cache filled by an earlier test: 5 * 50 + 4 * 25 = 350, scale(200 / 350).
    debugTextMeasurerOverride = (text, _) => Size(text == '\u00A0' ? 25 : 50, 20);
    final result = lines('This is really long text', width: 200, scaleToFit: true);
    expect(result, hasLength(1));
    expect(200 / result.single.width!, 0.5714285714285714);
  });
}

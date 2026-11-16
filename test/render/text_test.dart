// getWordsByLines expectations ported from test/component/Text.spec.tsx. The
// specs mock getBoundingClientRect, so every measured string has the mocked
// width; debugTextMeasurerOverride plays that role here.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/components.dart' show TextVerticalAnchor;
import 'package:recharts_flutter/src/render/svg_text.dart';

const style = TextStyle(fontSize: 12);

List<TextLineWords> lines(String text, {double? width, bool scaleToFit = false, int? maxLines, bool breakAll = false}) =>
    getWordsByLines(text, width: width, scaleToFit: scaleToFit, maxLines: maxLines, breakAll: breakAll, style: style);

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

    const codePointCases = {
      'emoji': ('😀😃', ['😀', '😃']),
      'Japanese hiragana': ('あいう', ['あ', 'い', 'う']),
      'Japanese katakana': ('アイウ', ['ア', 'イ', 'ウ']),
      'Chinese Han characters': ('中文汉', ['中', '文', '汉']),
      'supplementary Han characters': ('𠮷𠀀', ['𠮷', '𠀀']),
      'mixed kana, Han and emoji': ('あ中😀', ['あ', '中', '😀']),
    };
    for (final MapEntry(key: name, value: (text, expected)) in codePointCases.entries) {
      test('wraps $name on code-point boundaries with breakAll', () {
        expect([for (final l in lines(text, width: 25, breakAll: true)) l.words.join()], expected);
      });
    }

    test('renders nothing for empty content with breakAll and maxLines', () {
      // null and undefined children are a String here; '' with breakAll splits into no words.
      expect(getWordsByLines('', width: 300, maxLines: 1, breakAll: true, style: style), isEmpty);
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

  group('breakAll truncated by maxLines', () {
    // The spec's getStringSize: 10px for '…' and lone surrogates, 25px for every other code point.
    setUp(() => debugTextMeasurerOverride = (text, _) => Size(
        text.runes.fold(0.0, (sum, r) => sum + (r == 0x2026 || (r >= 0xD800 && r <= 0xDFFF) ? 10 : 25)), 17));
    const cases = {'emoji': ('😀😃😄', '😀…'), 'supplementary Han': ('𠮷𠀀𠮷', '𠮷…'), 'mixed kana and emoji': ('あ😀い', 'あ…')};
    for (final MapEntry(key: name, value: (text, expected)) in cases.entries) {
      test('keeps $name intact', () {
        expect([for (final l in lines(text, width: 50, maxLines: 1, breakAll: true)) l.words.join()], [expected]);
      });
    }
  });

  test('scaleToFit=true keeps one line; Text scales it by width / line width', () {
    // The spec mocks 50px, but its nbsp width (25px) comes from getStringSize's
    // cache filled by an earlier test: 5 * 50 + 4 * 25 = 350, scale(200 / 350).
    debugTextMeasurerOverride = (text, _) => Size(text == '\u00A0' ? 25 : 50, 20);
    final result = lines('This is really long text', width: 200, scaleToFit: true);
    expect(result, hasLength(1));
    expect(200 / result.single.width!, 0.5714285714285714);
  });

  group('lineHeight (Text.tsx): dy between lines, default 1em', () {
    // Ahem: 10px glyphs are squares from baseline - 8 to baseline + 2. With
    // verticalAnchor start the first baseline is at 0.71em = 7.1, so the last
    // ink row moves with (lines - 1) * lineHeight.
    Future<int> lastInkRow(WidgetTester tester, Object lineHeight) async {
      final rec = ui.PictureRecorder();
      paintSvgText(ui.Canvas(rec), 'a b', 0, 0,
          style: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
          verticalAnchor: TextVerticalAnchor.start,
          width: 1,
          lineHeight: lineHeight);
      final image = await rec.endRecording().toImage(40, 80);
      final bytes = (await image.toByteData())!;
      var last = -1;
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 40; x++) {
          if (bytes.getUint8((y * 40 + x) * 4 + 3) > 0) last = y;
        }
      }
      return last;
    }

    Future<int> firstInkRow(WidgetTester tester, TextVerticalAnchor anchor, Object lineHeight) async {
      final rec = ui.PictureRecorder();
      paintSvgText(ui.Canvas(rec), 'a b', 0, 40,
          style: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
          verticalAnchor: anchor,
          width: 1,
          lineHeight: lineHeight);
      final image = await rec.endRecording().toImage(40, 80);
      final bytes = (await image.toByteData())!;
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 40; x++) {
          if (bytes.getUint8((y * 40 + x) * 4 + 3) > 0) return y;
        }
      }
      return -1;
    }

    testWidgets('end anchor (Sunburst default) moves the first line up by (lines - 1) * lineHeight', (tester) async {
      await tester.runAsync(() async {
        final em = await firstInkRow(tester, TextVerticalAnchor.end, '1em');
        expect(await firstInkRow(tester, TextVerticalAnchor.end, 30), em - 20);
        expect(await firstInkRow(tester, TextVerticalAnchor.end, '.5em'), em + 5);
      });
    });

    testWidgets('middle anchor with a px lineHeight reduces to NaN, so dy is 0', (tester) async {
      await tester.runAsync(() async {
        // calc(0.5 * -30px + (0.71em / 2)) mixes px and em: invalid, the first baseline stays at y.
        final px = await firstInkRow(tester, TextVerticalAnchor.middle, '30px');
        final zero = await firstInkRow(tester, TextVerticalAnchor.end, '0px'); // one line shifted by 0 as well
        expect(px, zero);
        // In em it does reduce: the first baseline moves up.
        expect(await firstInkRow(tester, TextVerticalAnchor.middle, '1em'), lessThan(px));
      });
    });

    testWidgets('default is 1em; a number is px; em and px lengths work', (tester) async {
      await tester.runAsync(() async {
        final base = await lastInkRow(tester, '1em');
        expect(await lastInkRow(tester, 30), base + 20);
        expect(await lastInkRow(tester, '30px'), base + 20);
        expect(await lastInkRow(tester, '2em'), base + 10);
        expect(await lastInkRow(tester, '1em'), base);
      });
    });
  });
}

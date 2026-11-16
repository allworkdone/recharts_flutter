// getWordsByLines expectations ported from test/component/Text.spec.tsx. The
// specs mock getBoundingClientRect, so every measured string has the mocked
// width; debugTextMeasurerOverride plays that role here.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/components.dart'
    show Label, LabelPosition, TextAnchor, TextBackground, TextHalo, TextVerticalAnchor;
import 'package:recharts_flutter/src/core/polar_utils.dart' show PolarViewBox;
import 'package:recharts_flutter/src/render/polar_painter.dart' show paintPolarLabel;
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

  group('textPath (Text.spec.tsx textPath interactions)', () {
    // Ahem 10px: every glyph is a 10px square from baseline - 8 to baseline + 2.
    const ahem = TextStyle(fontSize: 10, color: Color(0xFF000000));
    final line = Path()
      ..moveTo(0, 50)
      ..lineTo(200, 50);

    Future<Rect?> ink(void Function(ui.Canvas c) paint) async {
      final rec = ui.PictureRecorder();
      paint(ui.Canvas(rec));
      final image = await rec.endRecording().toImage(240, 120);
      final bytes = (await image.toByteData())!;
      double? l, t, r, b;
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 240; x++) {
          if (bytes.getUint8((y * 240 + x) * 4 + 3) < 128) continue; // ignore antialiased edges
          l = l == null ? x.toDouble() : (x < l ? x.toDouble() : l);
          r = r == null ? x + 1.0 : (x + 1 > r ? x + 1.0 : r);
          t ??= y.toDouble();
          b = y + 1.0;
        }
      }
      return l == null ? null : Rect.fromLTRB(l, t!, r!, b!);
    }

    testWidgets('a horizontal path lays the text out like straight text; width, breakAll and lineHeight do not apply',
        (tester) async {
      await tester.runAsync(() async {
        final straight = await ink((c) => paintSvgText(c, 'one two', 0, 50, style: ahem));
        expect(straight!.width, 70);
        expect(
            await ink((c) =>
                paintSvgText(c, 'one two', 0, 0, style: ahem, textPath: line, width: 1, breakAll: true, lineHeight: '2em')),
            straight);
      });
    });

    testWidgets('textAnchor and startOffset place the text along the path; glyphs off the path are not drawn',
        (tester) async {
      await tester.runAsync(() async {
        Future<Rect?> at(Object? startOffset, TextAnchor anchor) =>
            ink((c) => paintSvgText(c, 'ab', 0, 0, style: ahem, textPath: line, startOffset: startOffset, textAnchor: anchor));
        Future<Rect?> straight(String text, double x, TextAnchor anchor) =>
            ink((c) => paintSvgText(c, text, x, 50, style: ahem, textAnchor: anchor));
        expect(await at(null, TextAnchor.start), await straight('ab', 0, TextAnchor.start));
        expect(await at(100, TextAnchor.middle), await straight('ab', 100, TextAnchor.middle));
        expect(await at('50%', TextAnchor.start), await straight('ab', 100, TextAnchor.start));
        // middle at 0: the midpoint of 'a' is at -5, so only 'b' is drawn.
        expect(await at(0, TextAnchor.middle), await straight('b', 0, TextAnchor.start));
        expect(await at(0, TextAnchor.end), isNull);
      });
    });

    testWidgets('glyphs turn with the path: a leftward path draws them upside down', (tester) async {
      await tester.runAsync(() async {
        final leftward = Path()
          ..moveTo(200, 50)
          ..lineTo(0, 50);
        // Straight text turned half a circle about the path's start.
        expect(await ink((c) => paintSvgText(c, 'ab', 0, 0, style: ahem, textPath: leftward)),
            await ink((c) => paintSvgText(c, 'ab', 200, 50, style: ahem, angle: 180)));
      });
    });

    testWidgets('dominantBaseline central centers the em box on the path', (tester) async {
      await tester.runAsync(() async {
        expect(await ink((c) => paintSvgText(c, 'ab', 0, 0, style: ahem, textPath: line, centralBaseline: true)),
            const Rect.fromLTRB(0, 45, 20, 55));
      });
    });

    testWidgets('angle turns the text about the center of its box (transform-box: fill-box)', (tester) async {
      await tester.runAsync(() async {
        final unturned = <Rect>[], turned = <Rect>[];
        paintSvgText(ui.Canvas(ui.PictureRecorder()), 'ab', 0, 0, style: ahem, textPath: line, startOffset: 100, boxes: unturned);
        final box = unturned.reduce((a, b) => a.expandToInclude(b));
        // PathMetrics work in float32.
        expect([box.left, box.width], [closeTo(100, 1e-4), closeTo(20, 1e-4)]);
        final inked = await ink(
            (c) => paintSvgText(c, 'ab', 0, 0, style: ahem, textPath: line, startOffset: 100, angle: 90, boxes: turned));
        final turnedBox = turned.reduce((a, b) => a.expandToInclude(b));
        expect([turnedBox.center.dx, turnedBox.center.dy, turnedBox.width, turnedBox.height],
            [closeTo(box.center.dx, 1e-4), closeTo(box.center.dy, 1e-4), closeTo(box.height, 1e-4), closeTo(20, 1e-4)]);
        // The ink (10px squares) turns about the same point.
        expect([inked!.center.dx, inked.center.dy, inked.width, inked.height],
            [closeTo(box.center.dx, 1), closeTo(box.center.dy, 1), closeTo(10, 1), closeTo(20, 1)]);
      });
    });
  });

  group('background (Text.background.spec.tsx, Label.background.spec.tsx)', () {
    test('resolveBackgroundPadding', () {
      expect(resolveBackgroundPadding(null), (x: 4, y: 2));
      expect(resolveBackgroundPadding(7), (x: 7, y: 7));
      expect(resolveBackgroundPadding(0), (x: 0, y: 0));
      expect(resolveBackgroundPadding((x: 10, y: null)), (x: 10, y: 2));
      expect(resolveBackgroundPadding((x: null, y: 10)), (x: 4, y: 10));
      expect(resolveBackgroundPadding((x: null, y: null)), (x: 4, y: 2));
    });

    test('getTextBackgroundRect', () {
      const textBox = Rect.fromLTWH(10, 20, 50, 14);
      expect(getTextBackgroundRect(textBox, (x: 3, y: 1)), const Rect.fromLTWH(7, 19, 56, 16));
      expect(getTextBackgroundRect(textBox, null), const Rect.fromLTWH(6, 18, 58, 18));
      expect(getTextBackgroundRect(const Rect.fromLTWH(1, 2, 0, 0), 3), isNull);
      expect(getTextBackgroundRect(const Rect.fromLTWH(1, 2, 10, 0), 3), isNull);
      expect(getTextBackgroundRect(const Rect.fromLTWH(1, 2, 0, 10), 3), isNull);
    });

    test('getTextPathBackgroundGeometry', () {
      const metrics = (pathLength: 200.0, textLength: 40.0, textHeight: 14.0, startOffset: 50.0);
      expect(getTextPathBackgroundGeometry(metrics, (x: 4, y: 2), TextAnchor.start), (start: 46, length: 48, strokeWidth: 18));
      expect(getTextPathBackgroundGeometry(metrics, 0, TextAnchor.middle), (start: 30, length: 40, strokeWidth: 14));
      expect(getTextPathBackgroundGeometry(metrics, 0, TextAnchor.end), (start: 10, length: 40, strokeWidth: 14));
      expect(
          getTextPathBackgroundGeometry(
              (pathLength: 200.0, textLength: 40.0, textHeight: 14.0, startOffset: 0.0), (x: 4, y: 2), TextAnchor.start),
          (start: 0, length: 44, strokeWidth: 18));
    });

    // FlutterTest 10px: ascent 7.5 and descent 2.5, so the glyph cell is 8 above and 3 below the baseline.
    const ahem = TextStyle(fontSize: 10, color: Color(0xFF000000));
    const red = Color(0xFFFF0000);

    Future<Rect?> inkOf(void Function(ui.Canvas c) paint, {int? rgba}) async {
      final rec = ui.PictureRecorder();
      paint(ui.Canvas(rec));
      final image = await rec.endRecording().toImage(240, 120);
      final bytes = (await image.toByteData())!;
      double? l, t, r, b;
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 240; x++) {
          final i = (y * 240 + x) * 4;
          if (bytes.getUint8(i + 3) < 128 || (rgba != null && bytes.getUint32(i) != rgba)) continue;
          l = l == null || x < l ? x.toDouble() : l;
          r = r == null || x + 1 > r ? x + 1.0 : r;
          t ??= y.toDouble();
          b = y + 1.0;
        }
      }
      return l == null ? null : Rect.fromLTRB(l, t!, r!, b!);
    }

    testWidgets('a rectangle around the glyph cells, with the padding, fill and rx of the background object', (tester) async {
      await tester.runAsync(() async {
        final boxes = <Rect>[];
        expect(
            await inkOf((c) => paintSvgText(c, 'ab', 10, 20,
                style: ahem, background: const TextBackground(fill: red, rx: 0, padding: (x: 1, y: 3)), boxes: boxes),
                rgba: 0xFF0000FF),
            const Rect.fromLTRB(9, 9, 31, 26));
        expect(boxes, [const Rect.fromLTRB(9, 9, 31, 26)]);
      });
    });

    testWidgets('no rectangle when the text has no size', (tester) async {
      await tester.runAsync(() async {
        final boxes = <Rect>[];
        expect(await inkOf((c) => paintSvgText(c, '', 10, 20, style: ahem, background: true, boxes: boxes)), isNull);
        expect(boxes, isEmpty);
      });
    });

    testWidgets('the rectangle gets the text transform inside a label layer too', (tester) async {
      await tester.runAsync(() async {
        // The cell 100..120 x 42..53 turned 90 degrees about (100, 50).
        expect(
            await inkOf((c) => paintLabelLayer(c, (c) => paintSvgText(c, 'ab', 100, 50,
                style: ahem, angle: 90, background: const TextBackground(fill: red, rx: 0, padding: 0)))),
            const Rect.fromLTRB(97, 50, 108, 70));
      });
    });

    testWidgets('label backgrounds go below every label text: two overlapping labels keep both texts', (tester) async {
      await tester.runAsync(() async {
        void first(ui.Canvas c) => paintSvgText(c, 'ab', 10, 20, style: ahem.copyWith(color: const Color(0xFF0000FF)));
        void second(ui.Canvas c) => paintSvgText(c, 'b', 40, 20, style: ahem, background: const TextBackground(fill: red, padding: 30));
        final firstText = await inkOf(first, rgba: 0x0000FFFF);
        expect(firstText, isNotNull);
        // On its own, the second label's background covers the first text; in a label layer it does not.
        expect(await inkOf((c) => [first(c), second(c)], rgba: 0x0000FFFF), isNull);
        expect(await inkOf((c) => paintLabelLayer(c, (c) => [first(c), second(c)]), rgba: 0x0000FFFF), firstText);
      });
    });

    testWidgets('on a path: a round-capped stroke over the stretch the text covers, and its outline', (tester) async {
      await tester.runAsync(() async {
        final line = Path()
          ..moveTo(0, 50)
          ..lineTo(200, 50);
        // 'ab' covers 50..70; padding (4, 2) and 14px stroke caps reach 50 - 4 - 7 = 39 and 70 + 4 + 7 = 81,
        // where the caps cover less than half of the last pixel column.
        expect(
            await inkOf((c) => paintSvgText(c, 'ab', 0, 0,
                style: ahem, textPath: line, startOffset: 50, background: const TextBackground(fill: red)),
                rgba: 0xFF0000FF),
            const Rect.fromLTRB(40, 43, 80, 57));
        expect(
            await inkOf((c) => paintSvgText(c, 'ab', 0, 0,
                style: ahem,
                textPath: line,
                startOffset: 50,
                angle: 90,
                background: const TextBackground(fill: red, stroke: Color(0xFF00FF00), strokeWidth: 2)),
                rgba: 0x00FF00FF),
            // The outline is 2 * 2 wider; angle turns the text, not the background.
            const Rect.fromLTRB(38, 41, 82, 59));
      });
    });

    test('a radial label background starts the arc padding.x earlier and leaves the text in place', () {
      List<Rect> boxes(Object? background) {
        final out = <Rect>[];
        paintPolarLabel(ui.Canvas(ui.PictureRecorder()),
            Label(value: 'text', position: LabelPosition.insideStart, startOffset: 20, background: background),
            const PolarViewBox(cx: 50, cy: 50, innerRadius: 20, outerRadius: 80, startAngle: 0, endAngle: 90),
            baseStyle: ahem, scaler: TextScaler.noScaling, boxes: out);
        return out;
      }

      final plain = boxes(null), padded = boxes(const TextBackground(padding: (x: 6, y: null)));
      // The background's bounds come first, then the same glyph cells.
      expect(padded.length, plain.length + 1);
      for (var i = 0; i < plain.length; i++) {
        // PathMetrics measure the two arcs in float32.
        expect([padded[i + 1].left, padded[i + 1].top], [closeTo(plain[i].left, 0.1), closeTo(plain[i].top, 0.1)]);
      }
    });
  });

  group('halo (Text.halo.spec.tsx)', () {
    const ahem = TextStyle(fontSize: 10, color: Color(0xFF000000));
    final line = Path()
      ..moveTo(0, 50)
      ..lineTo(200, 50);

    /// Bounds of the pixels of [rgba], or of every pixel at least half covered.
    Future<Rect?> inkOf(void Function(ui.Canvas c) paint, {int? rgba}) async {
      final rec = ui.PictureRecorder();
      paint(ui.Canvas(rec));
      final bytes = (await (await rec.endRecording().toImage(240, 120)).toByteData())!;
      double? l, t, r, b;
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 240; x++) {
          final i = (y * 240 + x) * 4;
          if (bytes.getUint8(i + 3) < 128 || (rgba != null && bytes.getUint32(i) != rgba)) continue;
          l = l == null || x < l ? x.toDouble() : l;
          r = r == null || x + 1 > r ? x + 1.0 : r;
          t ??= y.toDouble();
          b = y + 1.0;
        }
      }
      return l == null ? null : Rect.fromLTRB(l, t!, r!, b!);
    }

    /// [halo] reaches about [width] / 2 past [plain] on every side (whole pixels at least half covered).
    void expectGrown(Rect? halo, Rect plain, double width) {
      final sides = [plain.left - halo!.left, plain.top - halo.top, halo.right - plain.right, halo.bottom - plain.bottom];
      expect(sides, everyElement(inInclusiveRange(width / 2 - 0.5, width / 2 + 1)));
    }

    testWidgets('no halo by default; true strokes the letters white, 3 wide, under the fill', (tester) async {
      await tester.runAsync(() async {
        void text(ui.Canvas c, Object? halo) => paintSvgText(c, 'ab', 20, 50, style: ahem, halo: halo);
        expect(await inkOf((c) => text(c, null), rgba: 0xFFFFFFFF), isNull);
        expect(await inkOf((c) => text(c, false), rgba: 0xFFFFFFFF), isNull);
        final plain = (await inkOf((c) => text(c, null)))!;
        // 1.5px of stroke around the letters; the fill stays black on top.
        expectGrown(await inkOf((c) => text(c, true)), plain, 3);
        expect(await inkOf((c) => text(c, true), rgba: 0xFFFFFFFF), isNotNull);
        expect(await inkOf((c) => text(c, true), rgba: 0x000000FF), await inkOf((c) => text(c, null), rgba: 0x000000FF));
      });
    });

    testWidgets('stroke and strokeWidth from the halo object', (tester) async {
      await tester.runAsync(() async {
        final plain = (await inkOf((c) => paintSvgText(c, 'ab', 20, 50, style: ahem)))!;
        void gold(ui.Canvas c) => paintSvgText(c, 'ab', 20, 50,
            style: ahem, halo: const TextHalo(stroke: Color(0xFFFFD700), strokeWidth: 5, strokeLinejoin: StrokeJoin.miter));
        expectGrown(await inkOf(gold), plain, 5);
        expect(await inkOf(gold, rgba: 0xFFD700FF), isNotNull);
      });
    });

    testWidgets('text on a path gets the halo too', (tester) async {
      await tester.runAsync(() async {
        expect(await inkOf((c) => paintSvgText(c, 'ab', 0, 0, style: ahem, textPath: line, halo: true), rgba: 0xFFFFFFFF),
            isNotNull);
      });
    });
  });
}

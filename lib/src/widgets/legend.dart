// Port of src/component/DefaultLegendContent.tsx and the wrapper positioning
// of src/component/Legend.tsx (getDefaultPosition, getWidthOrHeight). The CSS
// inline formatting (inline-block items with `margin-right: 10`, a 14px icon
// with `vertical-align: middle; margin-right: 4px`, `text-align`) is computed
// here so the legend size is known before the plot area is laid out.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../core/curve.dart';
import '../render/shapes.dart';
import '../render/svg_text.dart';
import '../util.dart';

class LegendItemLayout {
  LegendItemLayout(this.entry, this.text, this.style, this.origin, this.iconTop, this.textTop);
  final LegendPayload entry;
  final String text;
  final TextStyle style;

  /// Top-left of the item's box inside the legend.
  final Offset origin;
  final double iconTop;
  final double textTop;
}

class LegendLayout {
  LegendLayout(this.size, this.items);

  /// The wrapper's bounding box (what Legend reports as its size).
  final Size size;
  final List<LegendItemLayout> items;
}

// ponytail: CSS `vertical-align: middle` needs the font's x-height, which
// Flutter does not expose; Roboto's (1082/2048 em) is assumed for every font.
const double _xHeightEm = 1082 / 2048;

LegendLayout computeLegendLayout({
  required Legend legend,
  required List<LegendPayload> payload,
  required Size chartSize,
  required Margin margin,
  required TextStyle baseStyle,
  required TextScaler scaler,
}) {
  final layout = legend.layout ?? ChartLayout.horizontal;
  final iconSize = legend.iconSize;
  final entries = payload.where((p) => p.type != LegendType.none).toList();
  final em = scaler.scale(baseStyle.fontSize ?? 14);
  final x = _xHeightEm * em;
  final metrics = textPainterFor('x', baseStyle, scaler);
  final rawAscent = metrics.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  // Blink rounds font ascent/descent to integers (SimpleFontData) and the
  // vertical-align shift to LayoutUnits (1/64 px).
  final ascent = jsRound(rawAscent);
  final descent = jsRound(metrics.height - rawAscent);
  final halfX = (x / 2 * 64).roundToDouble() / 64;
  final baseline = math.max(ascent, halfX + iconSize / 2);
  final itemHeight = baseline + math.max(descent, iconSize / 2 - halfX);
  final iconTop = baseline - halfX - iconSize / 2;
  final textTop = baseline - rawAscent;

  final measured = <(LegendPayload, String, TextStyle, double)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final raw = legend.formatter != null ? legend.formatter!(e.value, e, i) : e.value;
    final text = jsString(raw);
    var style = baseStyle.merge(legend.labelStyle);
    final color = e.inactive ? legend.inactiveColor : (legend.labelStyle?.color ?? e.color);
    if (color != null) style = style.copyWith(color: color);
    final width = iconSize + 4 + measureText(text, style, scaler).width;
    measured.add((e, text, style, width));
  }

  final items = <LegendItemLayout>[];
  if (layout == ChartLayout.horizontal) {
    final boxWidth = legend.width ?? chartSize.width - margin.left - margin.right;
    final rows = <List<(LegendPayload, String, TextStyle, double)>>[];
    var rowWidth = 0.0;
    for (final m in measured) {
      final outer = m.$4 + 10;
      if (rows.isEmpty || (rowWidth + outer > boxWidth && rows.last.isNotEmpty)) {
        rows.add([]);
        rowWidth = 0;
      }
      rows.last.add(m);
      rowWidth += outer;
    }
    for (var r = 0; r < rows.length; r++) {
      final w = rows[r].fold<double>(0, (a, m) => a + m.$4 + 10);
      var left = switch (legend.align) {
        HorizontalAlign.left => 0.0,
        HorizontalAlign.center => (boxWidth - w) / 2,
        HorizontalAlign.right => boxWidth - w,
      };
      for (final m in rows[r]) {
        items.add(LegendItemLayout(m.$1, m.$2, m.$3, Offset(left, r * itemHeight), iconTop, textTop));
        left += m.$4 + 10;
      }
    }
    final h = legend.height ?? (entries.isEmpty ? 0.0 : rows.length * itemHeight);
    return LegendLayout(Size(entries.isEmpty ? 0 : boxWidth, h), items);
  }
  var maxWidth = 0.0;
  for (var i = 0; i < measured.length; i++) {
    final m = measured[i];
    items.add(LegendItemLayout(m.$1, m.$2, m.$3, Offset(0, i * itemHeight), iconTop, textTop));
    maxWidth = math.max(maxWidth, m.$4 + 10);
  }
  return LegendLayout(
      Size(legend.width ?? maxWidth, legend.height ?? measured.length * itemHeight), items);
}

/// `getDefaultPosition` -> left/top of the legend wrapper inside the chart.
Offset legendPosition(Legend legend, Size chartSize, Margin margin, Size box) {
  final layout = legend.layout ?? ChartLayout.horizontal;
  final double left;
  if (legend.align == HorizontalAlign.center && layout == ChartLayout.vertical) {
    left = (chartSize.width - box.width) / 2;
  } else if (legend.align == HorizontalAlign.right) {
    left = chartSize.width - margin.right - box.width;
  } else {
    left = margin.left;
  }
  final double top = switch (legend.verticalAlign) {
    VerticalAlign.middle => (chartSize.height - box.height) / 2,
    VerticalAlign.bottom => chartSize.height - margin.bottom - box.height,
    VerticalAlign.top => margin.top,
  };
  return Offset(left, top);
}

/// `DefaultLegendContent` laid out by [computeLegendLayout].
class DefaultLegendContent extends StatelessWidget {
  const DefaultLegendContent({super.key, required this.legend, required this.layout, required this.scaler});
  final Legend legend;
  final LegendLayout layout;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: layout.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final item in layout.items) ...[
            Positioned(
              left: item.origin.dx,
              top: item.origin.dy + item.iconTop,
              width: legend.iconSize,
              height: legend.iconSize,
              child: CustomPaint(painter: _LegendIconPainter(item.entry, legend)),
            ),
            Positioned(
              left: item.origin.dx + legend.iconSize + 4,
              top: item.origin.dy + item.textTop,
              child: Text(item.text, style: item.style, textScaler: scaler, softWrap: false, maxLines: 1),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendIconPainter extends CustomPainter {
  _LegendIconPainter(this.entry, this.legend);
  final LegendPayload entry;
  final Legend legend;

  @override
  void paint(Canvas canvas, Size size) =>
      paintLegendIcon(canvas, entry, legend.iconType, legend.inactiveColor, legend.iconSize);

  @override
  bool shouldRepaint(_LegendIconPainter old) => old.entry != entry || old.legend != legend;
}

/// Reports its child's size after layout (Legend's `useElementOffset`), used
/// for custom legend content whose size is unknown before layout.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (_last != size) {
      _last = size;
      final s = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
    }
  }
}

/// The Legend positioned in the chart: [DefaultLegendContent] laid out as
/// [layout], or the custom `content` built from [payload], whose size is
/// measured after layout and reported through [onCustomSize].
Widget legendLayer(
  Legend legend, {
  required LegendLayout? layout,
  required List<LegendPayload> payload,
  required Size chartSize,
  required Margin margin,
  required TextScaler scaler,
  required Size? customSize,
  required ValueChanged<Size> onCustomSize,
}) {
  if (layout != null) {
    final pos = legendPosition(legend, chartSize, margin, layout.size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IgnorePointer(child: DefaultLegendContent(legend: legend, layout: layout, scaler: scaler)),
    );
  }
  final pos = legendPosition(legend, chartSize, margin, customSize ?? Size.zero);
  return Positioned(
    left: pos.dx,
    top: pos.dy,
    child: SizeReporter(onSize: onCustomSize, child: legend.content!(payload)),
  );
}

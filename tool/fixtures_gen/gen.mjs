// Writes expected outputs of the real Recharts 3.10.1 / d3 code into
// test/core/fixtures/*.json for the Dart ports in lib/src/core/.
//
// Regenerate (from the repo root):
//   cd tool/fixtures_gen && npm install && npm run gen
//
// `npm run gen` bundles this file with esbuild using the ESM entry points
// (recharts/es6, victory-vendor/es -> d3-shape 3.2.0, d3-array 3.2.4), which
// is what browser bundlers ship, then runs the bundle in Node (V8).

import { writeFileSync, mkdirSync } from 'node:fs';
import Decimal from 'decimal.js-light';
import { getNiceTickValues, getTickValuesFixedDomain } from 'recharts/es6/util/scale/getNiceTickValues.js';
import { configBezier, createEasingFunction, createSpringEasing } from 'recharts/es6/animation/easing.js';
import { getPath } from 'recharts/es6/shape/Curve.js';
import { rechartsScaleFactory } from 'recharts/es6/util/scale/RechartsScale.js';
import { scaleLinear, scaleLog, scalePow, scaleBand, scalePoint } from 'victory-vendor/d3-scale';

const outDir = new URL('../../../test/core/fixtures/', import.meta.url);
mkdirSync(outDir, { recursive: true });

// JSON has no NaN/Infinity: encode them as strings.
const enc = v => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : String(v);
  if (v === undefined) return null;
  if (Array.isArray(v)) return v.map(enc);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)]));
  return v;
};
const write = (name, data) => writeFileSync(new URL(name, outDir), JSON.stringify(enc(data)) + '\n');

// Deterministic PRNG (mulberry32).
let seed = 0x5eed;
const rand = () => {
  seed |= 0;
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const randRound = (x, digits) => Number(x.toFixed(digits));

// ---------------------------------------------------------------------------
// getNiceTickValues / getTickValuesFixedDomain

const niceDomains = [
  [0, 100], [0, 0.3], [0.1, 0.7], [0, 0.1 + 0.2], [0.1, 0.2], [0, 1 / 3], [-10, 10], [-1e-7, 1e-7],
  [1e-7, 3e-7], [0, 1e9], [1e9, 1e9 + 7], [5, 5], [0, 0], [0.5, 0.5], [-0.5, -0.5], [0.0012, 0.0012],
  [123.456, 123.456], [-3.7, -3.7], [1e9, 1e9], [100, 0], [0.7, 0.1], [-Infinity, 0], [0, Infinity],
  [-Infinity, Infinity], [3, -Infinity], [Infinity, 2], [0, 1], [0, 9], [0, 10], [0, 11], [1, 7],
  [12, 98], [-123.4, 567.8], [0.001, 0.002], [2.5, 2.5], [-1, 0], [-0.0001, 0.0003], [1e-10, 5e-10],
  [1234567, 1234999], [99.99, 100.01], [17, 23], [-50, -2], [-1e9, 3e8], [0.3, 0.30000000000000004],
  [999.9999999999999, 1000], [0, 0.09999999999999999], [-7.77, 13.13], [2, 3], [10, 1000],
];
for (let i = 0; i < 40; i++) {
  const mag = 10 ** Math.floor(rand() * 18 - 8);
  const a = randRound((rand() * 2 - 1) * mag * 10, 12);
  const b = randRound(a + rand() * mag * (rand() < 0.5 ? 1 : 30), 12);
  niceDomains.push(rand() < 0.2 ? [b, a] : [a, b]);
}

const tickCounts = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const modes = ['auto', 'adaptive', 'snap125'];
const run = f => {
  try {
    return { out: f() };
  } catch (e) {
    // A stack overflow inside decimal.js-light leaves its global precision and
    // its internal `external` flag changed; restore both (log() resets the flag).
    Decimal.config({ precision: 20 });
    new Decimal(2).log();
    return { throws: String(e) };
  }
};
const nice = [];
const fixed = [];
for (const domain of niceDomains) {
  for (const tickCount of tickCounts) {
    for (const allowDecimals of [true, false]) {
      for (const mode of modes) {
        nice.push({ domain, tickCount, allowDecimals, mode, ...run(() => getNiceTickValues(domain, tickCount, allowDecimals, mode)) });
        fixed.push({ domain, tickCount, allowDecimals, mode, ...run(() => getTickValuesFixedDomain(domain, tickCount, allowDecimals, mode)) });
      }
    }
  }
}
write('nice_ticks.json', { nice, fixed });

// ---------------------------------------------------------------------------
// Scales

const wrap = (scale, extra) => {
  const r = rechartsScaleFactory(scale);
  const [lo, hi] = r.range();
  const probes = [lo - 1, lo, (lo + hi) / 2, hi, hi + 1];
  return { rechartsRange: r.range(), isInRange: probes.map(v => [v, r.isInRange(v)]), ...extra(r) };
};
const tickCountsScale = [undefined, 0, 1, 2, 3, 5, 10, 20];
const continuousCase = (scale, params) => {
  const d = scale.domain();
  const span = d[d.length - 1] - d[0];
  const inputs = [...d, d[0] - span, d[0] + span / 3, d[d.length - 1] + span, (d[0] + d[d.length - 1]) / 2, 0, 1, -1, null, NaN];
  const rg = scale.range();
  const rangeInputs = [...rg, rg[0] - 10, (rg[0] + rg[rg.length - 1]) / 2, rg[rg.length - 1] + 10];
  return {
    ...params,
    ...wrap(scale, r => ({ map: inputs.map(x => [x, r.map(x)]) })),
    invert: rangeInputs.map(y => [y, scale.invert(y)]),
    ticks: tickCountsScale.map(c => [c ?? null, scale.ticks(c)]),
    nice: params.kind === 'log' ? [[null, scale.copy().nice().domain()]] : [undefined, 2, 5, 10].map(c => [c ?? null, scale.copy().nice(c).domain()]),
  };
};

const ranges = [[0, 500], [300, 0], [0.5, 333.7]];
const linear = [];
for (const domain of [[0, 100], [0, 0.3], [-1e-7, 3e-7], [1e9, 1e9 + 7], [100, -100], [0.1, 0.7], [5, 5], [-123.4, 567.8], [0, 50, 100], [0, 0.30000000000000004], [17.3, 23.9]]) {
  for (const range of domain.length === 3 ? [[0, 10, 100], [0, 500]] : ranges) {
    for (const clamp of [false, true]) {
      linear.push(continuousCase(scaleLinear().domain(domain).range(range).clamp(clamp), { kind: 'linear', domain, range, clamp }));
    }
  }
}

const log = [];
for (const [domain, base] of [
  [[1, 1000], 10], [[1, 10], 10], [[0.001, 1000], 10], [[1, 1e7], 10], [[1, 1e15], 10], [[-1000, -1], 10],
  [[1000, 1], 10], [[3, 7], 10], [[1, 2], 10], [[1, 64], 2], [[1, 100], Math.E], [[0.5, 300], 10], [[2, 5000], 3],
]) {
  for (const range of [[0, 500], [300, 0]]) {
    for (const clamp of [false, true]) {
      log.push(continuousCase(scaleLog().base(base).domain(domain).range(range).clamp(clamp), { kind: 'log', domain, range, base, clamp }));
    }
  }
}

const pow = [];
for (const exponent of [1, 0.5, 2, 3, 0.25]) {
  for (const domain of [[0, 100], [-10, 10], [0.1, 0.7], [100, 1]]) {
    for (const clamp of [false, true]) {
      const range = [0, 400];
      pow.push(continuousCase(scalePow().exponent(exponent).domain(domain).range(range).clamp(clamp), { kind: 'pow', domain, range, exponent, clamp }));
    }
  }
}

const bandDomains = [['a', 'b', 'c'], ['a', 'b', 'a', 'c', 'b'], ['only'], [], [1, 2, 3, 4, 5, 6, 7], ['x', 1, '1', null]];
const positions = [undefined, 'start', 'middle', 'end'];
const bandMap = (r, domain) =>
  [...domain, 'missing', 99].flatMap(x => positions.map(position => [x, position ?? null, r.map(x, position ? { position } : undefined)]));
const band = [];
for (const domain of bandDomains) {
  for (const range of ranges) {
    for (const [paddingInner, paddingOuter] of [[0, 0], [0.1, 0.1], [0.5, 0.2], [0.3, 1], [1.5, 0]]) {
      for (const align of [0, 0.5, 1]) {
        for (const round of [false, true]) {
          const s = scaleBand().domain(domain).range(range).paddingInner(paddingInner).paddingOuter(paddingOuter).align(align).round(round);
          band.push({
            domain, range, paddingInner, paddingOuter, align, round,
            step: s.step(), bandwidth: s.bandwidth(), outDomain: s.domain(),
            ...wrap(s, r => ({ map: bandMap(r, domain) })),
          });
        }
      }
    }
  }
}
const point = [];
for (const domain of bandDomains) {
  for (const range of ranges) {
    for (const padding of [0, 0.5, 1, 2]) {
      for (const align of [0, 0.5, 1]) {
        for (const round of [false, true]) {
          const s = scalePoint().domain(domain).range(range).padding(padding).align(align).round(round);
          point.push({
            domain, range, padding, align, round,
            step: s.step(), bandwidth: s.bandwidth(), outDomain: s.domain(),
            ...wrap(s, r => ({ map: bandMap(r, domain) })),
          });
        }
      }
    }
  }
}
write('scales.json', { linear, log, pow, band, point });

// ---------------------------------------------------------------------------
// Curves: Recharts' getPath (d3 line + curve factory) as SVG path data.

const pointSets = {
  empty: [],
  one: [[10, 20]],
  two: [[10, 20], [30.123456, 40.98765]],
  three: [[0, 0], [10, 30], [20, 10]],
  four: [[0, 0], [10, 30], [20, 10], [35, 25]],
  decimals: [[0, 12.3456], [13.1313, 45.0001], [27.77777, 3.33333], [41.0005, 39.9995], [55.5555, 17.1717], [69.9, 60.06], [83.3333, 5.4321]],
  gaps: [[0, 10], [10, 20], null, [30, 15], [40, 35], [50, 25], null, null, [80, 5], [90, 45]],
  isolated: [[0, 10], null, [20, 30], [30, 25], null, [50, 40]],
  duplicateX: [[0, 0], [10, 5], [10, 15], [20, 10], [30, 10]],
  coincident: [[0, 0], [10, 10], [10, 10], [20, 5], [30, 30]],
  vertical: [[10, 0], [50, 25.5], [20, 50], [80, 75], [40, 100]],
  nonFinite: [[0, 0], [10, NaN], [20, 5], [Infinity, 3], [40, 8], [50, -Infinity], [60, 2]],
  descending: [[50, 1], [40, 3], [30, 2], [20, 5]],
  large: [[-1000.5, 2e5], [0, -3.25], [1234.5678, 99999.9999], [5000, 0]],
  flat: [[0, 5], [10, 5], [20, 5], [30, 5]],
};
const curveTypes = ['basis', 'basisClosed', 'basisOpen', 'bumpX', 'bumpY', 'bump', 'linear', 'linearClosed', 'natural', 'monotoneX', 'monotoneY', 'monotone', 'step', 'stepBefore', 'stepAfter'];
const curves = [];
for (const [name, pts] of Object.entries(pointSets)) {
  const points = pts.map(p => (p ? { x: p[0], y: p[1] } : { x: null, y: null }));
  for (const type of curveTypes) {
    for (const layout of ['horizontal', 'vertical']) {
      for (const connectNulls of [false, true]) {
        curves.push({ name, points: pts, type, layout, connectNulls, d: getPath({ type, points, layout, connectNulls }) });
      }
    }
  }
}
write('curves.json', curves);

// ---------------------------------------------------------------------------
// Easing

const ts = [-0.5, -0.1, 0, 0.001, 0.01, 0.025];
for (let t = 0.05; t < 1; t += 0.05) ts.push(Number(t.toFixed(2)));
ts.push(0.333, 0.5005, 0.999, 1, 1.1, 2, NaN);
const sample = f => (f ? ts.map(t => f(t)) : null);
const easingNames = [
  'linear', 'ease', 'ease-in', 'ease-out', 'ease-in-out', 'spring',
  'cubic-bezier(0.1,0.7,1.0,0.1)', 'cubic-bezier(0.68, -0.55, 0.265, 1.55)', 'cubic-bezier(0.25,0.1,0.25,1)',
  'cubic-bezier(1,2,3)', 'cubic-bezier(a,b,c,d)', 'cubic-bezier((0,0,1,1))', 'cubic-bezier(0.5e0, 1e-1, .3, 1.)',
  'cubic-bezier( 0.4px,0,0.2,1)', 'cubic-bezier(0,0,1,1', 'bogus', 'Ease', '',
];
const beziers = [[0.1, 0.7, 1.0, 0.1], [0.68, -0.55, 0.27, 1.55], [0, 0, 1, 1], [0.42, 0, 0.58, 1], [1, 0, 0, 1], [0.9, 0.1, 0.1, 0.9], [0, 1, 1, 0]];
const springs = [{}, { stiff: 200, damping: 20 }, { stiff: 50, damping: 2 }, { stiff: 100, damping: 8, dt: 5 }];
write('easing.json', {
  ts,
  named: easingNames.map(name => ({ name, out: sample(createEasingFunction(name)) })),
  bezier: beziers.map(args => ({ args, out: sample(configBezier(...args)) })),
  spring: springs.map(config => ({ config, out: sample(createSpringEasing(config)) })),
});

// ---------------------------------------------------------------------------
// V8 Math.log / Math.log10 / Math.pow(10, k), bit for bit.

const view = new DataView(new ArrayBuffer(8));
const nextUp = (x, n) => {
  view.setFloat64(0, x);
  view.setBigUint64(0, view.getBigUint64(0) + BigInt(n));
  return view.getFloat64(0);
};
const mathInputs = [0, -0, 1, -1, Infinity, -Infinity, NaN, 5e-324, 2.2250738585072014e-308, 1e-310, Number.MAX_VALUE, Math.E, 2, 3, 0.5];
for (let k = -25; k <= 25; k++) {
  const p = Number(`1e${k}`);
  mathInputs.push(p, nextUp(p, 1), nextUp(p, -1), nextUp(p, 2), nextUp(p, -2), 3 * p, 0.3 * p, 2 ** k);
}
for (let i = 0; i < 2000; i++) mathInputs.push(10 ** (rand() * 40 - 20) * (rand() < 0.02 ? -1 : 1));
for (let i = 0; i < 300; i++) mathInputs.push(1 + (rand() - 0.5) * 1e-6, 1 + (rand() - 0.5) * 1e-3);
const pow10 = [];
for (let k = -30; k <= 30; k++) pow10.push([k, Math.pow(10, k)]);
write('js_math.json', {
  log: mathInputs.map(x => [x, Math.log(x)]),
  log10: mathInputs.map(x => [x, Math.log10(x)]),
  pow10,
});

console.log(`fixtures: ${nice.length} nice, ${linear.length + log.length + pow.length + band.length + point.length} scales, ${curves.length} curves`);

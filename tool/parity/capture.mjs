// usage: node capture.mjs <webBase> <flutterBase|none> [fixtureFilter] [--anim]
import { chromium } from 'playwright';
import pixelmatch from 'pixelmatch';
import { PNG } from 'pngjs';
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const ANIM = process.argv.includes('--anim');
const webBase = args[0] || 'http://localhost:5180';
const flBase = args[1] && args[1] !== 'none' ? args[1] : null;
const filter = args[2] || '';
const here = import.meta.dirname;
const fxDir = path.resolve(here, '../../example/assets/parity/fixtures');
const outDir = path.join(here, 'out');
fs.rmSync(outDir, { recursive: true, force: true });

const fixtures = fs.readdirSync(fxDir).filter((f) => f.endsWith('.json'))
  .map((f) => JSON.parse(fs.readFileSync(path.join(fxDir, f), 'utf8')))
  .filter((f) => !filter || f.name.includes(filter));

const WEB_LAG_MS = +(process.env.WEB_LAG_MS ?? 0);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const browser = await chromium.launch();

// A cold page (Flutter compiles its engine per browser context) can miss the
// readiness deadline when several boot at once: retry, then fail loudly rather
// than diff a blank page.
async function open(side, base, fx, clock, anim, attempt = 1) {
  const ctx = await browser.newContext({
    viewport: { width: fx.width + 40, height: fx.height + 40 }, deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();
  if (clock) await page.clock.install({ time: 0 });
  await page.goto(`${base}/?fixture=${fx.name}${anim ? '&anim=1' : ''}`, { waitUntil: 'load' });
  const t0 = Date.now();
  try {
    await page.waitForFunction('window.__parityReady === true', null, { timeout: 30000 });
  } catch (e) {
    await ctx.close();
    if (attempt < 3) {
      console.warn(`  [${side}] ${fx.name} not ready after ${Date.now() - t0} ms, retrying`);
      return open(side, base, fx, clock, anim, attempt + 1);
    }
    throw new Error(`[${side}] ${fx.name} never became ready`);
  }
  return { ctx, page };
}

const shot = (page, fx) => page.screenshot({ clip: { x: 0, y: 0, width: fx.width, height: fx.height } });

function diff(a, b, dir) {
  const A = PNG.sync.read(a), B = PNG.sync.read(b);
  if (A.width !== B.width || A.height !== B.height) return { mismatchPercent: null, note: 'size mismatch' };
  const D = new PNG({ width: A.width, height: A.height });
  const n = pixelmatch(A.data, B.data, D.data, A.width, A.height, { threshold: 0.1, includeAA: false });
  fs.writeFileSync(path.join(dir, 'diff.png'), PNG.sync.write(D));
  return { mismatchPercent: +(100 * n / (A.width * A.height)).toFixed(3) };
}

const results = [];
async function record(fx, state, webPng, flPng) {
  const dir = path.join(outDir, fx.name, state);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'web.png'), webPng);
  let r = { mismatchPercent: null, note: 'flutter not captured' };
  if (flPng) { fs.writeFileSync(path.join(dir, 'flutter.png'), flPng); r = diff(webPng, flPng, dir); }
  const row = { fixture: fx.name, state, ...r, hasFlutter: !!flPng, hasDiff: r.mismatchPercent != null };
  results.push(row);
  fs.writeFileSync(path.join(dir, 'summary.json'), JSON.stringify(row, null, 1));
  console.log(`${fx.name}/${state}: ${row.mismatchPercent ?? row.note}${row.mismatchPercent != null ? '%' : ''}`);
}

// Run one interaction step (hover | drag), then its `then` steps. Returns captured {state: png}.
async function runStep(page, fx, i, out, last = true) {
  const m = page.mouse;
  if (i.type === 'drag') {
    await m.move(Math.max(0, i.from.x - 20), Math.max(0, i.from.y - 20));
    await m.move(i.from.x, i.from.y, { steps: 2 });
    await m.down();
    await m.move(i.to.x, i.to.y, { steps: i.steps || 10 });
    if (i.captureDuring) { await sleep(400); out[`${i.id}-during`] = await shot(page, fx); }
    await m.up();
  } else {
    await m.move(Math.max(0, i.x - 20), Math.max(0, i.y - 20));
    await m.move(i.x, i.y, { steps: 2 });
  }
  await sleep(800);
  for (const t of i.then || []) await runStep(page, fx, t, out, false);
  if (last) out[i.id] = await shot(page, fx);
}

const sides = [['web', webBase], ...(flBase ? [['flutter', flBase]] : [])];

async function captureFixture(fx) {
  const shots = { web: {}, flutter: {} };
  for (const [side, base] of sides) {
    // each interaction starts from a fresh page load
    const { ctx, page } = await open(side, base, fx);
    await sleep(2500);
    shots[side].static = await shot(page, fx);
    await ctx.close();
    for (const i of fx.interactions || []) {
      const { ctx, page } = await open(side, base, fx);
      await sleep(2500);
      await runStep(page, fx, i, shots[side]);
      await ctx.close();
    }
  }
  const states = Object.keys(shots.web);
  for (const s of states) await record(fx, s, shots.web[s], shots.flutter[s]);

  if (ANIM && fx.captureAnimation) {
    const frames = { web: {}, flutter: {} };
    for (const [side, base] of sides) {
      const { ctx, page } = await open(side, base, fx, true, true);
      // time flows while booting; freeze only once the chart is ready but unmounted
      // pause on a 16 ms boundary: fake rAF fires at multiples of 16, so both sides see the same frame phase
      await page.clock.pauseAt(Math.ceil(((await page.evaluate('Date.now()')) + 50) / 16) * 16);
      await page.evaluate('window.__parityStart()');
      await sleep(200); // real time, clock paused: let React commit + effects register their rAF before frame 0
      // Flutter builds the chart in the next frame, and both libraries latch animation t=0 at the first
      // rAF after mount: run exactly one 16ms frame so "0ms" is the first painted frame of the chart.
      await page.clock.runFor(16);
      // Recharts reaches animation t=0 one rAF after mount (AnimationHandle INIT -> PENDING -> ACTIVE); the
      // Flutter engine mirrors that. WEB_LAG_MS (default 0) shifts web frames if the two ever drift again.
      const lag = side === 'web' ? WEB_LAG_MS : 0;
      let t = 0;
      for (const ms of fx.captureAnimation) {
        if (ms + lag > t) { await page.clock.runFor(ms + lag - t); t = ms + lag; }
        // CSS transitions (Treemap's slide-in) follow the real compositor clock, not the faked one: pin them to
        // the fake time. The transition starts on the frame after t=0, like the JS animations' progress 0.
        if (side === 'web') await page.evaluate((e) => document.getAnimations().forEach((a) => { a.pause(); a.currentTime = e; }), Math.max(0, ms - 16));
        frames[side][ms] = await shot(page, fx);
      }
      await ctx.close();
    }
    for (const ms of fx.captureAnimation) await record(fx, `anim-${ms}ms`, frames.web[ms], frames.flutter[ms]);
  }
}

// Fixtures are independent (own browser contexts), so run a few at once.
// PARITY_CONCURRENCY=1 restores the old one-at-a-time order.
const failures = [];
const CONCURRENCY = Math.max(1, +(process.env.PARITY_CONCURRENCY ?? 4));
const queue = [...fixtures];
await Promise.all(Array.from({ length: Math.min(CONCURRENCY, queue.length) }, async () => {
  while (queue.length) {
    const fx = queue.shift();
    try { await captureFixture(fx); } catch (e) { failures.push(`${fx.name}: ${e.message}`); }
  }
}));
await browser.close();

const animMs = (r) => (r.state.startsWith('anim-') ? parseInt(r.state.slice(5)) : -1);
const worst = {};
for (const r of results) worst[r.fixture] = Math.max(worst[r.fixture] ?? -1, r.mismatchPercent ?? -1);
// worst fixture first; within a fixture, static/interactions by mismatch, then anim frames by time
results.sort((a, b) => (worst[b.fixture] - worst[a.fixture]) || a.fixture.localeCompare(b.fixture)
  || ((animMs(a) >= 0) - (animMs(b) >= 0)) || (animMs(a) >= 0 ? animMs(a) - animMs(b) : (b.mismatchPercent ?? -1) - (a.mismatchPercent ?? -1)));
const scored = results.filter((r) => r.mismatchPercent != null);
const avg = scored.length ? scored.reduce((s, r) => s + r.mismatchPercent, 0) / scored.length : null;
fs.writeFileSync(path.join(outDir, 'summary.json'), JSON.stringify({ averageMismatchPercent: avg, results }, null, 1));

const img = (r, f) => (f === 'flutter' && !r.hasFlutter) || (f === 'diff' && !r.hasDiff)
  ? '<em>n/a</em>' : `<img src="${r.fixture}/${r.state}/${f}.png">`;
fs.writeFileSync(path.join(outDir, 'report.html'), `<!doctype html><meta charset="utf-8"><title>Parity report</title>
<style>body{font:14px sans-serif;margin:16px}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:4px;vertical-align:top}img{width:360px;display:block}</style>
<h1>Recharts parity report</h1>
<p>Average mismatch: <b>${avg == null ? 'n/a (no Flutter captures)' : avg.toFixed(3) + '%'}</b> over ${scored.length} of ${results.length} states (fixtures worst first; animation frames in time order)</p>
<table><tr><th>fixture / state</th><th>mismatch</th><th>web (Recharts)</th><th>flutter</th><th>diff</th></tr>
${results.map((r) => `<tr><td>${r.fixture}<br>${r.state}</td><td>${r.mismatchPercent == null ? 'n/a' : r.mismatchPercent + '%'}</td><td>${img(r, 'web')}</td><td>${img(r, 'flutter')}</td><td>${img(r, 'diff')}</td></tr>`).join('\n')}
</table>`);

console.log('\nmismatch%  fixture/state');
for (const r of results) console.log(String(r.mismatchPercent ?? 'n/a').padStart(9), ' ', r.fixture + '/' + r.state);
console.log(`\naverage: ${avg == null ? 'n/a' : avg.toFixed(3) + '%'}\nreport: ${path.join(outDir, 'report.html')}`);
if (failures.length) {
  console.error(`\nFAILED ${failures.length} fixture(s):\n  ${failures.join('\n  ')}`);
  process.exitCode = 1;
}

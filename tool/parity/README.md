# Recharts visual parity harness

    tool/parity/run.sh [fixture-name-filter] [--anim]

Builds the web renderer (Vite + React + recharts 3.10.1), runs `flutter build web --release --no-web-resources-cdn`
in `example/`, serves both (ports 5180 web, 5181 flutter), runs `capture.mjs`, prints a table.
Output: `out/report.html`, `out/summary.json`, `out/<fixture>/<state>/{web,flutter,diff}.png`.
If the Flutter build fails, web-only captures are still taken (no diff).
Capture: DSF 2, clip = fixture size at (0,0); static waits 2500 ms; hover = two-step mouse move then 800 ms.
`--anim` additionally captures frames for fixtures with `captureAnimation` (ms from chart mount); report rows
are grouped per fixture, animation frames in time order.

## Animation contract (`?fixture=X&anim=1`)
Each side boots and loads fonts but does NOT mount the chart, then sets `window.__parityReady = true` and exposes
`window.__parityStart()` (web: `root.render`; Flutter: `setState` mounting the chart, `example/lib/main.dart`).
Harness: install `page.clock` before navigation (time flows while booting) -> wait for `__parityReady` ->
`clock.pauseAt(now+50)` -> `__parityStart()` -> real 200 ms sleep (React commit/effects, clock frozen) ->
`runFor(16)` (one frame) -> `runFor` to each requested time, screenshot at each.

t=0 alignment: Flutter builds the chart on the first rAF after `setState`; Recharts (JavascriptAnimate) latches
its start time in a rAF requested from an effect after commit. Frames after `__parityStart()` are therefore
counted from the first painted frame (the extra 16 ms `runFor`), and both sides read elapsed time from the same
faked rAF timestamps. Recharts reaches progress 0 one rAF after mount (AnimationHandle goes INIT -> PENDING ->
ACTIVE on successive frames) and the Flutter engine starts its ticker one frame late to match, so both sides are
captured at the same `t`. `WEB_LAG_MS` (env, default 0) shifts the web side if they ever drift apart again.

## Interactions
`interactions: [...]`, each run from a fresh page load, then 800 ms settle, then capture `<id>`.
- hover: `{id,type:"hover",x,y}` (two-step move to x,y).
- drag: `{id,type:"drag",from:{x,y},to:{x,y},steps:12,captureDuring:true}`: move to `from` (2 steps), mouse down,
  move to `to` in `steps` steps, optionally wait 400 ms and capture `<id>-during` with the button held, mouse up,
  wait 800 ms, capture `<id>`. Real pointer events (verified: Flutter tooltip follows the drag).
- any step may carry `then: [step, ...]` (hover or drag); they run in order before the final capture.
The web page disables text selection and focus outlines so drags don't draw selection/focus artifacts.

## Fixtures
`example/assets/parity/fixtures/<name>.json`: `{name, description, width, height, chart:{type, props, children?}, interactions:[...], captureAnimation?}`.
`type` is the exact Recharts component name; `props` use Recharts prop names (JSON only); coordinates are CSS px from the chart's top-left.

## Contract for the Flutter example app
- `?fixture=<name>` renders only that fixture at (0,0), exactly width x height, white background, default text style Roboto 12px black.
- Fixtures load from asset `assets/parity/fixtures/<name>.json`.
- pubspec registers `assets/parity/fixtures/` and font family `Roboto` -> `assets/fonts/Roboto-Regular.ttf` (Roboto 3 classic, OFL; see `OFL.txt`).

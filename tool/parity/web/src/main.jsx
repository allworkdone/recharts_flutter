import React from 'react';
import { createRoot } from 'react-dom/client';
import * as Recharts from 'recharts';

const fixtures = import.meta.glob('../../../../example/assets/parity/fixtures/*.json', { eager: true, import: 'default' });
const byName = Object.fromEntries(Object.values(fixtures).map((f) => [f.name, f]));

const build = (n, key) => {
  const C = Recharts[n.type];
  if (!C) throw new Error('Unknown Recharts component ' + n.type);
  return React.createElement(C, { key, ...n.props }, ...(n.children || []).map((c, i) => build(c, i)));
};

// Drags would otherwise select text and focus-ring the chart; Flutter does neither.
document.head.insertAdjacentHTML('beforeend', '<style>*{user-select:none;-webkit-user-select:none}*:focus,*:focus-visible{outline:none!important}</style>');

const name = new URLSearchParams(location.search).get('fixture');
const fx = byName[name];
const root = createRoot(document.getElementById('root'));
if (!fx) {
  document.body.textContent = 'unknown fixture: ' + name;
} else {
  const { type, props, children } = fx.chart;
  const C = Recharts[type];
  // Load Roboto before the first render: Recharts measures the legend once and
  // ignores later changes under 1px, so a fallback-font measurement sticks.
  const mount = () => {
    root.render(React.createElement(C, { width: fx.width, height: fx.height, ...props }, ...(children || []).map((c, i) => build(c, i))));
    // ponytail: two rAFs so React has committed and the SVG exists
    requestAnimationFrame(() => requestAnimationFrame(() => { window.__parityReady = true; }));
  };
  // anim=1: boot + fonts only; the harness calls __parityStart() to mount (animation t=0).
  const deferred = new URLSearchParams(location.search).get('anim') === '1';
  document.fonts.load('12px Roboto').then(() => {
    if (deferred) { window.__parityStart = mount; window.__parityReady = true; } else mount();
  });
}

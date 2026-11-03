// Parity harness hooks on the web build (see tool/parity/README.md).

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Sets `window.__parityReady = true`.
void signalParityReady() => globalContext.setProperty('__parityReady'.toJS, true.toJS);

/// Exposes [start] as `window.__parityStart()`.
void exposeParityStart(void Function() start) => globalContext.setProperty('__parityStart'.toJS, start.toJS);

// Parity harness hooks off the web: the harness only drives the web build, so
// these do nothing on native platforms.

/// Sets `window.__parityReady = true` on web.
void signalParityReady() {}

/// Exposes [start] as `window.__parityStart()` on web.
void exposeParityStart(void Function() start) {}

#!/usr/bin/env bash
# usage: tool/parity/run.sh [fixture-filter] [--anim]
set -u
cd "$(dirname "$0")"; HERE=$PWD
FILTER=""; EXTRA=""
for a in "$@"; do case "$a" in --anim) EXTRA="--anim";; *) FILTER="$a";; esac; done
WEB_PORT=${WEB_PORT:-5180}; FL_PORT=${FL_PORT:-5181}

[ -d node_modules ] || npm install || exit 1
npx playwright install chromium >/dev/null 2>&1
npx vite build web || exit 1

FL_BASE=none
if (cd ../../example && flutter build web --release --no-web-resources-cdn); then
  FL_BASE=http://localhost:$FL_PORT
else
  echo "!! flutter build web FAILED - continuing with web-only captures"
fi

PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null' EXIT
python3 -m http.server $WEB_PORT -d web/dist >/dev/null 2>&1 & PIDS+=($!)
if [ "$FL_BASE" != none ]; then
  python3 -m http.server $FL_PORT -d ../../example/build/web >/dev/null 2>&1 & PIDS+=($!)
fi
sleep 1
node capture.mjs http://localhost:$WEB_PORT "$FL_BASE" "$FILTER" $EXTRA

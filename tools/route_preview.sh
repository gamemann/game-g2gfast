#!/usr/bin/env bash
# Render one TRACK of a hand-written map from its own spawn, looking down the route.
#
#   tools/route_preview.sh surf_g2g_intro 3
#   tools/route_preview.sh surf_g2g_intro 3 screenshots/fall_line.png
#   tools/route_preview.sh surf_g2g_intro 3 screenshots/fall_line.png 20 14 35
#
# The last two are how far back and how far above the spawn the camera stands, in
# metres. tools/bsp_preview.sh is the whole-map half; this is the per-route one, and a
# bonus route on a map 5,800 units wide is a sliver in that view.
#
# xvfb-run because this needs a rendering context and the machines this runs on have no
# display. `--headless` is NOT a substitute: it saves a frame of nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
id="${1:-surf_g2g_intro}" ; track="${2:-0}"
out="${3:-screenshots/${id}_track${track}.png}"
xvfb-run -a godot --path . --resolution 1600x900 tools/route_preview.tscn \
    -- "$id" "$track" "$out" "${4:-14}" "${5:-9}" "${6:-0}" 2>&1 | grep -E "^\[route\]" || true

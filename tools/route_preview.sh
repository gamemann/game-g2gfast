#!/usr/bin/env bash
# Render one TRACK of a hand-written map from its own spawn, looking down the route.
#
#   tools/route_preview.sh surf_g2g_intro 3
#   tools/route_preview.sh surf_g2g_intro 3 screenshots/fall_line.png
#   tools/route_preview.sh surf_g2g_intro 3 screenshots/fall_line.png 20 14 35
#   tools/route_preview.sh surf_mesa 0 screenshots/mesa.png 14 9 0 walk
#
# `walk` renders one frame per waypoint of the route instead -- the spawn, each stage's
# `!s<n>` arrival (or, on a map with no stages, each door's), and the finish -- facing the
# arrival and facing the next waypoint: `<out>_NN_<waypoint>_{a,b,back}.png`. It is the
# "along its route" half for an imported map, whose route does not run toward -Z.
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
    -- "$id" "$track" "$out" "${4:-14}" "${5:-9}" "${6:-0}" "${7:-}" 2>&1 | grep -E "^\[route\]" || true

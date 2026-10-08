#!/usr/bin/env bash
# Renders the real offline client's Escape menu, help screen and flashlight to screenshots/.
#
#   tools/screenshot_menus.sh [map] [yaw] [pitch]
#
# See tools/screenshot_menus.gd for the frames. xvfb-run because this needs a rendering
# context; `--headless` gives a null renderer and every frame it saves is empty.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
exec xvfb-run -a godot --path . --resolution 1600x900 --script tools/screenshot_menus.gd -- "$@"

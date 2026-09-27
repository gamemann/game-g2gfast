#!/usr/bin/env bash
# Publish imported maps as signed packs under an owner: <owner>/<map id>.
#
#   tools/publish_maps.sh --owner gamemann --key ../dot-server-deploy/keys/content.key
#   tools/publish_maps.sh --owner gamemann --key <pem> --out /tmp/maps surf_mesa
#
# Then upload <out>/ to the content origin's content/ prefix as it stands, and give the
# server `sv_map_content_owner <owner>`. See tools/publish_maps.gd.
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${GODOT:-godot}" --headless --path . --script res://tools/publish_maps.gd -- "$@"

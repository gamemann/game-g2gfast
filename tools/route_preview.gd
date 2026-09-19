extends Node3D

const G2GMapCatalogue := preload("../game/g2g_map_catalogue.gd")

## Renders ONE TRACK of a hand-written map, from its own spawn, looking down the route.
##
## [b]`tools/bsp_preview.sh` renders a whole map and that is the wrong frame for a
## bonus.[/b] It orbits the world AABB, so on a map whose four routes are spread over
## 5,800 units of X every route is a sliver and the one that was just built is
## indistinguishable from the three that were not. A route is read from its start line
## looking down it, which is where a player reads it from, and that is the only view
## that answers "can somebody see where to go".
##
##     tools/route_preview.sh surf_g2g_intro 3
##     tools/route_preview.sh surf_g2g_intro 3 screenshots/fall_line.png
##
## xvfb-run, not `--headless`: a null renderer saves a frame of nothing, which is worse
## than no screenshot because it looks like one.

const CHANNEL := "g2g.preview"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "surf_g2g_intro"
	var track := int(args[1]) if args.size() > 1 else 0
	var out := args[2] if args.size() > 2 else "screenshots/%s_track%d.png" % [id, track]
	var back := float(args[3]) if args.size() > 3 else 14.0
	var up := float(args[4]) if args.size() > 4 else 9.0
	# How far below horizontal to aim. A route that descends at 50° is invisible from a
	# camera looking along the horizon — it is BEHIND the start pad from there — which
	# is the whole difference between a frame that shows a route and a frame that shows
	# a pad with some sky over it.
	var aim := float(args[5]) if args.size() > 5 else 0.0

	var catalogue := G2GMapCatalogue.discover()
	var def := catalogue.get_map(StringName(id))
	if def == null:
		push_error("no map '%s'" % id)
		get_tree().quit(1)
		return

	var packed: PackedScene = load(def.scene_path)
	var map: Node3D = packed.instantiate()
	add_child(map)
	await get_tree().process_frame

	# The spawn is where a player is put and the route runs away from it; every route
	# in this game runs toward -Z, which is what yaw 0 means. Standing back and above
	# it is what makes the descent readable rather than a wall of texture.
	var spawn: Vector3 = map.call("spawn_for", track)
	var eye := spawn + Vector3(0.0, up, back)

	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 8192.0
	add_child(camera)
	camera.global_position = eye
	var reach := 60.0
	camera.look_at(
		spawn + Vector3(0.0, -reach * tan(deg_to_rad(aim)), -reach), Vector3.UP
	)
	camera.make_current()

	# Two frames: the first is drawn before the map's own lighting has been applied.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var path := out if out.begins_with("res://") or out.begins_with("user://") else out
	image.save_png(path)
	print("[route] %s track %d from %s -> %s" % [id, track, spawn, path])
	get_tree().quit(0)

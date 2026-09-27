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

# No `CHANNEL`: a one-shot CLI whose output is its stdout line and its PNG; the one
# failure is a bad argument, which `push_error` hands the person who typed it.


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
	# An imported map is one scene pointed at a manifest, and it builds only when told
	# which: without this the frame is the sky and nothing else.
	if map.has_method("build_from"):
		map.call("build_from", def)
	add_child(map)
	await get_tree().process_frame

	if args.size() > 6 and args[6] == "walk":
		await _walk(map, id, track, out)
		get_tree().quit(0)
		return

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


## `walk`: one frame per waypoint of the track's route, as a player arriving there sees it.
##
## An imported map's route does not run toward -Z, and one frame from its spawn says
## nothing about the other ninety percent of it. The waypoints are the ones the map
## itself defines -- the spawn, each stage's `!s<n>` destination in order, and the
## finish -- so the frames are the route the timer times. At each, two frames: facing the
## way the map faces an arriving player (`_a`), and facing the next waypoint (`_b`),
## which is the one that shows whether the way on can be seen at all.
func _walk(map: Node3D, id: String, track: int, out: String) -> void:
	var zones: DotTimerZoneSet = map.call("timer_zones")
	var points: Array[Vector3] = []
	var yaws: Array[float] = []
	var names: Array[String] = []
	points.append(map.call("spawn_for", track))
	yaws.append(float(map.call("spawn_yaw_for", track)))
	names.append("spawn")
	if zones != null:
		for n in range(1, zones.stage_count(track) + 1):
			var st := zones.stage_zone(track, n)
			if st == null:
				continue
			points.append(st.destination if st.destination != Vector3.ZERO else st.centre())
			yaws.append(st.destination_yaw)
			names.append("s%d" % n)
		# A map with no stages is a chain of teleport doors (surf_mesa is five ramps
		# joined by them), and their arrivals are the only route it states. Their order
		# is not written anywhere, so it is walked nearest-first from the spawn -- a
		# guess, but one that only decides which frame is numbered first.
		if zones.stage_count(track) == 0:
			var doors: Array[DotTimerZone] = []
			for z: DotTimerZone in zones.of_kind(DotTimerZone.Kind.TELEPORT, track):
				var seen := false
				for d: DotTimerZone in doors:
					seen = seen or d.destination.distance_to(z.destination) < 1.0
				if not seen and z.destination.distance_to(points[0]) > 1.0:
					doors.append(z)
			var here: Vector3 = points[0]
			while not doors.is_empty():
				var best := 0
				for k in range(doors.size()):
					if doors[k].destination.distance_to(here) < doors[best].destination.distance_to(here):
						best = k
				here = doors[best].destination
				points.append(here)
				yaws.append(doors[best].destination_yaw)
				names.append("door%d" % points.size())
				doors.remove_at(best)
		var end := zones.first_of_kind(DotTimerZone.Kind.END, track)
		if end != null:
			# At the finish's floor, not its centre: a finish volume is often tall, and
			# its centre is inside whatever roof is over it.
			var c := end.centre()
			points.append(Vector3(c.x, c.y - end.size().y * 0.5, c.z))
			yaws.append(INF)
			names.append("end")

	var camera := Camera3D.new()
	camera.fov = 90.0
	camera.far = 8192.0
	add_child(camera)
	camera.make_current()
	for i in range(points.size()):
		var at: Vector3 = points[i] + Vector3(0.0, 1.6, 0.0)
		# The last one faces the way the rider was travelling, then back the way they came.
		var toward: Vector3 = points[i + 1] if i + 1 < points.size() \
			else points[i] * 2.0 - points[max(i - 1, 0)]
		var frames := []
		if is_finite(yaws[i]):
			frames.append(["a", Vector3(-0.12, deg_to_rad(yaws[i]), 0.0)])
		elif i > 0:
			var back := points[i - 1] - at
			frames.append(["back", Vector3(-0.12, atan2(-back.x, -back.z), 0.0)])
		var d := toward - at
		var flat := Vector2(d.x, d.z).length()
		if d.length() > 0.5:
			# Pitch clamped to 50 degrees: a finish directly below is still a frame of
			# something rather than of one's own feet.
			var pitch := clampf(atan2(d.y, maxf(flat, 0.01)), deg_to_rad(-50.0), deg_to_rad(30.0))
			frames.append(["b", Vector3(pitch, atan2(-d.x, -d.z), 0.0)])
		for f: Array in frames:
			camera.global_position = at
			camera.rotation = f[1]
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := out.replace(".png", "_%02d_%s_%s.png" % [i, names[i], f[0]])
			get_viewport().get_texture().get_image().save_png(path)
			print("[route] %s track %d %s at %s -> %s" % [id, track, names[i], points[i], path])

extends Node

const G2GBspMap := preload("../game/g2g_bsp_map.gd")
const G2GConfig := preload("../game/g2g_config.gd")
const G2GGame := preload("../game/g2g_game.gd")
const G2GPlayer := preload("../game/g2g_player.gd")
const G2GUnits := preload("../game/g2g_units.gd")

## Checks a map imported from a Source .bsp: it loads, it is the right size, it is
## lit, and — the only question that matters — a player put on it stays on it.
##
## [codeblock]
## godot --headless --path . res://examples/headless_imported.tscn
## [/codeblock]
##
## [b]Why collision is the check and geometry is not.[/b] Every number about an
## imported map can be right while the map is unplayable: the vertex count, the
## bounds, the material list and the manifest all pass if the triangles are wound
## inside out or the collision body was never built, and a player then falls through
## a map that renders perfectly. This file's own repeated lesson — a value produced
## correctly and consumed by nothing — reaches imported geometry through collision.
##
## Skips rather than fails when nothing has been imported: `maps/imported/` is
## optional content and a clone that has never run the importer is not broken.

## The imported maps that are deliberately NOT courses, and why each one is not.
##
## [b]This suite asserted that every imported map is runnable, and `maps/zones/README.md`
## says in so many words that three of them are not.[/b] The check and the decision
## contradicted each other for as long as both existed, and the suite was the one that was
## wrong: it had been exiting 1 on three maps that are behaving exactly as documented.
##
## - `buses_from_hell_fixed` is a vehicle map. No teleports, no destinations, eight
##   `func_rotating` and a `game_ui` — there is no route to time.
## - `bhop_eazy` and `bhop_lego2` are section-chain maps (`t11`..`t2727`, `s_1`..`s_30`)
##   whose sections are all labelled and whose END is not. Nothing in either file
##   distinguishes the last gate from the twenty-six before it, and guessing would produce a
##   leaderboard that looks right and measures a route the map does not have.
##
## [b]The exemption is checked in both directions, which is what stops it being a mute
## button.[/b] A map in here that turns out to HAVE a runnable main track fails — because
## the reason it is listed has stopped being true and the list is now the lie. That is the
## same bargain every skip in this family makes: it is allowed to skip a check, it is not
## allowed to stop asking the question.
const NOT_COURSES := ["buses_from_hell_fixed", "bhop_eazy", "bhop_lego2"]

## The imported maps with no pit, which is a different question from having no finish.
##
## [b]A separate list of one, rather than reusing [constant NOT_COURSES], and the difference
## is the whole point.[/b] A surf or bhop map's `trigger_teleport` volumes ARE its pit, and
## losing them means a player who falls off falls for ever. `bhop_eazy` and `bhop_lego2`
## have pits and are checked for them; only `buses_from_hell_fixed` has none, because a
## vehicle map has nothing to fall off. Folding the two lists together would stop asking two
## maps a question they currently answer correctly, which is how an exemption quietly grows.
const NO_PIT := ["buses_from_hell_fixed"]

## Arrivals on these maps that DO land inside a pit on their own track, by label.
##
## [b]Known, not accepted.[/b] Each is a different fault the importer does not yet
## understand, written down so the check below can be asserted on every other map while
## these are worked through (`[arrive-1]` in the nightly list):
##
## - `surf_summit` stage 3 is put on a floor-level plane 6,272 by 4,224 units that sends
##   a player to the map start -- the destination is the checkpoint trigger's floor, and
##   that trigger reaches down to the plane.
## - `surf_greensway` stage 2 and `surf_mesa`'s door land inside teleport brushes 2,000
##   to 4,000 units across whose boxes are almost certainly wider than the brushes: a
##   wedge under a ramp has a bounding box over the ramp.
##
## All three are inside the MAPPER's trigger, not inside thickness this importer added --
## `clear_arrivals` in `tools/bsp_import.py` trims that, and it is what took
## `surf_aquaflow` stage 2 off this list.
##
## Asserted both ways, like [constant NOT_COURSES]: a map in here whose arrival stops
## landing in a pit fails, so the list cannot outlive its reason.
const ARRIVES_IN_PIT := {
	"surf_summit": ["stage 3"],
	"surf_greensway": ["stage 2"],
	"surf_mesa": ["door"],
}

## Checks every map gets. Tracks and stages add one each on top — see [member _expected].
const CHECKS_PER_MAP := 28

## A script error inside a test aborts THAT TEST and not the run, so a suite that has
## quietly lost two checks still prints "0 failed" — which is what happened while this
## file was being written, to the zone section. The count is asserted, not trusted.
var _expected := 0
var _map_id: StringName = &""

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var game: G2GGame = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("g2gfast — imported map")
	print("")

	# Every map under maps/imported/, not one this file names. A suite with its own
	# copy of the list is the bug the discovery in G2GGame exists to avoid.
	var ids := _imported_ids()
	if ids.is_empty():
		print("nothing in maps/imported/ — nothing to check")
		print("  tools/bsp_import.py <a .bsp> maps/imported --id <name>")
		get_tree().quit(0)
		return

	for id in ids:
		_map_id = id
		_expected += CHECKS_PER_MAP
		print("=== %s" % id)
		await _test_loads("res://maps/imported/%s/%s.json" % [id, id])
		await _test_geometry()
		await _test_lighting()
		_test_zones()
		_test_runnable()
		await _test_stands_on_it()
		await _test_stands_where_it_sends_you()
		_test_arrivals_miss_the_pits()
		_test_a_door_keeps_the_run()
		if game != null:
			game.queue_free()
			game = null
			await get_tree().process_frame

	print("")
	if _passed + _failed != _expected:
		_failed += 1
		_failures.append("the suite ran %d checks and should run %d — one aborted"
			% [_passed + _failed, _expected])
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	get_tree().quit(1 if _failed > 0 else 0)


func _imported_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open("res://maps/imported")
	if dir == null:
		return out
	for id in dir.get_directories():
		if FileAccess.file_exists("res://maps/imported/%s/%s.json" % [id, id]):
			out.append(StringName(id))
	out.sort()
	return out


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append("%s%s" % [what, "" if detail.is_empty() else "  (%s)" % detail])
		print("  FAIL  %s%s" % [what, "" if detail.is_empty() else "  (%s)" % detail])


func _test_loads(manifest_path: String) -> void:
	print("loading")
	var config := G2GConfig.new()
	config.records_directory = ""
	config.map_seconds = 0.0
	config.initial_map = _map_id

	game = G2GGame.new()
	game.config = config
	add_child(game)
	for _i in range(120):
		await get_tree().process_frame
		if game.maps != null and game.maps.current != null:
			break

	_check(game.maps != null and game.maps.current != null and game.maps.current.id == _map_id,
		"the imported map is in the catalogue and loads")
	# Discovery, not a list. If this fails the map was found by something naming it.
	_check(FileAccess.file_exists(manifest_path), "its manifest is beside it")


func _test_geometry() -> void:
	print("geometry")
	var node := game.current_map_node()
	_check(node is G2GBspMap, "the map node is a G2GBspMap")
	var mi := node.get_node_or_null("World") as MeshInstance3D
	_check(mi != null and mi.mesh != null, "it built a mesh")
	if mi == null or mi.mesh == null:
		return
	var mesh := mi.mesh
	_check(mesh.get_surface_count() > 1, "with a surface per material",
		"%d surfaces" % mesh.get_surface_count())

	# Every surface the manifest lists is drawn, across however many instances it took.
	# A mesh holds 256 and `bhop_monster_jam` has 311: in one mesh the last 55 were
	# refused by the engine and the map was drawn with holes in it while every
	# collision and standing check passed, because collision is built from the brushes.
	var drawn := 0
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("World") \
				and (child as MeshInstance3D).mesh != null:
			drawn += (child as MeshInstance3D).mesh.get_surface_count()
	var listed: int = (node as G2GBspMap).manifest.get("surfaces", []).size()
	_check(drawn == listed, "and every surface the manifest lists is drawn",
		"%d of %d" % [drawn, listed])

	var verts := 0
	var has_uv2 := true
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if arrays[Mesh.ARRAY_TEX_UV2] == null:
			has_uv2 = false
	_check(verts > 1000, "and real geometry", "%d verts" % verts)
	# UV2 is the whole reason this is not a glTF import. If it is gone the map is lit
	# by whatever texel the atlas happens to have at (0,0).
	_check(has_uv2, "and a second UV set on every surface, for the baked lighting")

	var aabb := mi.get_aabb()
	var units := aabb.size / G2GUnits.METRES_PER_UNIT
	# Source's own limit is +/-16384 units, so a map is at most 32768 across. Ten
	# times that means the unit ratio was applied twice or not at all -- the one
	# mistake that makes an imported map silently unplayable rather than wrong.
	# The LONGEST side, not x: bhop_grove is one corridor 704 units across and 32,192
	# long, and asking its x of the unit ratio failed a map that is exactly right.
	var longest := maxf(units.x, maxf(units.y, units.z))
	_check(longest > 1000.0 and longest < 40000.0,
		"and is the size a Source map can be", "%.0f x %.0f x %.0f units" % [units.x, units.y, units.z])


func _test_lighting() -> void:
	print("lighting")
	var node := game.current_map_node() as G2GBspMap
	var lm: Dictionary = node.manifest.get("lightmap", {})
	var path: String = "res://maps/imported/%s/%s" % [_map_id, lm.get("file", "")]
	_check(ResourceLoader.exists(path), "the baked lightmap atlas is an imported resource", path)

	var mi := node.get_node_or_null("World") as MeshInstance3D
	var mat := mi.get_surface_override_material(0) as ShaderMaterial if mi != null else null
	_check(mat != null, "surfaces carry a ShaderMaterial")
	if mat == null:
		return
	_check(mat.get_shader_parameter("lightmap_tex") is Texture2D,
		"and the atlas is bound to every one of them")


func _test_zones() -> void:
	print("zones")
	var zones := game.timers.zones
	_check(zones != null, "the map produced a zone set")
	if zones == null:
		return
	_check(zones.problems().is_empty(), "which is well formed", ", ".join(zones.problems()))
	var respawns := zones.of_kind(DotTimerZone.Kind.RESPAWN).size()
	# A surf map's trigger_teleport volumes are its pit. Losing them means a player
	# who falls off falls for ever, which is the bug dot-timer's effect_requested was.
	if NO_PIT.has(_map_id):
		_check(respawns == 0, "has no pit, and still has none",
			"listed in NO_PIT; %d respawn zones" % respawns)
	else:
		_check(respawns > 0, "with the pit volumes carried across as RESPAWN zones",
			"%d respawn zones" % respawns)

	# Source sweeps its trigger tests; dot-timer samples a point per tick. A pit drawn
	# as a 16-unit plane -- which is how every one of them is drawn, because in Source
	# that is enough -- is stepped clean over by a player falling at genre speed, and
	# they then fall for ever. 48 of surf_kitsune's 53 were that thin on import.
	var thin := zones.thin_zones(G2GUnits.to_metres(3500.0), game.tick_rate)
	_check(thin.is_empty(), "and no zone a 3500 u/s player passes through between ticks",
		"%d thin" % thin.size())

	# The two zones without which a map is scenery. Every one of these maps had them
	# in its entity lump or in maps/zones/ before it was offered as a level; a map
	# that reaches here without them is one the importer stopped reading.
	var tracks := zones.playable_tracks()

	if NOT_COURSES.has(_map_id):
		# Asserted the other way round. See [constant NOT_COURSES]: if this map has grown a
		# finish, the list is out of date and that is worth a failure, because the next
		# person to read it would believe it.
		_check(not tracks.has(DotTimerTrack.MAIN),
			"is not a course, and still is not",
			"listed in NOT_COURSES; runnable tracks: %s" % str(tracks))
	else:
		_check(tracks.has(DotTimerTrack.MAIN),
			"the main track has both a start line and a finish",
			"runnable tracks: %s" % str(tracks))

	# A track a player cannot be put on is a track nobody plays. `spawn_for` falls
	# back to `fallback_spawn_units` for a missing one, which is the main track's
	# spawn -- so a bonus with no spawn of its own silently starts at the map's start,
	# and looks like a bonus that does not work rather than like a missing zone.
	var without := PackedStringArray()
	for track in tracks:
		if zones.first_of_kind(DotTimerZone.Kind.SPAWN, track) == null:
			without.append(DotTimerTrack.name_of(track))
	_check(without.is_empty(), "and every runnable track has somewhere to spawn",
		", ".join(without))


func _test_runnable() -> void:
	print("runnable")
	var zones := game.timers.zones
	if zones == null:
		_check(false, "a run can be started, split and finished")
		_check(false, "and its stages come out in order")
		return

	# [b]Drive the timer over the map's own zones and see a time come out.[/b] Every
	# other check here is about a zone existing; this is the only one about the zones
	# adding up to a run. A start with no reachable finish, a stage numbered past the
	# end, a finish inside the start -- all of them pass `problems()` and none of them
	# produces a time.
	var timer := DotTimer.new()
	timer.bind(zones, game.tick_rate)
	var finished: Array[DotTimerRun] = []
	timer.run_finished.connect(func(run: DotTimerRun) -> void: finished.append(run))

	var start := zones.first_of_kind(DotTimerZone.Kind.START, DotTimerTrack.MAIN)
	var finish := zones.first_of_kind(DotTimerZone.Kind.END, DotTimerTrack.MAIN)

	if NOT_COURSES.has(_map_id):
		# Both checks still run and still count; what changes is what the right answer is.
		# See [constant NOT_COURSES] — a map listed there that grows a finish is a list that
		# has gone stale, and the failure is how anybody finds out.
		_check(start == null or finish == null,
			"has no run to time, as documented",
			"listed in NOT_COURSES")
		_check(true, "and no stages to order")
		return

	if start == null or finish == null:
		_check(false, "a run can be started, split and finished", "no start or no end")
		_check(false, "and its stages come out in order")
		return

	# [b]A tick outside every zone, between the start and everything after it.[/b] The
	# run begins on the tick the player LEAVES the start line, and that happens after
	# the zone handling for the same tick -- so a route that steps straight from the
	# start into the first stage arrives while the run is still IDLE and the split is
	# dropped. It is an artifact of stepping a timer by hand rather than walking a
	# map, and it cost every staged map here exactly one split until the gap was put
	# back in.
	var bounds: Dictionary = (game.current_map_node() as G2GBspMap).manifest.get("bounds", {})
	var away := G2GUnits.vector_to_metres(Vector3(
		float((bounds.get("max", [0, 0, 0]) as Array)[0]),
		float((bounds.get("max", [0, 0, 0]) as Array)[1]),
		float((bounds.get("max", [0, 0, 0]) as Array)[2]))) + Vector3(0.0, 128.0, 0.0)

	# From stage 2, because stage 1 IS the start line on every map that numbers its
	# own stages -- and stepping back into the start zone mid-route makes the timer do
	# what it should: treat leaving it again as a new attempt, wiping the splits.
	var route: Array[Vector3] = [start.centre(), start.centre(), away]
	for n in range(2, zones.stage_count(DotTimerTrack.MAIN) + 1):
		var stage := zones.stage_zone(DotTimerTrack.MAIN, n)
		if stage != null:
			route.append(stage.centre())
	route.append(finish.centre())

	var sample := DotTimerSample.new()
	for point in route:
		sample.previous_position = sample.position
		sample.position = point
		sample.grounded = true
		timer.tick(sample)

	_check(finished.size() == 1, "a run can be started, split and finished",
		"%d finishes" % finished.size())
	if finished.is_empty():
		_check(false, "and its stages come out in order")
		return

	# Stage 1 is the start line, and a run begins by LEAVING it -- so its split is the
	# one that legitimately never arrives. Every stage after it must.
	var wanted := maxi(0, zones.stage_count(DotTimerTrack.MAIN) - 1)

	var got := 0
	for n in range(2, zones.stage_count(DotTimerTrack.MAIN) + 1):
		if finished[0].splits.has(n):
			got += 1
	_check(got == wanted, "and its stages come out in order",
		"%d of %d splits" % [got, wanted])


func _test_stands_on_it() -> void:
	print("collision")
	var node := game.current_map_node()
	# Anywhere under the map, not under the MeshInstance3D. The solid used to BE the
	# mesh -- `create_trimesh_collision()` parents a `World_col` to it -- and it is not
	# any more: it is built from the .bsp's brushes, which is a different set of
	# geometry from the drawn faces and belongs to the map rather than to the drawing of
	# it. The old shape is still what a pre-collision manifest falls back to, so this
	# has to find both.
	var body: Node = null
	for c in node.find_children("*", "StaticBody3D", true, false):
		body = c
		break
	_check(body is StaticBody3D, "the world has a static body")
	var shape_count := 0
	if body != null:
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				shape_count += 1
	_check(shape_count > 0, "with a collision shape on it", "%d shapes" % shape_count)

	var bot := game.add_player(&"bot", "Bot", true)
	_check(bot != null, "a player joins")
	if bot == null:
		return
	bot.sampler = null

	var start := node.spawn_for(0)
	await get_tree().physics_frame
	_check(bot.global_position.distance_to(start) < 2.0, "at the map's own spawn",
		"%.1f m away" % bot.global_position.distance_to(start))

	# Let it fall. On a map whose collision never got built this is the only check in
	# the file that fails, and it fails by hundreds of metres rather than marginally.
	var floor_y := start.y
	for _i in range(180):
		await get_tree().physics_frame
	var drop := floor_y - bot.global_position.y
	_check(drop < 8.0, "and is still standing on the map three seconds later",
		"fell %.1f m" % drop)

	var bounds: Dictionary = (node as G2GBspMap).manifest.get("bounds", {})
	var min_y: float = float((bounds.get("min", [0, -16384, 0]) as Array)[1]) * G2GUnits.METRES_PER_UNIT
	_check(bot.global_position.y > min_y, "and has not left the world",
		"y=%.1f, world floor %.1f" % [bot.global_position.y, min_y])


## Every place the map can put a player: each track's spawn, and each `!s<n>`.
##
## [b]A destination is the one field nothing else checks.[/b] `DotTimerManager`
## resolves "go to stage 3" to a zone's [member DotTimerZone.destination] and hands it
## to the host, which teleports; a destination that is in the sky, inside a wall, or
## left at the origin succeeds at every step and drops the player out of the world.
## Standing on it for a second is the whole test, and it is the same test as the one
## above with somewhere else to stand.
func _test_stands_where_it_sends_you() -> void:
	print("destinations")
	var node := game.current_map_node()
	var zones := game.timers.zones
	var spots: Array = []
	if zones != null:
		for track in zones.playable_tracks():
			var spawn := zones.first_of_kind(DotTimerZone.Kind.SPAWN, track)
			if spawn != null:
				spots.append([DotTimerTrack.short_name_of(track) + " spawn", spawn.destination])
			for n in range(1, zones.stage_count(track) + 1):
				var stage := zones.stage_zone(track, n)
				if stage != null:
					spots.append(["stage %d" % n, stage.destination])
	_expected += spots.size()

	var bot: G2GPlayer = game.players.get(&"bot")
	if bot == null:
		bot = game.add_player(&"bot", "Bot", true)
		bot.sampler = null
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		bot.teleport(at, 0.0)
		for _i in range(90):
			await get_tree().physics_frame
		var drop := at.y - bot.global_position.y
		_check(drop < 8.0, "%s is somewhere a player can stand" % spot[0],
			"fell %.1f m from %s" % [drop, str(at / G2GUnits.METRES_PER_UNIT)])


## Every place the map puts a player -- a spawn, a stage, the far side of a door -- is
## outside every pit on that track.
##
## [b]A pit that contains its own arrival is a loop nobody can see from the zone list.[/b]
## A respawn fires on ENTRY, so a player put inside one is sent back to the start the
## first time they move -- which from the player's side is a `!s2` that does nothing and
## a stage nobody can reach. bhop_pandora2_fix spawned every player inside its first pit
## because the importer thickened a 16-unit plane 48 units under the start room into a
## 192-unit slab reaching up through the floor; `tools/bsp_import.py` `inflate_pit` is the
## fix and this is the check that fails without it. `_test_stands_where_it_sends_you`
## could not see it: it teleports a bot to each arrival and measures how far it FELL,
## and a bot the pit put back at a higher spawn has fallen a negative distance.
func _test_arrivals_miss_the_pits() -> void:
	print("arrivals")
	var zones := game.timers.zones
	var inside := PackedStringArray()
	if zones != null:
		var pits := zones.of_kind(DotTimerZone.Kind.RESPAWN)
		for zone: DotTimerZone in zones.zones:
			var label := ""
			match zone.kind:
				DotTimerZone.Kind.SPAWN:
					label = "%s spawn" % DotTimerTrack.short_name_of(zone.track)
				DotTimerZone.Kind.STAGE:
					label = "stage %d" % int(zone.number)
				DotTimerZone.Kind.TELEPORT:
					label = "door"
				_:
					continue
			for pit: DotTimerZone in pits:
				if pit.track == zone.track and pit.contains(zone.destination):
					if not inside.has(label):
						inside.append(label)
					break
	var known: Array = ARRIVES_IN_PIT.get(String(_map_id), [])
	if known.is_empty():
		_check(inside.is_empty(), "no spawn, stage or door puts a player inside a pit",
			", ".join(inside))
	else:
		# Both ways: the listed ones still do, and nothing else does.
		var listed := PackedStringArray(known)
		_check(inside == listed,
			"lands in a pit exactly where ARRIVES_IN_PIT says it does",
			"listed %s, found %s" % [str(listed), str(inside)])


## Walking through one of the map's doors does not end the run.
##
## [b]`doorways` in a map's zone file exists so that a door is a TELEPORT, which keeps
## the run, rather than a RESPAWN, which ends it -- and the game's handler for TELEPORT
## called `G2GPlayer.teleport`, which ends it.[/b] So every door the importer ever
## made ended the run anyway, on surf_kitsune (the map the rule was written for), on
## bhop_interloper's three parts, on bhop_badges_mini's hundred and eighty sections. The
## zone list was exactly right and the only symptom was a timer that stopped at the
## first door. Driven through the real handler: the manager's signal, which is what the
## timer emits when a player walks in.
func _test_a_door_keeps_the_run() -> void:
	print("doors")
	var zones := game.timers.zones
	var door: DotTimerZone = null
	var start: DotTimerZone = null
	if zones != null:
		door = zones.first_of_kind(DotTimerZone.Kind.TELEPORT, DotTimerTrack.MAIN)
		start = zones.first_of_kind(DotTimerZone.Kind.START, DotTimerTrack.MAIN)
	if door == null or start == null:
		_check(true, "a door keeps the run", "no door on the main track")
		return

	var bot: G2GPlayer = game.players.get(&"bot")
	if bot == null:
		bot = game.add_player(&"bot", "Bot", true)
		bot.sampler = null
	var timer := bot.timer
	if timer == null:
		_check(false, "a door keeps the run", "the bot has no timer")
		return
	timer.stop()

	# Leave the start line, so there is a run to lose. Synchronously, inside one frame,
	# so the game's own tick cannot feed the timer the bot's real position in between.
	var sample := DotTimerSample.new()
	sample.grounded = true
	var away := start.centre() + Vector3(0.0, start.size().y + 8.0, 0.0)
	for point in [start.centre(), start.centre(), away]:
		sample.previous_position = sample.position
		sample.position = point
		timer.tick(sample)
	var was_running := timer.run.is_running()

	game.timers.effect_requested.emit(&"bot", door)

	var moved := bot.global_position.distance_to(door.destination) < 0.01
	_check(was_running and moved and timer.run.is_running(), "a door keeps the run",
		"running before %s, moved %s, running after %s"
		% [was_running, moved, timer.run.is_running()])
	timer.stop()

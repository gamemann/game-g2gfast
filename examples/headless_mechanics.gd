extends Node

const G2GBspMap := preload("../game/g2g_bsp_map.gd")
const G2GConfig := preload("../game/g2g_config.gd")
const G2GGame := preload("../game/g2g_game.gd")
const G2GMapMechanics := preload("../game/g2g_map_mechanics.gd")
const G2GPlayer := preload("../game/g2g_player.gd")
const G2GUnits := preload("../game/g2g_units.gd")

## What an imported map's brush entities do, asked of every imported map with a player on
## it: where each teleport sends you, whether a sinking block takes you off it (and only
## you, and only if you stay), whether a push pushes, and whether water is swum in.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mechanics.tscn [-- <map> ...]
## [/codeblock]
##
## [b]Why its own suite.[/b] `headless_imported` asks whether a map is a level: it loads,
## it is lit, a run can be timed, the spawns and stages stand. This asks whether the map
## does what its triggers say, which is the half Christian's bhop_evolve and bhop_eazy
## footage found broken (2026-10-08): every pit sent a runner back to the start, every
## gate between sections did the same, nothing sank, nothing pushed, and water was air.
## None of that fails a check about a zone set, because a zone set where every pit sends
## you to the spawn is a perfectly valid zone set.
##
## Each section samples at most [constant SAMPLE] volumes per map, evenly through the
## list, so a map with four hundred pits costs what one with forty does and every run
## samples the same ones.
##
## Counts sections entered against sections finished AND its checks against the count it
## planned, for the reason every suite here does.

const SAMPLE := 12

## Pits whose destination is known to be somewhere a player cannot stand, by map: the
## mapper's own `info_teleport_destination` in a wall or over nothing. Asserted both ways
## (a listed map whose destinations all stand fails), so the list cannot outlive its
## reason. Filled from this suite's own first run.
const DESTINATIONS_THAT_FALL := {}

var game: G2GGame = null
var _map_id: StringName = &""
var _passed := 0
var _failed := 0
var _failures: PackedStringArray = PackedStringArray()
var _entered := 0
var _completed := 0
var _planned := 0
var _falls: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("g2gfast — what an imported map's brush entities do")
	var ids := _imported_ids()
	if ids.is_empty():
		print("nothing in maps/imported/ — nothing to check")
		get_tree().quit(0)
		return

	var sections := 0
	for id in ids:
		_map_id = id
		print("=== %s" % id)
		await _load(id)
		if game == null or game.maps.current == null or game.maps.current.id != id:
			_check(false, "%s loads" % id)
			continue
		_planned += 1
		_check(true, "%s loads" % id)
		await _test_pits()
		await _test_pit_keeps_the_run()
		await _test_blocks()
		await _test_pushes()
		await _test_water()
		sections += 5
		game.queue_free()
		game = null
		await get_tree().process_frame

	print("")
	print("pits that do not stand, by map (for DESTINATIONS_THAT_FALL):")
	for id: String in _falls:
		print("  %s: %s" % [id, str(_falls[id])])
	if _passed + _failed != _planned:
		_failed += 1
		_failures.append("ran %d checks, planned %d -- one aborted" % [_passed + _failed, _planned])
	print("%d passed, %d failed, %d of %d sections ran to their last line" % [
		_passed, _failed, _completed, _entered])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _entered != sections or _completed != _entered:
		print("ERROR: %d sections entered, %d completed, %d expected" % [_entered, _completed, sections])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _imported_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open("res://maps/imported")
	if dir == null:
		return out
	var only := OS.get_cmdline_user_args()
	for id in dir.get_directories():
		if not only.is_empty() and not only.has(id):
			continue
		if FileAccess.file_exists("res://maps/imported/%s/%s.json" % [id, id]):
			out.append(StringName(id))
	out.sort()
	return out


func _section(title: String) -> void:
	_entered += 1
	print(title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	var line := "%s: %s%s" % [_map_id, what, "" if detail.is_empty() else "  (%s)" % detail]
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(line)
		print("  FAIL  %s%s" % [what, "" if detail.is_empty() else "  (%s)" % detail])


func _load(id: StringName) -> void:
	var config := G2GConfig.new()
	config.records_directory = ""
	config.map_seconds = 0.0
	config.initial_map = id
	config.map_rotation_file = ""
	game = G2GGame.new()
	game.config = config
	add_child(game)
	for _i in range(120):
		await get_tree().process_frame
		if game.maps != null and game.maps.current != null:
			break


func _bot() -> G2GPlayer:
	var bot: G2GPlayer = game.players.get(&"bot")
	if bot == null:
		bot = game.add_player(&"bot", "Bot", true)
		bot.sampler = null
	return bot


static func _sample(list: Array, n: int) -> Array:
	if list.size() <= n:
		return list
	var out: Array = []
	for i in n:
		out.append(list[int(float(i) * float(list.size()) / float(n))])
	return out


func _u(v: Vector3) -> String:
	var u := G2GUnits.vector_to_units(v)
	return "(%d %d %d)" % [roundi(u.x), roundi(u.y), roundi(u.z)]


## Every pit with a destination puts a player somewhere they stay: they land, they are
## not caught by a pit on landing, and they do not fall away.
func _test_pits() -> void:
	_section("teleports")
	var zones := game.timers.zones
	var pits: Array = []
	var dests := {}
	if zones != null:
		for zone: DotTimerZone in zones.of_kind(DotTimerZone.Kind.RESPAWN):
			if zone.payload.has(G2GBspMap.SENDS_TO):
				var key := _u(zone.destination)
				if not dests.has(key):
					dests[key] = zone
	pits = _sample(dests.values(), SAMPLE)
	var total_pits := zones.of_kind(DotTimerZone.Kind.RESPAWN).size() if zones != null else 0
	var sending := 0
	if zones != null:
		for z: DotTimerZone in zones.of_kind(DotTimerZone.Kind.RESPAWN):
			if z.payload.has(G2GBspMap.SENDS_TO):
				sending += 1
	_planned += 1
	_check(total_pits == 0 or sending * 2 >= total_pits,
		"most pits send a player where the map says rather than to the spawn",
		"%d of %d pits carry a destination" % [sending, total_pits])

	var bot := _bot()
	var fell := PackedStringArray()
	for zone: DotTimerZone in pits:
		bot.teleport(zone.destination, zone.destination_yaw, true)
		var resent := [0]
		var handler := func(id: StringName, z: DotTimerZone) -> void:
			if id == &"bot" and z.kind == DotTimerZone.Kind.RESPAWN:
				resent[0] += 1
		game.timers.effect_requested.connect(handler)
		# A destination may be in the air (the mapper's own, a hundred units over the
		# floor is common) and may send you on through another teleport (a secret room's
		# way out): both are the map. What is never the map is a fall that does not end,
		# or a pit that sends you into a pit that sends you back.
		# Landing on a surf ramp is riding it, which is never "grounded", so what fails is
		# falling FREELY: two seconds after being put there, a player held up by nothing
		# has dropped what gravity alone gives, and one on a ramp or a floor has not.
		var landed := false
		var seconds := 4.0
		var start_y := bot.global_position.y
		for _i in range(int(seconds * game.tick_rate)):
			await get_tree().physics_frame
			if bot.controller.state.is_grounded():
				landed = true
				break
		game.timers.effect_requested.disconnect(handler)
		var free_fall := 0.5 * bot.controller.tunables.gravity * seconds * seconds
		var falls_freely: bool = not landed and resent[0] == 0 and start_y - bot.global_position.y > free_fall * 0.85
		if falls_freely or resent[0] >= 3:
			fell.append("%s%s" % [_u(zone.destination), " loops" if resent[0] >= 3 else " falls freely"])
	var known: Array = DESTINATIONS_THAT_FALL.get(String(_map_id), [])
	if not fell.is_empty():
		_falls[String(_map_id)] = Array(fell)
	_planned += 1
	if known.is_empty():
		_check(fell.is_empty(), "every sampled pit destination holds a player up, without a loop (%d)" % pits.size(),
			"%d do not: %s" % [fell.size(), ", ".join(fell)])
	else:
		_check(PackedStringArray(known) == fell, "the pit destinations that fall are the listed ones",
			"listed %s, found %s" % [str(known), str(fell)])
	_done()


## A pit keeps the run, through the game's own handler.
func _test_pit_keeps_the_run() -> void:
	_section("a pit keeps the run")
	var zones := game.timers.zones
	var pit: DotTimerZone = null
	var start: DotTimerZone = null
	if zones != null:
		for z: DotTimerZone in zones.of_kind(DotTimerZone.Kind.RESPAWN, DotTimerTrack.MAIN):
			if z.payload.has(G2GBspMap.SENDS_TO):
				pit = z
				break
		start = zones.first_of_kind(DotTimerZone.Kind.START, DotTimerTrack.MAIN)
	_planned += 1
	if pit == null or start == null:
		_check(true, "a pit keeps the run", "no start, or no pit with a destination")
		_done()
		return
	var bot := _bot()
	var timer := bot.timer
	timer.stop()
	var sample := DotTimerSample.new()
	sample.grounded = true
	var away := start.centre() + Vector3(0.0, start.size().y + 8.0, 0.0)
	for point in [start.centre(), start.centre(), away]:
		sample.previous_position = sample.position
		sample.position = point
		timer.tick(sample)
	var was := timer.run.is_running()
	game.timers.effect_requested.emit(&"bot", pit)
	var moved := bot.global_position.distance_to(pit.destination) < 0.01
	_check(was and moved and timer.run.is_running(),
		"falling into a pit sends the player to its destination and keeps the run",
		"running before %s, moved %s, running after %s" % [was, moved, timer.run.is_running()])
	timer.stop()
	_done()


## A block sinks under a player who stays on it, and not under one who hops off it.
func _test_blocks() -> void:
	_section("blocks")
	var m := game.mechanics
	if m == null or m.blocks.is_empty():
		_planned += 1
		_check(true, "blocks", "no sinking blocks on this map")
		_done()
		return
	var bot := _bot()
	var sank := 0
	var stood := 0
	var hopped_ok := 0
	var tried := 0
	var wrong := PackedStringArray()
	for b: Dictionary in _sample(m.blocks, SAMPLE):
		var box: AABB = b["box"]
		var top := Vector3(box.get_center().x, box.end.y + G2GUnits.to_metres(2.0), box.get_center().z)
		# Somewhere to stand at all: a block narrower than the hull, or one under a ceiling,
		# is checked by the ones beside it.
		bot.teleport(top, 0.0, true)
		bot.controller.state.velocity = Vector3.ZERO
		var landed := false
		for _i in range(8):
			await get_tree().physics_frame
			if bot.controller.state.is_grounded():
				landed = true
				break
		if not landed:
			continue
		tried += 1
		var on_since := bot.global_position
		var delay := float(b["delay"])
		var ticks := int(ceil((delay + 0.25) * float(game.tick_rate)))
		for _i in range(ticks):
			await get_tree().physics_frame
		var dest: Vector3 = b["destination"]
		if bot.global_position.distance_to(dest) < G2GUnits.to_metres(64.0) \
				or bot.global_position.distance_to(on_since) > G2GUnits.to_metres(48.0):
			sank += 1
		else:
			wrong.append("%s stayed at %s" % [_u(top), _u(bot.global_position)])
		stood += 1

		# A hop: land and leave on the next tick, which is what a clean run does.
		bot.teleport(top + Vector3(0, G2GUnits.to_metres(40.0), 0), 0.0, true)
		bot.controller.state.velocity = Vector3.ZERO
		var hop_ok := true
		for _i in range(int(0.3 * game.tick_rate)):
			await get_tree().physics_frame
			if bot.controller.state.is_grounded():
				bot.controller.state.velocity.y = G2GUnits.to_metres(G2GUnits.JUMP_VELOCITY)
				bot.controller.motor.set_mode(bot.controller.state, DotFpsState.Mode.AIR)
			if bot.global_position.distance_to(dest) < G2GUnits.to_metres(32.0):
				hop_ok = false
				break
		if hop_ok:
			hopped_ok += 1
	_planned += 2
	_check(tried == 0 or sank == stood,
		"a player who stays on a block is taken off it by the plate under it (%d of %d)" % [sank, stood],
		", ".join(wrong))
	_check(tried == 0 or hopped_ok == tried,
		"a player who hops off a block on landing is not (%d of %d)" % [hopped_ok, tried])
	_done()


## A push moves a player along it.
func _test_pushes() -> void:
	_section("pushes")
	var m := game.mechanics
	var pushes: Array = []
	if m != null:
		for p: Dictionary in m.pushes:
			if (p["push"] as Vector3).length() > G2GUnits.to_metres(50.0):
				pushes.append(p)
	if pushes.is_empty():
		_planned += 1
		_check(true, "pushes", "no pushes on this map")
		_done()
		return
	var bot := _bot()
	var moved := 0
	var tried := 0
	var lame := PackedStringArray()
	for p: Dictionary in _sample(pushes, SAMPLE):
		var box: AABB = p["box"]
		var push: Vector3 = p["push"]
		var at := Vector3(box.get_center().x, box.position.y + G2GUnits.to_metres(1.0), box.get_center().z)
		if bot.controller.motor.would_overlap(bot.controller.state, at) or _in_pit(at):
			continue    # a push box sunk into a floor or over a pit: its neighbours answer
		bot.teleport(at, 0.0, true)
		bot.controller.state.velocity = Vector3.ZERO
		var before := at
		var sent := [0]
		var watch := func(id: StringName, _z: DotTimerZone) -> void:
			if id == &"bot":
				sent[0] += 1
		game.timers.effect_requested.connect(watch)
		for _i in range(8):
			await get_tree().physics_frame
		game.timers.effect_requested.disconnect(watch)
		if sent[0] > 0:
			continue    # the push carried the player into a teleport: it pushed
		tried += 1
		var along := (bot.global_position - before).dot(push.normalized()) \
			+ bot.controller.state.velocity.dot(push.normalized()) * (1.0 / float(game.tick_rate))
		# Eight ticks of the push, or the velocity it left: a quarter of either is a push.
		if along > push.length() * (8.0 / float(game.tick_rate)) * 0.25 or \
				bot.controller.state.velocity.dot(push.normalized()) > push.length() * 0.25:
			moved += 1
		else:
			lame.append("%s pushed %.0f along %s" % [_u(at), G2GUnits.to_units(along), _u(push)])
	_planned += 1
	_check(moved == tried, "a player inside a push is pushed along it (%d of %d placed)" % [moved, tried],
		", ".join(lame))
	_done()


## Whether [param at] is inside any pit: a place the map takes a player away from, so a
## push or a pool there cannot be asked anything.
func _in_pit(at: Vector3) -> bool:
	var zones := game.timers.zones
	if zones == null:
		return false
	for z: DotTimerZone in zones.of_kind(DotTimerZone.Kind.RESPAWN):
		if z.contains(at) or z.contains(at + Vector3.UP * G2GUnits.to_metres(36.0)):
			return true
	return false


func _in_push(at: Vector3) -> bool:
	for p: Dictionary in game.mechanics.pushes:
		if (p["box"] as AABB).has_point(at) or (p["box"] as AABB).has_point(at + Vector3.UP * G2GUnits.to_metres(36.0)):
			return true
	return false


## Water is swum in: a player who presses nothing sinks slowly, and one holding jump rises.
func _test_water() -> void:
	_section("water")
	var m := game.mechanics
	var pools: Array = []
	if m != null:
		for w: AABB in m.water:
			if w.size.y > G2GUnits.to_metres(80.0) and w.size.x > G2GUnits.to_metres(64.0) \
					and w.size.z > G2GUnits.to_metres(64.0) \
					and not _in_pit(Vector3(w.get_center().x, w.end.y - G2GUnits.to_metres(70.0), w.get_center().z)):
				pools.append(w)
	if pools.is_empty():
		_planned += 1
		_check(true, "water", "no water deep enough to swim in on this map")
		_done()
		return
	var bot := _bot()
	var swam := 0
	var rose := 0
	var stuck := PackedStringArray()
	var placed := 0
	var tried := 0
	for w: AABB in _sample(pools, 4):
		var feet := Vector3(w.get_center().x, w.end.y - G2GUnits.to_metres(70.0), w.get_center().z)
		if bot.controller.motor.would_overlap(bot.controller.state, feet) or _in_push(feet):
			continue    # under a floor, or in a current: surf_grave_reloaded's pools pull you down
		placed += 1
		bot.teleport(feet, 0.0, true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if bot.controller.state.mode != bot.swim.mode_id:
			continue
		tried += 1
		swam += 1
		var y0 := bot.global_position.y
		var command := DotFpsCommand.new()
		command.buttons = DotFpsCommand.BUTTON_JUMP
		for _i in range(32):
			bot.controller.apply_command(command)
			await get_tree().physics_frame
		if bot.global_position.y > y0 + G2GUnits.to_metres(8.0) \
				or bot.controller.state.mode != bot.swim.mode_id:
			rose += 1
		else:
			stuck.append("%s %.0f -> %.0f u, mode %d, surface %.0f" % [_u(feet), G2GUnits.to_units(y0),
				G2GUnits.to_units(bot.global_position.y), bot.controller.state.mode, G2GUnits.to_units(w.end.y)])
		bot.controller.apply_command(DotFpsCommand.new())
	_planned += 2
	_check(tried == placed, "a player put in the water swims (%d of %d pools)" % [tried, placed], "nobody entered the swim mode")
	_check(rose == tried, "and holding jump rises to the surface (%d of %d)" % [rose, tried], ", ".join(stuck))
	_done()

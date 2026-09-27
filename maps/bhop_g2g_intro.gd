extends "../game/g2g_map.gd"

const G2GGeometry := preload("../game/g2g_geometry.gd")
const G2GReach := preload("../game/g2g_reach.gd")

## `bhop_g2g_intro` — sixteen blocks with widening gaps, three stages, and three bonuses.
##
## Built in genre units so it reads like a brush list. The gaps grow from 96
## to 288 units: at 250 u/s a standing jump clears about 190, so from the tenth block
## on the only way across is to have kept the speed from the earlier ones — which
## means landing and jumping on the same tick, every time, which is the whole skill.
## With [code]sv_autobunnyhopping 1[/code] that is holding the key and aiming; with it
## off, it is the tick.
##
## The bonus is a short side route off the start pad: three wide platforms and a
## finish, for a player who wants a warm-up.
##
## [b]Bonus 2 is the other half of that, and it is a different skill rather than a
## harder version of the same one.[/b] The main route and bonus 1 are both about SPEED:
## the gap grows until only a player who kept the last block's momentum can cross it.
## `the needle` keeps its gap at 96 units the whole way down — the shortest gap on the
## map, and well inside a standing jump at run speed, so no hop on it is ever about
## carrying speed — and narrows the landing instead, 192 units wide down to 48. A block
## 48 units across is 16 units wider than the player, and the whole of it is aim.
##
## Two reasons that shape rather than a longer gap. A player who cannot yet chain hops
## has nothing to practise on this map, because everything else on it refuses them at
## the tenth block; the needle refuses nobody for lack of speed and is still hard. And a
## constant gap is the one shape a SCRIPTED bot can complete — it cannot strafe, so it
## cannot gain, so a route that demands a gain is a route no check can ever drive end to
## end. `headless_run` drives this one from its start line to its finish through both of
## its stage splits, which nothing in this repository could do on a bonus before.
##
## [b]96 rather than 160, and the difference was measured rather than chosen.[/b] At 160
## a hopping bot cleared seven blocks and fell at the eighth: a chained hop takes off
## wherever the last one landed rather than at the lip, so the distance actually
## available is the jump MINUS however far onto the block the bot arrived, and that
## margin bleeds a little every landing. A gap a standing jump clears is not the same
## as a gap a chain of them clears, which is the number this map's main route encodes in
## its first block and nowhere says out loud.
##
## [b]Bonus 3, `the hairpin`, is the one route here that turns.[/b] See
## [constant HAIRPIN_LEGS].

const BLOCKS := 16
const BLOCK_LENGTH := 160.0
const BLOCK_WIDTH := 192.0
const BLOCK_THICKNESS := 32.0
const FIRST_GAP := 96.0
const LAST_GAP := 288.0

const START_Z := 0.0
const FLOOR_Y := 0.0

## Bonus 2, `the needle`: constant gap, narrowing blocks. West of the start pad, running
## the same way as the main route so a player learns one heading rather than two.
const NEEDLE_X := -640.0
const NEEDLE_BLOCKS := 10
const NEEDLE_GAP := 96.0
const NEEDLE_FIRST_WIDTH := 192.0
const NEEDLE_LAST_WIDTH := 48.0

## Bonus 3, `the hairpin`: out, across and back, a U of RUN jumps east of the warm-up.
##
## [b]Every other route on this map is a straight line down -Z.[/b] The hairpin asks for
## the one thing none of them does: land, turn, and leave in a new direction. It goes
## out along -Z, turns right on a square corner block onto a climbing traverse along +X,
## turns right again on a second corner at the top, and comes back along +Z down a stair
## of drops onto blocks that narrow from 160 to 96, finishing beside where it started.
## The two corners are the two stage lines (drawn in the finish colour, as `the ridge`'s
## are), and each faces the direction the route LEAVES it in, which is the direction a
## restarting player has to go.
##
## [b]Every gap is a RUN gap, sized with [G2GReach] under the shipped cvars[/b] — 189
## flat, 166 onto +24, 222 down 48 — and each is at least 29 units inside it, so a
## player who lands anywhere can run to the lip and take the next one. That is what a
## corner needs: a turn costs the speed a chain would be carrying, so a turning route
## sized for a CHAIN would be one only a strafer who turns in the air could run.
##
## One list, read by the geometry, the zones and `headless_run`'s bot ([method
## hairpin_blocks]). `heading` is [code]Vector2(x, z)[/code]; a leg's `turn` is the
## heading its corner leaves in, and `corner_gap` / `corner_rise` the jump onto it.
const HAIRPIN_X := 2304.0
const HAIRPIN_PAD_LENGTH := 512.0
const HAIRPIN_PAD_WIDTH := 256.0
const HAIRPIN_CORNER := 256.0
const HAIRPIN_FINISH_GAP := 160.0
const HAIRPIN_FINISH_RISE := -48.0
const HAIRPIN_FINISH_LENGTH := 384.0
const HAIRPIN_LEGS: Array = [
	{"name": "out", "heading": Vector2(0.0, -1.0), "blocks": 4, "rise": 0.0,
		"first_gap": 112.0, "last_gap": 160.0, "first_width": 192.0, "last_width": 192.0,
		"corner_gap": 144.0, "corner_rise": 0.0, "turn": Vector2(1.0, 0.0)},
	{"name": "across", "heading": Vector2(1.0, 0.0), "blocks": 4, "rise": 24.0,
		"first_gap": 96.0, "last_gap": 128.0, "first_width": 176.0, "last_width": 176.0,
		"corner_gap": 128.0, "corner_rise": 24.0, "turn": Vector2(0.0, 1.0)},
	{"name": "back", "heading": Vector2(0.0, 1.0), "blocks": 4, "rise": -48.0,
		"first_gap": 128.0, "last_gap": 192.0, "first_width": 160.0, "last_width": 96.0},
]


func _build() -> void:
	tier = 2
	G2GGeometry.sun(self)
	fallback_spawn_units = Vector3(0.0, FLOOR_Y + 8.0, START_Z + 320.0)

	# The start pad, long enough to build speed on.
	var main: Array = [G2GGeometry.box(
		self, Vector3(0.0, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z + 256.0),
		Vector3(BLOCK_WIDTH, BLOCK_THICKNESS, 512.0), G2GGeometry.COLOUR_START
	)]

	var z := START_Z

	for i in range(BLOCKS):
		main.append(G2GGeometry.box(
			self,
			Vector3(0.0, FLOOR_Y - BLOCK_THICKNESS * 0.5, z - BLOCK_LENGTH * 0.5),
			Vector3(BLOCK_WIDTH, BLOCK_THICKNESS, BLOCK_LENGTH),
			G2GGeometry.COLOUR_PLATFORM
		))
		z -= BLOCK_LENGTH + gap_at(i)

	# The finish pad.
	main.append(G2GGeometry.box(
		self, Vector3(0.0, FLOOR_Y - BLOCK_THICKNESS * 0.5, z - 192.0),
		Vector3(BLOCK_WIDTH, BLOCK_THICKNESS, 384.0), G2GGeometry.COLOUR_END
	))

	# [b]A CHAIN, and the map's own sentence says why.[/b] From the ninth gap on (198
	# units) nothing crosses without speed a standing jump does not have, so the whole
	# line is sized for hops carried at course speed — see G2GReach.
	add_course("main", DotTimerTrack.MAIN, G2GReach.Kind.CHAIN, main)

	# The bonus: off to the right of the start pad, three big platforms and a pad.
	var warm_up: Array = []

	for i in range(3):
		warm_up.append(G2GGeometry.box(
			self,
			Vector3(640.0 + float(i) * 320.0, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z + 256.0),
			Vector3(192.0, BLOCK_THICKNESS, 192.0), G2GGeometry.COLOUR_BONUS
		))

	warm_up.append(G2GGeometry.box(
		self, Vector3(1600.0, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z + 256.0),
		Vector3(256.0, BLOCK_THICKNESS, 256.0), G2GGeometry.COLOUR_END
	))

	# A warm-up is a RUN course: every gap in it is a jump from the lip at run speed,
	# which is what "a warm-up" has to mean for a player who cannot chain yet.
	add_course("warm-up", DotTimerTrack.of_bonus(1), G2GReach.Kind.RUN, warm_up)

	# Bonus 2, `the needle`. Its own start pad west of the main one, then ten blocks at a
	# constant 96-unit gap whose width closes from 192 to 48, and a finish wide enough
	# to land on after the last of them.
	var needle: Array = [G2GGeometry.box(
		self, Vector3(NEEDLE_X, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z + 256.0),
		Vector3(256.0, BLOCK_THICKNESS, 512.0), G2GGeometry.COLOUR_START
	)]

	for i in range(NEEDLE_BLOCKS):
		needle.append(G2GGeometry.box(
			self,
			Vector3(NEEDLE_X, FLOOR_Y - BLOCK_THICKNESS * 0.5, needle_z(i) - BLOCK_LENGTH * 0.5),
			Vector3(needle_width(i), BLOCK_THICKNESS, BLOCK_LENGTH),
			G2GGeometry.COLOUR_BONUS
		))

	needle.append(G2GGeometry.box(
		self,
		Vector3(NEEDLE_X, FLOOR_Y - BLOCK_THICKNESS * 0.5, needle_end_z() - 192.0),
		Vector3(256.0, BLOCK_THICKNESS, 384.0), G2GGeometry.COLOUR_END
	))

	# RUN, and it is the whole design of the route: "no hop on it is ever about carrying
	# speed", which is what makes it the one a scripted bot finishes.
	add_course("the needle", DotTimerTrack.of_bonus(2), G2GReach.Kind.RUN, needle)

	_build_hairpin()


## Bonus 3, `the hairpin`. See [constant HAIRPIN_LEGS].
func _build_hairpin() -> void:
	var bodies: Array = [G2GGeometry.box(
		self,
		Vector3(HAIRPIN_X, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z + HAIRPIN_PAD_LENGTH * 0.5),
		Vector3(HAIRPIN_PAD_WIDTH, BLOCK_THICKNESS, HAIRPIN_PAD_LENGTH), G2GGeometry.COLOUR_START
	)]

	for block: Dictionary in hairpin_blocks():
		var centre: Vector3 = block["centre"]
		var extent: Vector2 = block["extent"]
		bodies.append(G2GGeometry.box(
			self,
			Vector3(centre.x, centre.y - BLOCK_THICKNESS * 0.5, centre.z),
			Vector3(extent.x, BLOCK_THICKNESS, extent.y),
			# A corner carries a stage line and is drawn in the finish colour: a split a
			# player can see, and the block they are about to turn on.
			G2GGeometry.COLOUR_END if int(block["stage"]) > 0 else G2GGeometry.COLOUR_BONUS
		))

	var pad := hairpin_pad()
	bodies.append(G2GGeometry.box(
		self, Vector3(pad.x, pad.y - BLOCK_THICKNESS * 0.5, pad.z),
		Vector3(HAIRPIN_PAD_WIDTH, BLOCK_THICKNESS, HAIRPIN_FINISH_LENGTH), G2GGeometry.COLOUR_END
	))

	# RUN, for the reason in [constant HAIRPIN_LEGS]: every corner spends the speed.
	add_course("the hairpin", DotTimerTrack.of_bonus(3), G2GReach.Kind.RUN, bodies)


## Every block of the hairpin in order, corners included: `centre` is the middle of its
## top face (units), `extent` its size in world X and Z, `heading` the direction a player
## LEAVES it in, `exit` the middle of the edge they leave it over (x, z), and `stage` the
## stage split drawn across it, 0 for none.
##
## [b]Static, and the only place the hairpin's arithmetic is done[/b], for the reason
## `bhop_g2g_stages.ridge_blocks` is: a gap changed here moves the block, the split on
## it and the bot's aim and jump together.
static func hairpin_blocks() -> Array:
	var out: Array = []
	var at := Vector2(HAIRPIN_X, START_Z)   # the pad's far edge: the route leaves it here
	var y := FLOOR_Y
	var stage := 0

	for leg: Dictionary in HAIRPIN_LEGS:
		var heading: Vector2 = leg["heading"]
		var blocks := int(leg["blocks"])

		for i in range(blocks):
			var t := float(i) / float(maxi(blocks - 1, 1))
			at += heading * lerpf(float(leg["first_gap"]), float(leg["last_gap"]), t)
			y += float(leg["rise"])
			var width := lerpf(float(leg["first_width"]), float(leg["last_width"]), t)
			out.append(_hairpin_block(at + heading * BLOCK_LENGTH * 0.5, y,
				_extent(heading, BLOCK_LENGTH, width), heading, at + heading * BLOCK_LENGTH, 0))
			at += heading * BLOCK_LENGTH

		if not leg.has("turn"):
			continue

		# The corner: square, entered along the leg and left along `turn`.
		at += heading * float(leg["corner_gap"])
		y += float(leg["corner_rise"])
		var turn: Vector2 = leg["turn"]
		var middle := at + heading * HAIRPIN_CORNER * 0.5
		stage += 1
		out.append(_hairpin_block(middle, y, Vector2(HAIRPIN_CORNER, HAIRPIN_CORNER), turn,
			middle + turn * HAIRPIN_CORNER * 0.5, stage))
		at = middle + turn * HAIRPIN_CORNER * 0.5

	return out


static func _hairpin_block(
	middle: Vector2, y: float, extent: Vector2, heading: Vector2, exit: Vector2, stage: int
) -> Dictionary:
	return {
		"centre": Vector3(middle.x, y, middle.y), "extent": extent,
		"heading": heading, "exit": exit, "stage": stage,
	}


## A block's size in world X and Z, from its length along [param heading] and its width.
static func _extent(heading: Vector2, length: float, width: float) -> Vector2:
	return Vector2(length, width) if absf(heading.x) > 0.5 else Vector2(width, length)


## The middle of the hairpin's finish pad's top face: one more drop past the last block.
static func hairpin_pad() -> Vector3:
	var blocks := hairpin_blocks()
	var last: Dictionary = blocks[blocks.size() - 1]
	var heading: Vector2 = last["heading"]
	var middle: Vector2 = (last["exit"] as Vector2) \
		+ heading * (HAIRPIN_FINISH_GAP + HAIRPIN_FINISH_LENGTH * 0.5)
	var top: float = (last["centre"] as Vector3).y + HAIRPIN_FINISH_RISE
	return Vector3(middle.x, top, middle.y)


## The yaw that faces [param heading] ([code]Vector2(x, z)[/code]). Yaw 0 is -Z on this
## map and a positive yaw turns left (`Basis(UP, yaw)`), so +X is -90 — what the
## warm-up's spawn uses.
static func yaw_facing(heading: Vector2) -> float:
	return rad_to_deg(atan2(-heading.x, -heading.y))


static func gap_at(index: int) -> float:
	return lerpf(FIRST_GAP, LAST_GAP, float(index) / float(maxi(BLOCKS - 1, 1)))


## Z of the front edge of needle block [param index]. One arithmetic, read by the
## geometry and by the zones, because a stage line placed from a second copy of a
## block's position is a split that drifts the first time a number here moves.
static func needle_z(index: int) -> float:
	return START_Z - float(index) * (BLOCK_LENGTH + NEEDLE_GAP)


## How wide needle block [param index] is. Closes linearly, so the difficulty is a ramp
## rather than a wall — the player who falls learns where their aim runs out.
static func needle_width(index: int) -> float:
	return lerpf(
		NEEDLE_FIRST_WIDTH, NEEDLE_LAST_WIDTH,
		float(index) / float(maxi(NEEDLE_BLOCKS - 1, 1))
	)


## Z of the far edge of the needle's last block: where its finish pad begins.
static func needle_end_z() -> float:
	return needle_z(NEEDLE_BLOCKS - 1) - BLOCK_LENGTH


static func end_z() -> float:
	var z := START_Z
	for i in range(BLOCKS):
		z -= BLOCK_LENGTH + gap_at(i)
	return z


## Z of the front edge of block [param index], for placing stage lines.
static func block_z(index: int) -> float:
	var z := START_Z
	for i in range(index):
		z -= BLOCK_LENGTH + gap_at(i)
	return z


func timer_zones() -> DotTimerZoneSet:
	return build_zones()


static func build_zones() -> DotTimerZoneSet:
	var zones := DotTimerZoneSet.new()
	zones.map_id = &"bhop_g2g_intro"
	zones.meta["tier"] = 2
	zones.meta["author"] = "g2gfast"

	var main := DotTimerTrack.MAIN
	var finish_z := end_z()

	zones.add(zone_box(DotTimerZone.Kind.START, main,
		Vector3(-96.0, FLOOR_Y, START_Z), Vector3(96.0, FLOOR_Y + 128.0, START_Z + 512.0)))
	zones.add(zone_box(DotTimerZone.Kind.END, main,
		Vector3(-96.0, FLOOR_Y, finish_z - 384.0), Vector3(96.0, FLOOR_Y + 128.0, finish_z - 64.0)))

	# Stages on blocks 5, 10 and 14, spanning the block so a fast player cannot pass
	# through the line between two ticks.
	#
	# Each carries the spot `!s<n>` puts a player: the block the stage line is drawn
	# on, a little above it. Without a destination the request succeeds and drops them
	# at the world origin, which on this map is in the sky over the start pad.
	#
	# [b]`!s2` and `!s3` put a player where the next gap cannot be crossed from a
	# standstill, by anybody.[/b] A restart is a chain that begins at run speed, and from
	# blocks 10 and 14 the gaps ahead need more than even a perfect strafe adds in the
	# hops available; `!s1` needs 78% of one. `headless_run` prints all three. Not moved,
	# because they are the same three destinations `[stage-yaw-1]` is waiting on.
	var stage_blocks := [5, 10, 14]
	for i in range(stage_blocks.size()):
		var bz := block_z(stage_blocks[i])
		zones.add(zone_stage(
			main, i + 1,
			Vector3(-96.0, FLOOR_Y, bz - BLOCK_LENGTH),
			Vector3(96.0, FLOOR_Y + 128.0, bz),
			Vector3(0.0, FLOOR_Y + 8.0, bz - BLOCK_LENGTH * 0.5),
			180.0
		))

	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, main,
		Vector3(-4096.0, FLOOR_Y - 1024.0, finish_z - 4096.0),
		Vector3(4096.0, FLOOR_Y - 192.0, START_Z + 4096.0)))

	zones.add(zone_spawn(main, Vector3(0.0, FLOOR_Y + 8.0, START_Z + 400.0), 0.0))

	# The bonus.
	var bonus := DotTimerTrack.of_bonus(1)
	zones.add(zone_box(DotTimerZone.Kind.START, bonus,
		Vector3(544.0, FLOOR_Y, START_Z + 160.0), Vector3(736.0, FLOOR_Y + 128.0, START_Z + 352.0)))
	zones.add(zone_box(DotTimerZone.Kind.END, bonus,
		Vector3(1472.0, FLOOR_Y, START_Z + 128.0), Vector3(1728.0, FLOOR_Y + 128.0, START_Z + 384.0)))
	zones.add(zone_spawn(bonus, Vector3(640.0, FLOOR_Y + 8.0, START_Z + 256.0), -90.0))

	# [b]The bonus tracks had no respawn zone, and the main track has had one since the
	# map was written.[/b] A `DotTimerZone` carries a track, and a RESPAWN zone on track
	# 0 catches nobody who is running track 1 — so a player who missed a bonus platform
	# here fell out of the world for ever with nothing in the log to say so, while the
	# same mistake on the main route put them back on the pad. Found by driving a bot
	# down the needle: it fell at a block and was still falling 1,370 metres later.
	#
	# `surf_g2g_intro` was given per-bonus respawn zones when its second bonus was
	# added, and a hand-written check for them was added to `headless_run` then — but it
	# was asked on the surf map only, so this map was never the one being checked. The
	# same one-map fix this tree has now missed in six places. That check is gone:
	# dot-timer's `DotTimerZoneSet.route_problems()` asks every route on every map for a
	# start, a finish, a spawn and a pit (`[track-zone-1]`), and `tools/export_zones.gd`
	# refuses to write a map that fails it.
	var fall_low := Vector3(-4096.0, FLOOR_Y - 1024.0, finish_z - 4096.0)
	var fall_high := Vector3(4096.0, FLOOR_Y - 192.0, START_Z + 4096.0)

	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, bonus, fall_low, fall_high))

	# Bonus 2, `the needle`, with two stage splits on it.
	#
	# [b]Stages on a bonus track, which nothing here had.[/b] `DotTimerZoneSet` keys a
	# stage by its track, and every stage zone in this repository was on the main one —
	# so `stage_count(track)`, the per-stage splits and `!s<n>` on anything but the main
	# route were code no map had ever asked to run. The two lines are on blocks 3 and 7:
	# the first is where the blocks stop being generous and the second is where they get
	# genuinely thin, which is where a player wants to know their time.
	var needle := DotTimerTrack.of_bonus(2)
	var needle_finish := needle_end_z()

	zones.add(zone_box(DotTimerZone.Kind.START, needle,
		Vector3(NEEDLE_X - 128.0, FLOOR_Y, START_Z),
		Vector3(NEEDLE_X + 128.0, FLOOR_Y + 128.0, START_Z + 512.0)))
	zones.add(zone_box(DotTimerZone.Kind.END, needle,
		Vector3(NEEDLE_X - 128.0, FLOOR_Y, needle_finish - 384.0),
		Vector3(NEEDLE_X + 128.0, FLOOR_Y + 128.0, needle_finish - 64.0)))

	for i in range(2):
		var block := 3 if i == 0 else 7
		var nz := needle_z(block)
		var half := needle_width(block) * 0.5

		zones.add(zone_stage(
			needle, i + 1,
			Vector3(NEEDLE_X - half, FLOOR_Y, nz - BLOCK_LENGTH),
			Vector3(NEEDLE_X + half, FLOOR_Y + 128.0, nz),
			Vector3(NEEDLE_X, FLOOR_Y + 8.0, nz - BLOCK_LENGTH * 0.5),
			# Facing DOWN the needle. Yaw 0 is -Z here — it is what the spawn zones on
			# this map use and it is the direction `headless_run` drives a bot to make
			# progress. The main route's three stage lines say 180.0, which faces a
			# player back up the course they were about to run; that is not changed
			# here because it is existing content on a track with records against it,
			# but it is not copied either.
			0.0
		))

	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, needle, fall_low, fall_high))
	zones.add(zone_spawn(needle, Vector3(NEEDLE_X, FLOOR_Y + 8.0, START_Z + 400.0), 0.0))

	# Bonus 3, the hairpin: a start, a split on each corner, a finish, a spawn and a pit,
	# every one read off `hairpin_blocks()`.
	var hairpin := DotTimerTrack.of_bonus(3)
	var pad := hairpin_pad()
	var pad_half := HAIRPIN_PAD_WIDTH * 0.5

	zones.add(zone_box(DotTimerZone.Kind.START, hairpin,
		Vector3(HAIRPIN_X - pad_half, FLOOR_Y, START_Z),
		Vector3(HAIRPIN_X + pad_half, FLOOR_Y + 128.0, START_Z + HAIRPIN_PAD_LENGTH)))
	# The pad's last 320 units, so a player has landed rather than grazed its lip when
	# the clock stops. The route comes home along +Z, so "last" is the high-Z end.
	zones.add(zone_box(DotTimerZone.Kind.END, hairpin,
		Vector3(pad.x - pad_half, pad.y, pad.z - HAIRPIN_FINISH_LENGTH * 0.5 + 64.0),
		Vector3(pad.x + pad_half, pad.y + 128.0, pad.z + HAIRPIN_FINISH_LENGTH * 0.5)))

	for block: Dictionary in hairpin_blocks():
		if int(block["stage"]) == 0:
			continue
		var centre: Vector3 = block["centre"]
		var half: Vector2 = (block["extent"] as Vector2) * 0.5
		zones.add(zone_stage(
			hairpin, int(block["stage"]),
			Vector3(centre.x - half.x, centre.y, centre.z - half.y),
			Vector3(centre.x + half.x, centre.y + 128.0, centre.z + half.y),
			centre + Vector3(0.0, 8.0, 0.0),
			# Facing the way the route LEAVES the corner, which is the way a restarting
			# player has to go. Not the main route's 180 (`[stage-yaw-1]`).
			yaw_facing(block["heading"])
		))

	zones.add(zone_spawn(hairpin,
		Vector3(HAIRPIN_X, FLOOR_Y + 8.0, START_Z + HAIRPIN_PAD_LENGTH - 112.0), 0.0))
	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, hairpin,
		Vector3(-4096.0, FLOOR_Y - 1024.0, -4096.0),
		Vector3(8192.0, pad.y - BLOCK_THICKNESS - 256.0, 4096.0)))

	return zones

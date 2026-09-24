extends "../game/g2g_map.gd"

const G2GGeometry := preload("../game/g2g_geometry.gd")
const G2GReach := preload("../game/g2g_reach.gd")

## `bhop_g2g_stages` — five stages, two bonuses, and a different idea in each stage.
##
## Bonus 1 is a surf descent; bonus 2, `the ridge`, is a staged RUN line — see
## [constant RIDGE_SECTIONS].
##
## [b]Why this map exists.[/b] `bhop_g2g_intro` is sixteen blocks in a straight line
## over a flat plane. It proves the movement and it is not a map: there is one thing to
## do, once, and a player who can do it has seen everything. It is also the wrong shape
## to exercise this platform, because every interesting thing dot-timer can do —
## stages, splits, a stage restart, a per-stage comparison, a bonus on its own track —
## needs a map with more than one section in it.
##
## This is the timer community's staged-map shape: a course divided into numbered sections
## with a line between each, so a run has a split at every line, a player can practise
## one section with [code]!s3[/code], and the HUD has something to say between the start
## and the finish. Each stage is one idea, so a player who fails knows which idea they
## failed:
##
## [codeblock]
## 1  straight       blocks in a line, gaps growing.      Keep the speed.
## 2  the turn       the course bends 90 degrees.         Strafe through it.
## 3  the climb      blocks rising 24 units each.         Height costs speed.
## 4  the drop       a descent onto narrow blocks.        Do not overshoot.
## 5  the zigzag     blocks alternating left and right.   Both directions.
## [/codeblock]
##
## [b]Everything is derived from a cursor.[/b] `_course()` walks a position and a
## heading and returns every block; the geometry and the zones both read that one list,
## so a stage line cannot drift from the block it is drawn on. That is `G2GMap`'s rule
## and it matters more here than on a straight course — a hand-placed line on a map that
## turns is a leaderboard nobody can compare.

## Units per block along the direction of travel.
const BLOCK_LENGTH := 160.0

## How wide a block is across the direction of travel.
const BLOCK_WIDTH := 176.0

## How wide the narrow blocks in stage 4 are. A 176-unit block is forgiving; 96 is
## about a hull and a half and is where a player starts having to aim the landing.
const NARROW_WIDTH := 96.0

const BLOCK_THICKNESS := 32.0

## How high a stage-3 block sits above the one before it.
##
## 24 units, because a bhop jump gains about 57 and a player who is climbing is
## spending part of every jump on the climb rather than on the gap. Anything past about
## 32 stops being a climb and becomes a wall.
const CLIMB_STEP := 24.0

## How far a stage-4 block sits below the one before it.
const DROP_STEP := 48.0

## How far a zigzag block is offset sideways from the centre line.
const ZIGZAG_OFFSET := 128.0

const FLOOR_Y := 0.0

## How far to the side the bonus sits. See `_build_bonus`.
const BONUS_X := 6144.0

## Bonus 2, `the ridge`: up a stair, along a narrowing crest, down the other side. Half
## way between the main course (which never leaves x <= 176) and the surf bonus (whose
## ramps start at 5,760), so neither is in the other's view from a start pad.
const RIDGE_X := 3072.0

## The ridge's three sections, in order. One list, read by the geometry, the zones and
## `headless_run`'s bot, for the reason [constant STAGES] is one list. `rise` is per
## block; a section's first gap is the gap onto its first block.
##
## [b]Every gap is a RUN gap, sized with [G2GReach] under the shipped cvars[/b] — a jump
## from the lip at 250 u/s clears 189 flat, 166 onto +24 and 222 down 48 — and each is at
## least 29 units inside it, so a player who lands anywhere on a block can run to its
## edge and still make the next one. That is the route's whole promise: it is the
## stages map's practice line, for a player who can jump but cannot yet chain, and it
## asks three things a straight line of level blocks does not — judge a climb, hold a
## line on a crest that narrows from 176 to 80, and not overshoot a drop.
const RIDGE_SECTIONS: Array = [
	{"kind": "climb", "blocks": 5, "rise": 24.0, "first_gap": 96.0, "last_gap": 128.0,
		"first_width": 176.0, "last_width": 176.0},
	{"kind": "crest", "blocks": 4, "rise": 0.0, "first_gap": 128.0, "last_gap": 160.0,
		"first_width": 176.0, "last_width": 80.0},
	{"kind": "descent", "blocks": 5, "rise": -48.0, "first_gap": 128.0, "last_gap": 192.0,
		"first_width": 128.0, "last_width": 128.0},
]

## The ridge's start pad: its centre is at START_Z, like the main route's.
const RIDGE_PAD_LENGTH := 512.0

## Where a player stands to start, behind the start line.
const START_Z := 512.0

## How many stages, and how many blocks each one is.
##
## Read by the geometry, by the zones and by the suite. One list, because two lists is
## the bug the one list exists to prevent — and this repository's own tooling has been
## the third copy of a list twice.
const STAGES: Array = [
	{"kind": "straight", "blocks": 8, "first_gap": 96.0, "last_gap": 224.0},
	{"kind": "turn", "blocks": 8, "first_gap": 128.0, "last_gap": 208.0},
	{"kind": "climb", "blocks": 7, "first_gap": 128.0, "last_gap": 192.0},
	{"kind": "drop", "blocks": 7, "first_gap": 160.0, "last_gap": 288.0},
	{"kind": "zigzag", "blocks": 9, "first_gap": 128.0, "last_gap": 240.0},
]


func _build() -> void:
	tier = 4
	G2GGeometry.sun(self)

	var course := _course()

	fallback_spawn_units = Vector3(0.0, FLOOR_Y + 8.0, START_Z - 96.0)

	# The start pad. Long, because this genre's runs begin with a prestrafe: a player
	# holding jump from a standstill creeps at the air cap for ever, so the pad has to
	# be long enough to walk up to speed on before crossing the line.
	var bodies: Array = [G2GGeometry.box(
		self, Vector3(0.0, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z),
		Vector3(BLOCK_WIDTH + 128.0, BLOCK_THICKNESS, 640.0),
		G2GGeometry.ROLE_START
	)]

	for block: Dictionary in course:
		bodies.append(G2GGeometry.box(
			self,
			Vector3(
				float(block["x"]),
				float(block["y"]) - BLOCK_THICKNESS * 0.5,
				float(block["z"])
			),
			Vector3(float(block["width"]), BLOCK_THICKNESS, BLOCK_LENGTH),
			# The last block of each stage is drawn in the finish colour, so a player
			# can SEE where the split is rather than only being told after crossing it.
			# A stage line the player cannot see is a split they cannot aim at.
			G2GGeometry.ROLE_END if bool(block["stage_end"]) else G2GGeometry.ROLE_PLATFORM,
			Basis(Vector3.UP, deg_to_rad(float(block["yaw"])))
		))

	var last: Dictionary = course[course.size() - 1]

	# The finish pad, from `_pad_centre` and not from an offset written out again here.
	#
	# [b]It was `last.z - 384`, and the course does not end heading -Z.[/b] The turn in
	# stage 2 leaves the cursor at yaw 90 and every stage after it inherits that, so the
	# last block heads -X — and a pad offset along world -Z landed 543 units off the
	# finish zone, which is drawn 384 units along the HEADING. The two boxes overlapped
	# by a 128 x 24 corner nothing lands on: the player ran onto a pad drawn in the
	# finish colour, stopped, and the timer went on counting for ever. Nothing errored,
	# because a run that has not finished is a legitimate thing for a run to be.
	#
	# One function now answers "where is the finish", and the geometry and the zone both
	# call it. That is this map's own rule -- `_course()` is the single source for the
	# blocks -- applied to the one place that was still doing the arithmetic twice.
	var end_at := _pad_centre(last)

	bodies.append(G2GGeometry.box(
		self,
		Vector3(end_at.x, end_at.y - BLOCK_THICKNESS * 0.5, end_at.z),
		Vector3(BLOCK_WIDTH + 128.0, BLOCK_THICKNESS, 512.0),
		G2GGeometry.ROLE_END,
		Basis(Vector3.UP, deg_to_rad(float(last["yaw"])))
	))

	# [b]One CHAIN, start pad to finish pad.[/b] Every stage's idea is a way of keeping
	# speed — "keep the speed", "strafe through it", "height costs speed" — and the
	# widest gaps in stages 1, 3 and 4 are past what a standing jump crosses, so the line
	# is sized for hops carried at course speed. `headless_run` also runs the chain from
	# every `!s<n>` destination, because a stage a player restarts from a standstill is
	# a chain that begins at run speed rather than at whatever the stages before it
	# built. The surf bonus declares nothing: it is a drop onto a bank, not a jump.
	add_course("main", DotTimerTrack.MAIN, G2GReach.Kind.CHAIN, bodies)

	_build_bonus()
	_build_ridge()


## Bonus 2, `the ridge`. See [constant RIDGE_SECTIONS].
func _build_ridge() -> void:
	var bodies: Array = [G2GGeometry.box(
		self, Vector3(RIDGE_X, FLOOR_Y - BLOCK_THICKNESS * 0.5, START_Z),
		Vector3(256.0, BLOCK_THICKNESS, RIDGE_PAD_LENGTH), G2GGeometry.ROLE_START
	)]

	for block: Dictionary in ridge_blocks():
		bodies.append(G2GGeometry.box(
			self,
			Vector3(RIDGE_X, float(block["y"]) - BLOCK_THICKNESS * 0.5,
				float(block["near"]) - BLOCK_LENGTH * 0.5),
			Vector3(float(block["width"]), BLOCK_THICKNESS, BLOCK_LENGTH),
			# The first block of each section after the first carries a stage line and is
			# drawn in the finish colour, as the main route's are: a split a player can see.
			G2GGeometry.ROLE_END if bool(block["stage_line"]) else G2GGeometry.ROLE_BONUS
		))

	var pad := ridge_pad()
	bodies.append(G2GGeometry.box(
		self, Vector3(RIDGE_X, pad.y - BLOCK_THICKNESS * 0.5, pad.z),
		Vector3(256.0, BLOCK_THICKNESS, 384.0), G2GGeometry.ROLE_END
	))

	# RUN: every gap is a jump from the lip at run speed, which is what the route
	# promises and what `headless_run` drives a bot along to prove it.
	add_course("the ridge", DotTimerTrack.of_bonus(2), G2GReach.Kind.RUN, bodies)


## Every block of the ridge in order: `near` and `far` are the Z of its two edges
## (near > far, the route runs toward -Z), `y` its top, `stage_line` whether a stage
## split is drawn across it and `stage` which number that split is.
##
## [b]Static, and the only place the ridge's arithmetic is done[/b] — the geometry, the
## zones and the suite's bot all read it, so a gap changed here moves the block, the
## split on it and the bot's jump together.
static func ridge_blocks() -> Array:
	var out: Array = []
	var near := START_Z - RIDGE_PAD_LENGTH * 0.5
	var y := FLOOR_Y

	for section_index in range(RIDGE_SECTIONS.size()):
		var section: Dictionary = RIDGE_SECTIONS[section_index]
		var blocks := int(section["blocks"])

		for i in range(blocks):
			var t := float(i) / float(maxi(blocks - 1, 1))
			near -= lerpf(float(section["first_gap"]), float(section["last_gap"]), t)
			y += float(section["rise"])

			out.append({
				"near": near,
				"far": near - BLOCK_LENGTH,
				"y": y,
				"width": lerpf(float(section["first_width"]), float(section["last_width"]), t),
				"stage_line": section_index > 0 and i == 0,
				"stage": section_index,
			})
			near -= BLOCK_LENGTH

	return out


## The centre of the ridge's finish pad (top face): 384 units long, one more
## descent step below the last block and a 160-unit gap past it.
static func ridge_pad() -> Vector3:
	var blocks := ridge_blocks()
	var last: Dictionary = blocks[blocks.size() - 1]
	return Vector3(RIDGE_X, float(last["y"]) - 48.0, float(last["far"]) - 160.0 - 192.0)


## The bonus: a two-ramp surf descent onto a pad.
##
## [b]Surf on a bhop map, deliberately.[/b] A bonus track is a whole second route with
## its own records, and making it the same thing as the main route wastes it. It is
## also the cheapest proof that a track is a route and not a game mode: one map, one
## timer, one records table, and the two tracks are played completely differently.
func _build_bonus() -> void:
	# Far enough out that it is not in the main route's view.
	#
	# It was at 2048 and the screenshot is why it is not: a 1536-unit-tall surf ramp
	# that close fills a third of the screen from the start pad, so the first thing a
	# player on the MAIN track sees is the bonus. A bonus is a thing you go and find.
	var x := BONUS_X

	G2GGeometry.box(
		self, Vector3(x, FLOOR_Y + 1024.0 - BLOCK_THICKNESS * 0.5, START_Z),
		Vector3(512.0, BLOCK_THICKNESS, 512.0), G2GGeometry.ROLE_BONUS
	)

	# Two ramps facing each other, which is what a surf section is: a player rides the
	# face of one, crosses, and rides the other.
	for i in range(2):
		var side := 1.0 if i == 0 else -1.0
		G2GGeometry.ramp(
			self,
			Vector3(x + side * 384.0, FLOOR_Y + 320.0, START_Z - 1536.0),
			Vector3(64.0, 1536.0, 2560.0),
			side * 45.0,
			Vector3.FORWARD,
			G2GGeometry.ROLE_RAMP
		)

	G2GGeometry.box(
		self, Vector3(x, FLOOR_Y - 384.0 - BLOCK_THICKNESS * 0.5, START_Z - 3072.0),
		Vector3(768.0, BLOCK_THICKNESS, 768.0), G2GGeometry.ROLE_END
	)


## Every block on the main course, in order, as plain dictionaries.
##
## [b]Static, and the single source of truth for both the geometry and the zones.[/b]
## `_build` places a mesh at each entry and `build_zones` draws a stage line across the
## last block of each stage — both from this. A map that computed the two separately is
## a map whose stage lines drift off their blocks the first time somebody changes a gap,
## and nothing anywhere reports it: the run still finishes, the splits are just taken
## somewhere else.
static func _course() -> Array:
	var out: Array = []

	# The cursor: where the next block goes, and which way the course is heading.
	# Heading is a yaw in degrees, 0 being -Z, which is the direction the start pad
	# faces.
	var x := 0.0
	var y := FLOOR_Y
	var z := START_Z - 320.0
	var yaw := 0.0

	for stage_index in range(STAGES.size()):
		var stage: Dictionary = STAGES[stage_index]
		var blocks := int(stage["blocks"])
		var kind := String(stage["kind"])

		for i in range(blocks):
			var t := float(i) / float(maxi(blocks - 1, 1))
			var gap := lerpf(float(stage["first_gap"]), float(stage["last_gap"]), t)
			var width := BLOCK_WIDTH
			var offset := 0.0

			match kind:
				"turn":
					# 90 degrees over the stage. Spread across every block rather than
					# taken in one, because a bhop turn is made by strafing THROUGH it:
					# a single right angle is a wall a player hits at 300 u/s.
					yaw = lerpf(0.0, 90.0, t)
				"climb":
					y += CLIMB_STEP
				"drop":
					y -= DROP_STEP
					width = NARROW_WIDTH
				"zigzag":
					offset = ZIGZAG_OFFSET * (1.0 if i % 2 == 0 else -1.0)
				_:
					pass

			# Step the cursor along the heading, then place the block. The sideways
			# offset is applied across the heading, so a zigzag on a turned section
			# still zigzags across the course rather than across the world.
			var forward := Vector3(
				-sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw))
			)
			var across := Vector3(
				cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw))
			)

			var step := BLOCK_LENGTH + gap if i > 0 else BLOCK_LENGTH
			x += forward.x * step
			z += forward.z * step

			var at := Vector3(x, y, z) + across * offset

			out.append({
				"stage": stage_index + 1,
				"kind": kind,
				"x": at.x,
				"y": at.y,
				"z": at.z,
				"yaw": yaw,
				"width": width,
				"stage_end": i == blocks - 1,
			})

	return out


## The last block of stage [param number], counted from 1.
static func stage_block(number: int) -> Dictionary:
	var course := _course()

	for block: Dictionary in course:
		if int(block["stage"]) == number and bool(block["stage_end"]):
			return block

	return {}


func timer_zones() -> DotTimerZoneSet:
	return build_zones()


static func build_zones() -> DotTimerZoneSet:
	var zones := DotTimerZoneSet.new()
	zones.map_id = &"bhop_g2g_stages"
	zones.meta["tier"] = 4
	zones.meta["author"] = "g2gfast"

	var main := DotTimerTrack.MAIN
	var course := _course()
	var last: Dictionary = course[course.size() - 1]

	zones.add(zone_box(DotTimerZone.Kind.START, main,
		Vector3(-192.0, FLOOR_Y, START_Z - 320.0),
		Vector3(192.0, FLOOR_Y + 192.0, START_Z + 320.0)))

	# The finish, on the pad past the last block. Axis-aligned even though the course
	# ends turned: a zone is an AABB, so a box drawn around a rotated pad is bigger than
	# the pad. That is correct here — a player can only arrive at it along the course —
	# and it is why the box is drawn from the pad's centre rather than its corners.
	var end_at := _pad_centre(last)
	zones.add(zone_box(DotTimerZone.Kind.END, main,
		end_at - Vector3(256.0, 0.0, 256.0),
		end_at + Vector3(256.0, 192.0, 256.0)))

	# One stage line per stage boundary, on the block the geometry drew in the finish
	# colour. There are STAGES.size() - 1 of them: the last stage ends at the FINISH,
	# not at a stage line, and a stage zone drawn on top of the finish would split the
	# run at the same instant it ended.
	for number in range(1, STAGES.size()):
		var block := stage_block(number)

		if block.is_empty():
			continue

		var at := Vector3(
			float(block["x"]), float(block["y"]), float(block["z"])
		)

		zones.add(zone_stage(
			main, number,
			at - Vector3(224.0, 0.0, 224.0),
			at + Vector3(224.0, 192.0, 224.0),
			at + Vector3(0.0, 16.0, 0.0),
			float(block["yaw"]) + 180.0
		))

	# The pit. Everything below the course, which on a map that climbs and drops has to
	# be measured from the LOWEST block rather than from the floor — the drop section
	# ends below where it started, and a pit at y = 0 would be a ceiling under it.
	var lowest := FLOOR_Y

	for block: Dictionary in course:
		lowest = minf(lowest, float(block["y"]))

	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, main,
		Vector3(-16384.0, lowest - 4096.0, -16384.0),
		Vector3(16384.0, lowest - 256.0, 16384.0)))

	zones.add(zone_spawn(main, Vector3(0.0, FLOOR_Y + 8.0, START_Z + 128.0), 0.0))

	# The bonus: the surf descent.
	var bonus := DotTimerTrack.of_bonus(1)

	zones.add(zone_box(DotTimerZone.Kind.START, bonus,
		Vector3(BONUS_X - 256.0, FLOOR_Y + 1024.0, START_Z - 256.0),
		Vector3(BONUS_X + 256.0, FLOOR_Y + 1216.0, START_Z + 256.0)))
	zones.add(zone_box(DotTimerZone.Kind.END, bonus,
		Vector3(BONUS_X - 384.0, FLOOR_Y - 384.0, START_Z - 3456.0),
		Vector3(BONUS_X + 384.0, FLOOR_Y - 128.0, START_Z - 2688.0)))
	zones.add(zone_spawn(
		bonus, Vector3(BONUS_X, FLOOR_Y + 1032.0, START_Z + 128.0), 0.0
	))

	# The bonus's own pit. A RESPAWN carries a track, and the main route's catches
	# nobody on this one: until `[track-zone-1]` asked every route on every map, a
	# player who came off either ramp fell for ever. Under the lowest thing on the
	# whole map -- the bonus's finish pad sits below the main course -- so neither
	# route's geometry is ever inside it.
	var bonus_floor := minf(lowest, FLOOR_Y - 384.0 - BLOCK_THICKNESS)
	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, bonus,
		Vector3(-16384.0, bonus_floor - 4096.0, -16384.0),
		Vector3(16384.0, bonus_floor - 256.0, 16384.0)))

	# Bonus 2, the ridge: a start, two stage splits, a finish, a spawn and a pit.
	var ridge := DotTimerTrack.of_bonus(2)
	var pad := ridge_pad()

	zones.add(zone_box(DotTimerZone.Kind.START, ridge,
		Vector3(RIDGE_X - 128.0, FLOOR_Y, START_Z - RIDGE_PAD_LENGTH * 0.5),
		Vector3(RIDGE_X + 128.0, FLOOR_Y + 192.0, START_Z + RIDGE_PAD_LENGTH * 0.5)))
	# The pad's last 320 units: it begins 64 in from the pad's near edge, so a player
	# has landed rather than grazed the lip when the clock stops.
	zones.add(zone_box(DotTimerZone.Kind.END, ridge,
		Vector3(RIDGE_X - 128.0, pad.y, pad.z - 192.0),
		Vector3(RIDGE_X + 128.0, pad.y + 192.0, pad.z + 128.0)))

	for block: Dictionary in ridge_blocks():
		if not bool(block["stage_line"]):
			continue
		var half := float(block["width"]) * 0.5
		zones.add(zone_stage(
			ridge, int(block["stage"]),
			Vector3(RIDGE_X - half, float(block["y"]), float(block["far"])),
			Vector3(RIDGE_X + half, float(block["y"]) + 192.0, float(block["near"])),
			Vector3(RIDGE_X, float(block["y"]) + 16.0, float(block["near"]) - BLOCK_LENGTH * 0.5),
			# Facing down the route: yaw 0 is -Z here, as the spawn zones use. The main
			# route's `yaw + 180` faces back up it and is `[stage-yaw-1]`'s, not copied.
			0.0
		))

	zones.add(zone_spawn(ridge, Vector3(RIDGE_X, FLOOR_Y + 8.0, START_Z + 128.0), 0.0))
	zones.add(zone_box(DotTimerZone.Kind.RESPAWN, ridge,
		Vector3(-16384.0, bonus_floor - 4096.0, -16384.0),
		Vector3(16384.0, pad.y - BLOCK_THICKNESS - 256.0, 16384.0)))

	return zones


## The centre of the finish pad, which sits 384 units past the last block along its
## own heading.
static func _pad_centre(last: Dictionary) -> Vector3:
	var yaw := float(last["yaw"])
	var forward := Vector3(-sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))

	return Vector3(
		float(last["x"]), float(last["y"]), float(last["z"])
	) + forward * 384.0

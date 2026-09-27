extends RefCounted

const G2GUnits := preload("g2g_units.gd")
const G2GReach := preload("g2g_reach.gd")

## A slot and reach sweep over a hand-built map's boxes (`[gate-sweep-1]`,
## `[gate-sweep-2]`): where two solids leave a crack narrower than a player, what a player
## can stand on, what they can get to from a spawn or a `!s<n>`, and what they cannot get
## back out of.
##
## [b]Why a map needs this when its routes are already driven and measured.[/b]
## `headless_run` asks about the bodies a course NAMES. Nothing asked about the ones it
## does not: the top of a back wall, the floor a player who misses a ramp lands on, a
## crack between a ramp and a pad. Every one of those is found by a player on a live
## server, reported as "stuck", and fixed with a `!r`. This asks the geometry instead.
##
## [b]Everything is in genre units[/b], read off the same [DotFpsTunables] the server
## applies: the hull is [code]2 × radius[/code] (32 u, the genre's hull), the headroom a
## crouched player (54 u), the step [code]sv_stepsize[/code] (18 u), the slope limit
## [code]max_slope[/code] (45.57°), and a jump [G2GReach]'s RUN reach and climb limit.
##
## [b]How it works[/b] (game-playground's `PlaygroundMapSurvey`, reimplemented here — a copy
## per project is the family's rule). The boxes are read off the built map and rasterised
## into columns on a [constant CELL] grid: each column is the list of solid spans a
## vertical line through it passes. The top of a span is somewhere to stand if the face it
## leaves through is no steeper than the slope limit, there is a crouched player's headroom
## above it, and nothing in the neighbouring columns intrudes into the hull. Standable
## cells are joined into REGIONS by walking (a step of at most the step height), and
## regions into a directed graph by: dropping off an edge; sliding down the fall line of a
## face nobody can stand on; a RUN jump (from the lip at run speed) inside
## [method G2GReach.run_reach]; and the consecutive bodies of every CHAIN course the map
## declares (`G2GMap.add_course`), provided [method G2GReach.chain] says a perfect strafe
## runs it — the chain is `headless_run`'s question and its answer is reused, not redone.
##
## - [b]Unreached[/b]: a region no spawn and no stage destination leads to, and that the
##   caller has not declared.
## - [b]Trapped[/b]: a region a spawn leads to that leads to none of: a spawn, a finish
##   zone, a respawn zone, or a fall into one. A player there can only type `!r`.
## - [b]Slots[/b]: two solids with air between them narrower than the hull, side by side
##   over more than a step. A passage that looks open and is not, or a crack that holds a
##   body.
##
## [b]What reach means on a surf map, and why it stops short there on purpose.[/b] A surf
## ramp is steeper than anybody can stand on, so it has no cells: it is a surface a player
## slides on, not a floor. What a player on one reaches is decided by their SPEED, and on
## a ramp speed is the rider's — an air-strafe adds up to [code]sv_maxairwishspeed[/code]
## a tick, to [code]sv_maxvelocity[/code] — so any bound on it is either "everywhere" or a
## guess at a player's skill, and a flood fill over either answers nothing. The survey
## floods only what needs no skill: walking, a step, a drop, a RUN jump, and a slide down a
## face's FALL LINE (straight down it, off its low edge, onto whatever is below). A surf
## route whose next surface is reached by a carried flight — off the end of a bank, over a
## gap to the next one — reads as unreached, which errs toward reporting, and the caller
## declares it with the check that rides it. The standable parts (pads, floors, platforms,
## finishes) are surveyed fully: slots, headroom, trapped and spawns all mean on a surf map
## exactly what they mean on a bhop map.
##
## [b]What it does not do, on purpose.[/b] A jump is judged edge to edge from above, not
## swept through the air. A tilted box's slot distance is sampled along its edges every
## [constant EDGE_SAMPLE] units rather than solved exactly. Each is a place to extend it
## the day a map needs it.

## Grid spacing, units. Half the hull, so a cell's eight neighbours are the hull.
const CELL := 16.0

## Units between the points sampled along a tilted solid's edges for the slot distance.
const EDGE_SAMPLE := 8.0

## Most slide steps followed down one face before the survey gives up on it.
const SLIDE_LIMIT := 4000

## Units. How far above the highest span a slide or a fall may still count a top as
## "at or below": the tilt of one cell of a steep face.
const _TOL := 2.0


## One solid box, in units.
class Solid:
	extends RefCounted
	var xform: Transform3D
	var inverse: Transform3D
	var size: Vector3
	var bounds: AABB
	var upright: bool
	## The body it came from, so a course can name it; null for a fixture.
	var body: Node3D = null


## One zone, in units. The timer's zones are in metres; the survey converts at the edge.
class Box:
	extends RefCounted
	var kind: int
	var from: Vector3
	var to: Vector3

	func has(at: Vector3) -> bool:
		return at.x >= from.x and at.x <= to.x and at.y >= from.y and at.y <= to.y \
			and at.z >= from.z and at.z <= to.z


var solids: Array[Solid] = []

# From the tunables, in units.
var hull := 32.0
var headroom := 54.0
var step := 18.0
var climb := 51.3
var cos_limit := 0.7
var _tunables: DotFpsTunables = null
var _tick_rate := 128

var _origin := Vector2.ZERO
var _nx := 0
var _nz := 0

# Per column (ix + iz * _nx), the merged spans: [bottom, top, standable, nx, nz] * n.
var _spans: Dictionary = {}
var _top_max := PackedFloat32Array()
var _bottom_min := PackedFloat32Array()

# Standable cells: their column, their height, and their region.
var _node_col := PackedInt32Array()
var _node_y := PackedFloat32Array()
var _node_region := PackedInt32Array()
var _col_first := PackedInt32Array()
var _col_count := PackedInt32Array()

var _parent := PackedInt32Array()

var _region_low: Array[Vector3] = []
var _region_high: Array[Vector3] = []
var _region_count := PackedInt32Array()
var _region_edge: Array[PackedInt32Array] = []

var _out: Array[Dictionary] = []
var _escapes: Dictionary = {}
var _void_falls := 0
var _course_links := 0
var _course_problems: Array[String] = []


## Surveys a built map (its [method G2GMap._build] has run; it need not be in the tree).
##
## [param starts] are the points players are put at, in units: spawns and stage
## destinations. [param declared] is `[{box: AABB (units), why: String}]` for areas the
## caller knows no start reaches. Returns
## `{cells, reached_cells, regions, slots, unreached, trapped, startless,
## stale_declarations, void_falls, course_links, course_problems, standable_tilted}`;
## every list is of human-readable lines.
static func survey(
	map: Node3D, zones: DotTimerZoneSet, starts: Array[Vector3], declared: Array,
	t: DotFpsTunables, tick_rate: int
) -> Dictionary:
	var s := new()
	s._configure(t, tick_rate)
	s._collect(map)
	var courses: Array = map.get("courses") if map.get("courses") != null else []
	return s._run(zones, starts, declared, courses)


## Surveys a list of solids directly: for a fixture that is not a map.
static func survey_solids(
	boxes: Array[Solid], zones: DotTimerZoneSet, starts: Array[Vector3], declared: Array,
	t: DotFpsTunables, tick_rate: int
) -> Dictionary:
	var s := new()
	s._configure(t, tick_rate)
	s.solids = boxes
	return s._run(zones, starts, declared, [])


## A solid from a centre, a size and an optional basis, in units — `G2GGeometry.box`'s
## arguments.
static func solid(at: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> Solid:
	var out := Solid.new()
	out.xform = Transform3D(basis, at)
	out.inverse = out.xform.affine_inverse()
	out.size = size
	out.upright = basis.y.normalized().dot(Vector3.UP) > 0.9999

	var low := Vector3(INF, INF, INF)
	var high := -low

	for corner in _corners(out):
		low = low.min(corner)
		high = high.max(corner)

	out.bounds = AABB(low, high - low)
	return out


static func _corners(s: Solid) -> PackedVector3Array:
	var half := s.size * 0.5
	var out := PackedVector3Array()
	for i in range(8):
		out.append(s.xform * Vector3(
			half.x * (1.0 if i & 1 else -1.0),
			half.y * (1.0 if i & 2 else -1.0),
			half.z * (1.0 if i & 4 else -1.0)
		))
	return out


func _configure(t: DotFpsTunables, tick_rate: int) -> void:
	_tunables = t
	_tick_rate = tick_rate
	hull = 2.0 * G2GUnits.to_units(t.radius)
	headroom = G2GUnits.to_units(t.crouch_height)
	step = G2GReach.step(t)
	climb = G2GReach.climb_limit(t)
	cos_limit = cos(t.max_slope_radians())


func _collect(map: Node3D) -> void:
	for child in map.get_children():
		var body := child as StaticBody3D

		if body == null:
			continue

		for part in body.get_children():
			var shape := part as CollisionShape3D

			if shape == null or not (shape.shape is BoxShape3D):
				continue

			var xform := body.transform * shape.transform
			var one := solid(
				G2GUnits.vector_to_units(xform.origin),
				G2GUnits.vector_to_units((shape.shape as BoxShape3D).size),
				xform.basis
			)
			one.body = body
			solids.append(one)


func _run(
	zones: DotTimerZoneSet, starts: Array[Vector3], declared: Array, courses: Array
) -> Dictionary:
	var slots := _slots()

	_rasterise()
	_find_cells()
	_join_regions()

	var boxes := _zone_boxes(zones)
	var pits: Array[Box] = []
	for box in boxes:
		if box.kind == DotTimerZone.Kind.RESPAWN:
			pits.append(box)

	_link_regions(boxes, pits)
	_link_courses(courses)

	# Forward from every start. A start in the air falls to whatever is under it, which
	# is what a player put there does.
	var from: Dictionary = {}
	var startless: Array[String] = []

	for at in starts:
		var node := _fall(at.x, at.z, at.y + _TOL, pits)
		if node == -1:
			node = _cell_near(at)

		if node >= 0:
			from[_node_region[node]] = true
			_escapes[_node_region[node]] = true
		else:
			startless.append("(%.0f, %.0f, %.0f)%s" % [
				at.x, at.y, at.z, " falls into a pit" if node == -2 else " is over nothing",
			])

	var reached := _flood(from.keys(), _out)

	var back: Array[Dictionary] = []
	for _i in range(_out.size()):
		back.append({})
	for a in range(_out.size()):
		for b: int in _out[a]:
			back[b][a] = true

	var safe := _flood(_escapes.keys(), back)

	var unreached: Array[String] = []
	var trapped: Array[String] = []
	var reached_cells := 0
	var used: Dictionary = {}

	for region in range(_region_count.size()):
		var what := _describe(region)

		if not reached.has(region):
			var by := _declared_by(region, declared)
			if by < 0:
				unreached.append(what)
			else:
				used[by] = true
		else:
			reached_cells += _region_count[region]
			if not safe.has(region):
				trapped.append(what)

	# A declaration that covers nothing unreached is stale: the ground it excused is
	# reached now, or gone, and leaving it would excuse the next thing built there.
	var stale: Array[String] = []
	for i in range(declared.size()):
		if not used.has(i):
			stale.append(str((declared[i] as Dictionary).get("why", "declaration %d" % i)))

	return {
		"cells": _node_col.size(),
		"stale_declarations": stale,
		"reached_cells": reached_cells,
		"regions": _region_count.size(),
		"slots": slots,
		"unreached": unreached,
		"trapped": trapped,
		"startless": startless,
		"void_falls": _void_falls,
		"course_links": _course_links,
		"course_problems": _course_problems,
		"standable_tilted": _standable_tilted(),
	}


func _describe(region: int) -> String:
	var low := _region_low[region]
	var high := _region_high[region]
	return "%d cells from (%.0f, %.0f, %.0f) to (%.0f, %.0f, %.0f)" % [
		_region_count[region], low.x, low.y, low.z, high.x, high.y, high.z,
	]


static func _zone_boxes(zones: DotTimerZoneSet) -> Array[Box]:
	var out: Array[Box] = []
	if zones == null:
		return out
	for zone in zones.zones:
		if zone.shape != DotTimerZone.Shape.BOX:
			continue
		var box := Box.new()
		box.kind = zone.kind
		box.from = G2GUnits.vector_to_units(zone.from)
		box.to = G2GUnits.vector_to_units(zone.to)
		out.append(box)
	return out


## Tilted solids whose upward face is standable: a slab somebody may call a ramp that the
## movement treats as floor. Reported, not judged — a walkable ramp is a legitimate
## thing to build, and a SURF ramp that is walkable is not surf.
func _standable_tilted() -> Array[String]:
	var out: Array[String] = []
	for s in solids:
		if s.upright:
			continue
		# The broad face: the one across the slab's thinnest dimension. The other four
		# are its edges, a slab's thickness across, and a 60° bank's edge is 30° from
		# level — standable, and not what anybody means by the ramp.
		var thin := 0
		for axis in range(1, 3):
			if s.size[axis] < s.size[thin]:
				thin = axis
		var best := absf(s.xform.basis[thin].normalized().y)
		if best >= cos_limit:
			out.append("the slab at (%.0f, %.0f, %.0f), %.1f° from level" % [
				s.xform.origin.x, s.xform.origin.y, s.xform.origin.z, rad_to_deg(acos(best)),
			])
	return out


# --- Slots -------------------------------------------------------------------

func _slots() -> Array[String]:
	var found: Array[String] = []

	for i in range(solids.size()):
		var a := solids[i]

		for j in range(i + 1, solids.size()):
			var b := solids[j]

			if not a.bounds.grow(hull).intersects(b.bounds):
				continue

			# Side by side over more than a step: a crack between two floors a player
			# steps over is not a passage.
			var band := minf(a.bounds.end.y, b.bounds.end.y) \
				- maxf(a.bounds.position.y, b.bounds.position.y)
			if band <= step:
				continue

			var gap := _gap(a, b)

			if gap > 0.01 and gap < hull:
				var at := (a.xform.origin + b.xform.origin) * 0.5
				found.append("%.0f u between the solids at (%.0f, %.0f, %.0f) and (%.0f, %.0f, %.0f), near (%.0f, %.0f, %.0f)" % [
					gap, a.xform.origin.x, a.xform.origin.y, a.xform.origin.z,
					b.xform.origin.x, b.xform.origin.y, b.xform.origin.z, at.x, at.y, at.z,
				])

	return found


## The clear air between two solids. Two upright boxes are measured from above, exactly,
## and only where their facing sides run side by side for a hull's width (two boxes
## meeting at a corner are not a corridor). A tilted one is measured in 3D, sampled
## along both boxes' edges, which is where the least distance between two boxes lies.
func _gap(a: Solid, b: Solid) -> float:
	if a.upright and b.upright:
		var pa := _footprint(a)
		var pb := _footprint(b)

		if _polygons_overlap(pa, pb):
			return 0.0
		if not _side_by_side(pa, pb):
			return INF

		var best := INF
		for k in range(4):
			for p in pb:
				best = minf(best, _point_segment(p, pa[k], pa[(k + 1) % 4]))
			for p in pa:
				best = minf(best, _point_segment(p, pb[k], pb[(k + 1) % 4]))
		return best

	if _boxes_overlap(a, b):
		return 0.0

	return minf(_edge_distance(a, b), _edge_distance(b, a))


## Whether two footprints face each other along at least a hull's width: projected on
## the axis they are separated along, the other axis's extents overlap by that much.
func _side_by_side(pa: PackedVector2Array, pb: PackedVector2Array) -> bool:
	for poly in [pa, pb]:
		var p := poly as PackedVector2Array
		for k in range(2):
			var along := (p[(k + 1) % 4] - p[k]).normalized()
			var across := Vector2(-along.y, along.x)
			var a_lo := INF
			var a_hi := -INF
			var b_lo := INF
			var b_hi := -INF
			var c_lo := INF
			var c_hi := -INF
			var d_lo := INF
			var d_hi := -INF
			for v in pa:
				a_lo = minf(a_lo, v.dot(along))
				a_hi = maxf(a_hi, v.dot(along))
				c_lo = minf(c_lo, v.dot(across))
				c_hi = maxf(c_hi, v.dot(across))
			for v in pb:
				b_lo = minf(b_lo, v.dot(along))
				b_hi = maxf(b_hi, v.dot(along))
				d_lo = minf(d_lo, v.dot(across))
				d_hi = maxf(d_hi, v.dot(across))
			# Separated across this edge's normal, overlapping along the edge.
			var separated := c_hi < d_lo or d_hi < c_lo
			if separated and minf(a_hi, b_hi) - maxf(a_lo, b_lo) >= hull:
				return true
	return false


## The least distance from any point along [param a]'s edges to [param b].
static func _edge_distance(a: Solid, b: Solid) -> float:
	var corners := _corners(a)
	var best := INF
	# The 12 edges of a box: pairs of corner indices differing in one bit.
	for i in range(8):
		for bit in [1, 2, 4]:
			var j: int = i | bit
			if j == i:
				continue
			var p := corners[i]
			var q := corners[j]
			var n := maxi(1, int(ceil(p.distance_to(q) / EDGE_SAMPLE)))
			for k in range(n + 1):
				best = minf(best, _point_box(p.lerp(q, float(k) / float(n)), b))
	return best


## Distance from [param p] to solid [param s], 0 inside it.
static func _point_box(p: Vector3, s: Solid) -> float:
	var local := s.inverse * p
	var half := s.size * 0.5
	var d := Vector3(
		maxf(absf(local.x) - half.x, 0.0),
		maxf(absf(local.y) - half.y, 0.0),
		maxf(absf(local.z) - half.z, 0.0)
	)
	return d.length()


## Whether two boxes intersect or touch, by the separating axis test.
static func _boxes_overlap(a: Solid, b: Solid) -> bool:
	var axes: Array[Vector3] = []
	for s in [a, b]:
		for k in range(3):
			axes.append((s as Solid).xform.basis[k].normalized())
	for i in range(3):
		for j in range(3):
			var cross := a.xform.basis[i].normalized().cross(b.xform.basis[j].normalized())
			if cross.length() > 1e-6:
				axes.append(cross.normalized())

	var ca := _corners(a)
	var cb := _corners(b)

	for axis in axes:
		var a_lo := INF
		var a_hi := -INF
		var b_lo := INF
		var b_hi := -INF
		for v in ca:
			a_lo = minf(a_lo, v.dot(axis))
			a_hi = maxf(a_hi, v.dot(axis))
		for v in cb:
			b_lo = minf(b_lo, v.dot(axis))
			b_hi = maxf(b_hi, v.dot(axis))
		if a_hi < b_lo - 0.01 or b_hi < a_lo - 0.01:
			return false
	return true


static func _footprint(s: Solid) -> PackedVector2Array:
	var x := s.xform.basis.x * s.size.x * 0.5
	var z := s.xform.basis.z * s.size.z * 0.5
	var c := s.xform.origin
	var out := PackedVector2Array()
	for corner in [c - x - z, c + x - z, c + x + z, c - x + z]:
		out.append(Vector2((corner as Vector3).x, (corner as Vector3).z))
	return out


static func _polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		var p := poly as PackedVector2Array
		for k in range(p.size()):
			var edge := p[(k + 1) % p.size()] - p[k]
			var axis := Vector2(-edge.y, edge.x)
			var a_lo := INF
			var a_hi := -INF
			var b_lo := INF
			var b_hi := -INF
			for v in a:
				a_lo = minf(a_lo, v.dot(axis))
				a_hi = maxf(a_hi, v.dot(axis))
			for v in b:
				b_lo = minf(b_lo, v.dot(axis))
				b_hi = maxf(b_hi, v.dot(axis))
			if a_hi < b_lo - 1e-4 or b_hi < a_lo - 1e-4:
				return false
	return true


static func _point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Columns -----------------------------------------------------------------

func _rasterise() -> void:
	var low := Vector2(INF, INF)
	var high := -low

	for s in solids:
		low = low.min(Vector2(s.bounds.position.x, s.bounds.position.z))
		high = high.max(Vector2(s.bounds.end.x, s.bounds.end.z))

	# One cell of air round everything, so an edge of the map is an edge.
	_origin = low - Vector2(CELL, CELL)
	_nx = int(ceil((high.x - low.x) / CELL)) + 3
	_nz = int(ceil((high.y - low.y) / CELL)) + 3

	var raw: Dictionary = {}

	for s in solids:
		var ix0 := maxi(0, int(floor((s.bounds.position.x - _origin.x) / CELL)))
		var ix1 := mini(_nx - 1, int(floor((s.bounds.end.x - _origin.x) / CELL)))
		var iz0 := maxi(0, int(floor((s.bounds.position.z - _origin.y) / CELL)))
		var iz1 := mini(_nz - 1, int(floor((s.bounds.end.z - _origin.y) / CELL)))
		var up := s.inverse.basis.y
		var half := s.size * 0.5

		if s.xform.basis.is_equal_approx(Basis.IDENTITY):
			var span := [s.bounds.position.y, s.bounds.end.y, true, 0.0, 0.0]
			var ax0 := maxi(ix0, int(ceil((s.bounds.position.x - _origin.x) / CELL - 0.5)))
			var ax1 := mini(ix1, int(floor((s.bounds.end.x - _origin.x) / CELL - 0.5)))
			var az0 := maxi(iz0, int(ceil((s.bounds.position.z - _origin.y) / CELL - 0.5)))
			var az1 := mini(iz1, int(floor((s.bounds.end.z - _origin.y) / CELL - 0.5)))
			for iz in range(az0, az1 + 1):
				for ix in range(ax0, ax1 + 1):
					var col := ix + iz * _nx
					var list: Array = raw.get(col, [])
					list.append(span)
					raw[col] = list
			continue

		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var x := _origin.x + (float(ix) + 0.5) * CELL
				var z := _origin.y + (float(iz) + 0.5) * CELL
				var a := s.inverse * Vector3(x, 0.0, z)

				# A vertical line through the box, in the box's own space: a + y * up.
				var t_in := -INF
				var t_out := INF
				var exit_axis := -1
				var missed := false

				for axis in range(3):
					if absf(up[axis]) < 1e-9:
						if absf(a[axis]) > half[axis]:
							missed = true
							break
						continue

					var t1 := (-half[axis] - a[axis]) / up[axis]
					var t2 := (half[axis] - a[axis]) / up[axis]
					t_in = maxf(t_in, minf(t1, t2))

					if maxf(t1, t2) < t_out:
						t_out = maxf(t1, t2)
						exit_axis = axis

				if missed or t_in >= t_out or exit_axis < 0:
					continue

				var local_normal := Vector3.ZERO
				local_normal[exit_axis] = signf(up[exit_axis])
				var normal := (s.xform.basis * local_normal).normalized()
				var standable := normal.y >= cos_limit

				var col := ix + iz * _nx
				var list: Array = raw.get(col, [])
				list.append([t_in, t_out, standable, normal.x, normal.z])
				raw[col] = list

	_top_max.resize(_nx * _nz)
	_top_max.fill(-INF)
	_bottom_min.resize(_nx * _nz)
	_bottom_min.fill(INF)

	for col: int in raw:
		var list: Array = raw[col]

		if list.size() == 1:
			var only := PackedFloat32Array()
			_push_span(only, list[0])
			_spans[col] = only
			_bottom_min[col] = only[0]
			_top_max[col] = only[1]
			continue

		list.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))

		var merged := PackedFloat32Array()
		var current: Array = (list[0] as Array).duplicate()

		for k in range(1, list.size()):
			var next: Array = list[k]
			if float(next[0]) <= float(current[1]) + 0.5:
				if float(next[1]) > float(current[1]) + 0.01:
					current[1] = next[1]
					current[2] = next[2]
					current[3] = next[3]
					current[4] = next[4]
				elif absf(float(next[1]) - float(current[1])) <= 0.01 and bool(next[2]):
					current[2] = true
			else:
				_push_span(merged, current)
				current = next.duplicate()

		_push_span(merged, current)
		_spans[col] = merged
		_bottom_min[col] = merged[0]
		_top_max[col] = merged[merged.size() - 4]


static func _push_span(out: PackedFloat32Array, span: Array) -> void:
	out.append(float(span[0]))
	out.append(float(span[1]))
	out.append(1.0 if bool(span[2]) else 0.0)
	out.append(float(span[3]))
	out.append(float(span[4]))


const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const SIDES: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


func _solid_between(col: int, y0: float, y1: float) -> bool:
	if _top_max[col] <= y0 or _bottom_min[col] >= y1:
		return false
	var spans: PackedFloat32Array = _spans.get(col, PackedFloat32Array())
	for k in range(0, spans.size(), 5):
		if spans[k] < y1 and spans[k + 1] > y0:
			return true
	return false


func _too_tall(col: int, y: float) -> bool:
	return _top_max[col] > y + climb


func _floor_near(col: int, y: float) -> bool:
	if _top_max[col] < y - step:
		return false
	var spans: PackedFloat32Array = _spans.get(col, PackedFloat32Array())
	for k in range(0, spans.size(), 5):
		if spans[k + 2] > 0.5 and absf(spans[k + 1] - y) <= step:
			return true
	return false


func _find_cells() -> void:
	_col_first.resize(_nx * _nz)
	_col_first.fill(-1)
	_col_count.resize(_nx * _nz)
	_col_count.fill(0)

	var cols: Array = _spans.keys()
	cols.sort()

	for col: int in cols:
		var spans: PackedFloat32Array = _spans[col]
		var ix := col % _nx
		var iz := col / _nx
		for k in range(0, spans.size(), 5):
			if spans[k + 2] < 0.5:
				continue

			var y := spans[k + 1]

			if k + 5 < spans.size() and spans[k + 5] - y < headroom:
				continue

			var clear := true
			for d in NEIGHBOURS:
				var jx := ix + d.x
				var jz := iz + d.y
				if jx < 0 or jz < 0 or jx >= _nx or jz >= _nz:
					continue
				if _solid_between(jx + jz * _nx, y + step, y + headroom):
					clear = false
					break

			if not clear:
				continue

			if _col_count[col] == 0:
				_col_first[col] = _node_col.size()
			_col_count[col] += 1
			_node_col.append(col)
			_node_y.append(y)


# --- Regions ------------------------------------------------------------------

func _find(n: int) -> int:
	while _parent[n] != n:
		_parent[n] = _parent[_parent[n]]
		n = _parent[n]
	return n


func _join_regions() -> void:
	_parent.resize(_node_col.size())
	for n in range(_node_col.size()):
		_parent[n] = n

	for n in range(_node_col.size()):
		var col := _node_col[n]
		var ix := col % _nx
		var iz := col / _nx

		for d in SIDES:
			var jx := ix + d.x
			var jz := iz + d.y
			if jx < 0 or jz < 0 or jx >= _nx or jz >= _nz:
				continue
			var jcol := jx + jz * _nx
			for m in range(_col_first[jcol], _col_first[jcol] + _col_count[jcol]):
				if absf(_node_y[m] - _node_y[n]) <= step:
					var ra := _find(n)
					var rb := _find(m)
					if ra != rb:
						_parent[ra] = rb

	var index: Dictionary = {}
	_node_region.resize(_node_col.size())

	for n in range(_node_col.size()):
		var root := _find(n)
		if not index.has(root):
			index[root] = index.size()
			_region_low.append(Vector3(INF, INF, INF))
			_region_high.append(Vector3(-INF, -INF, -INF))
			_region_count.append(0)
			_region_edge.append(PackedInt32Array())
			_out.append({})

		var r: int = index[root]
		_node_region[n] = r
		var at := _node_at(n)
		_region_low[r] = _region_low[r].min(at)
		_region_high[r] = _region_high[r].max(at)
		_region_count[r] += 1


func _node_at(n: int) -> Vector3:
	var col := _node_col[n]
	return Vector3(
		_origin.x + (float(col % _nx) + 0.5) * CELL,
		_node_y[n],
		_origin.y + (float(col / _nx) + 0.5) * CELL
	)


func _link_regions(boxes: Array[Box], pits: Array[Box]) -> void:
	# Standing in a finish or a reset is a way out.
	for box in boxes:
		if box.kind != DotTimerZone.Kind.END and box.kind != DotTimerZone.Kind.RESPAWN:
			continue

		var ix0 := maxi(0, int(floor((box.from.x - _origin.x) / CELL)))
		var ix1 := mini(_nx - 1, int(floor((box.to.x - _origin.x) / CELL)))
		var iz0 := maxi(0, int(floor((box.from.z - _origin.y) / CELL)))
		var iz1 := mini(_nz - 1, int(floor((box.to.z - _origin.y) / CELL)))

		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var zcol := ix + iz * _nx
				for n in range(_col_first[zcol], _col_first[zcol] + _col_count[zcol]):
					if box.has(_node_at(n) + Vector3(0.0, 8.0, 0.0)):
						_escapes[_node_region[n]] = true

	for n in range(_node_col.size()):
		var region := _node_region[n]
		var at := _node_at(n)
		var col := _node_col[n]
		var ix := col % _nx
		var iz := col / _nx
		var edge := false

		for d in SIDES:
			var jx := ix + d.x
			var jz := iz + d.y
			var level := false

			if jx >= 0 and jz >= 0 and jx < _nx and jz < _nz:
				var ncol := jx + jz * _nx
				for m in range(_col_first[ncol], _col_first[ncol] + _col_count[ncol]):
					if absf(_node_y[m] - _node_y[n]) <= step:
						level = true
						break

			if level:
				continue

			var jcol := jx + jz * _nx
			var inside_grid := jx >= 0 and jz >= 0 and jx < _nx and jz < _nz

			if inside_grid and _solid_between(jcol, at.y + step, at.y + headroom):
				if not _too_tall(jcol, at.y):
					edge = true
				continue

			if inside_grid and _floor_near(jcol, at.y):
				var kx := jx + d.x
				var kz := jz + d.y
				var beyond := kx >= 0 and kz >= 0 and kx < _nx and kz < _nz
				if not (beyond and _solid_between(kx + kz * _nx, at.y + step, at.y + headroom)
						and _too_tall(kx + kz * _nx, at.y)):
					edge = true
				continue

			edge = true

			var x := _origin.x + (float(jx) + 0.5) * CELL
			var z := _origin.y + (float(jz) + 0.5) * CELL
			var landed := _fall(x, z, at.y, pits)

			if landed >= 0 and _node_region[landed] != region:
				_out[region][_node_region[landed]] = true
			elif landed == -2:
				_escapes[region] = true

		if edge:
			_region_edge[region].append(n)

	_link_jumps()


## Where a player who leaves the ground over (x, z) at [param y] comes to rest: a cell,
## -2 for a fall into a respawn volume, or -1 for a fall into nothing. A face nobody can
## stand on is slid down along its fall line, one cell at a time.
func _fall(x: float, z: float, y: float, pits: Array[Box]) -> int:
	var cx := x
	var cz := z
	var top := y

	for _i in range(SLIDE_LIMIT):
		var ix := int(floor((cx - _origin.x) / CELL))
		var iz := int(floor((cz - _origin.y) / CELL))
		var col := ix + iz * _nx
		var spans: PackedFloat32Array = PackedFloat32Array()

		if ix >= 0 and iz >= 0 and ix < _nx and iz < _nz:
			spans = _spans.get(col, PackedFloat32Array())

		var best := -1
		for k in range(0, spans.size(), 5):
			if spans[k + 1] <= top + _TOL and (best < 0 or spans[k + 1] > spans[best + 1]):
				best = k

		if best < 0:
			for pit in pits:
				if cx >= pit.from.x and cx <= pit.to.x and cz >= pit.from.z \
						and cz <= pit.to.z and pit.from.y < top:
					return -2
			_void_falls += 1
			return -1

		if spans[best + 2] > 0.5:
			for n in range(_col_first[col], _col_first[col] + _col_count[col]):
				if absf(_node_y[n] - spans[best + 1]) < 0.01:
					return n
			# Standable but no room: a hull's width from something. Stop here.
			return -1

		var down := Vector2(spans[best + 3], spans[best + 4])
		if down.length() < 1e-4:
			return -1
		down = down.normalized() * CELL
		top = spans[best + 1]
		cx += down.x
		cz += down.y

	return -1


## A declared CHAIN course's bodies, linked in order, if [G2GReach] says a perfect strafe
## runs it from its start line. `headless_run` asserts the same verdict, so a course that
## is not a chain fails there; here it is simply not a way forward.
func _link_courses(courses: Array) -> void:
	for course: Object in courses:
		if int(course.get("kind")) != G2GReach.Kind.CHAIN:
			continue

		var bodies: Array = course.get("bodies")
		var routes := G2GReach.measure(bodies)
		if not bool(G2GReach.chain(routes, _tunables, _tick_rate, 1.0)["ok"]):
			_course_problems.append("%s is not a chain even strafing perfectly" % course.get("name"))
			continue

		var regions: Array[int] = []
		for body: Node3D in bodies:
			var node := _cell_on(body)
			if node < 0:
				_course_problems.append("%s: the body at %s has no standable cell on it" % [
					course.get("name"), G2GUnits.vector_to_units(body.transform.origin),
				])
			regions.append(_node_region[node] if node >= 0 else -1)

		for i in range(regions.size() - 1):
			if regions[i] >= 0 and regions[i + 1] >= 0 and regions[i] != regions[i + 1]:
				if not _out[regions[i]].has(regions[i + 1]):
					_out[regions[i]][regions[i + 1]] = true
					_course_links += 1


## The standable cell on top of a level body's centre.
func _cell_on(body: Node3D) -> int:
	for s in solids:
		if s.body != body:
			continue
		var top := s.bounds.end.y
		var at := s.xform.origin
		var ix := int(floor((at.x - _origin.x) / CELL))
		var iz := int(floor((at.z - _origin.y) / CELL))
		for ring in range(0, 3):
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					var jx := ix + dx
					var jz := iz + dz
					if jx < 0 or jz < 0 or jx >= _nx or jz >= _nz:
						continue
					var col := jx + jz * _nx
					for n in range(_col_first[col], _col_first[col] + _col_count[col]):
						if absf(_node_y[n] - top) < 0.5:
							return n
	return -1


func _link_jumps() -> void:
	var regions := _region_count.size()

	for a in range(regions):
		for b in range(regions):
			if a == b or _out[a].has(b):
				continue

			var rise := _region_low[b].y - _region_high[a].y
			if rise > climb:
				continue

			var reach := G2GReach.run_reach(rise, _tunables)
			var bounds_a := AABB(_region_low[a], _region_high[a] - _region_low[a])
			var bounds_b := AABB(_region_low[b], _region_high[b] - _region_low[b])

			if _plan_gap(bounds_a, bounds_b) - CELL > reach:
				continue

			if _can_jump(a, b):
				_out[a][b] = true


## The clear air between two boxes seen from above, 0 when their footprints overlap.
static func _plan_gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector2(dx, dz).length()


## Units per bucket of a region's edge cells, for [method _can_jump].
const BUCKET := 128.0

var _edge_buckets: Dictionary = {}


func _buckets_of(region: int) -> Dictionary:
	if _edge_buckets.has(region):
		return _edge_buckets[region]

	var out: Dictionary = {}
	for n in _region_edge[region]:
		var at := _node_at(n)
		var key := Vector2i(floori(at.x / BUCKET), floori(at.z / BUCKET))
		var list: PackedInt32Array = out.get(key, PackedInt32Array())
		list.append(n)
		out[key] = list

	_edge_buckets[region] = out
	return out


func _can_jump(a: int, b: int) -> bool:
	var target := AABB(_region_low[b], _region_high[b] - _region_low[b])
	var buckets := _buckets_of(b)

	for n in _region_edge[a]:
		var from := _node_at(n)
		var best_reach := G2GReach.run_reach(_region_low[b].y - from.y, _tunables)

		if _plan_gap(AABB(from, Vector3.ZERO), target) - CELL > best_reach:
			continue

		var r := int(ceil((best_reach + CELL) / BUCKET))
		var bx := floori(from.x / BUCKET)
		var bz := floori(from.z / BUCKET)

		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var list: PackedInt32Array = buckets.get(Vector2i(bx + dx, bz + dz), PackedInt32Array())
				for m in list:
					var to := _node_at(m)
					var rise := to.y - from.y
					if rise > climb:
						continue
					# Centre to centre, less a cell: lip to lip, with the half cell either
					# side of each edge cell's centre given back.
					var gap := Vector2(to.x - from.x, to.z - from.z).length() - CELL
					if gap <= G2GReach.run_reach(rise, _tunables):
						return true

	return false


# --- Reading the graph ----------------------------------------------------------

static func _flood(starts: Array, edges: Array[Dictionary]) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array = starts.duplicate()

	for s: int in starts:
		seen[s] = true

	while not queue.is_empty():
		var r: int = queue.pop_back()
		for next: int in edges[r]:
			if not seen.has(next):
				seen[next] = true
				queue.append(next)

	return seen


## A standable cell close to [param at], at or a little under it: for a start that sits
## against a wall, where the column straight down has no room for the hull.
func _cell_near(at: Vector3) -> int:
	var ix := int(floor((at.x - _origin.x) / CELL))
	var iz := int(floor((at.z - _origin.y) / CELL))
	var best := -1

	for ring in range(1, 4):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var jx := ix + dx
				var jz := iz + dz
				if jx < 0 or jz < 0 or jx >= _nx or jz >= _nz:
					continue
				var col := jx + jz * _nx
				for n in range(_col_first[col], _col_first[col] + _col_count[col]):
					if _node_y[n] <= at.y + _TOL and _node_y[n] >= at.y - 64.0:
						if best < 0 or _node_y[n] > _node_y[best]:
							best = n
		if best >= 0:
			return best

	return -1


## The index of the declaration covering every cell of [param region] (all of them inside
## the declared boxes, and the first box that holds one is the one credited), or -1. Per
## cell rather than by the region's bounds, because a region can be a ring whose bounds
## are the whole map.
func _declared_by(region: int, declared: Array) -> int:
	if declared.is_empty():
		return -1

	var boxes: Array[AABB] = []
	for entry: Variant in declared:
		boxes.append(((entry as Dictionary)["box"] as AABB).grow(CELL))

	var first := -1

	for n in range(_node_col.size()):
		if _node_region[n] != region:
			continue
		var at := _node_at(n)
		var inside := -1
		for i in range(boxes.size()):
			if boxes[i].has_point(at):
				inside = i
				break
		if inside < 0:
			return -1
		if first < 0:
			first = inside

	return first

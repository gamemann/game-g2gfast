extends Node3D

const G2GUnits := preload("g2g_units.gd")

## Every zone drawn as its box: twelve thick edges that glow, in the zone's colour.
##
## [b]A zone a runner cannot see is a line they find by failing.[/b] The timer has always
## known exactly where every start, stage and finish is, and the world showed none of
## them: an imported map's start line is wherever a trigger was compiled, and a section
## line on a map nobody labelled is wherever somebody wrote a zones file. The timer
## plugins every one of these communities ran draw a beam box round each zone for that
## reason, and this is that box.
##
## Two layers per edge, both from one [MultiMesh] each so a map with two hundred pits is
## two draw calls: a bright core [member core_units] across, and a soft additive halo
## [member halo_units] across around it -- the glow, drawn rather than left to the
## environment's bloom, because the browser profile and the server's own render settings
## both decide whether bloom exists and a zone line should not depend on either.
##
## Client only, and drawing only: it reads [member DotTimerManager.zones] and changes
## nothing. [method refresh] rebuilds it, on a map change and whenever the zone editor
## draws a zone.

## Colour per kind, by the conventions those servers use: green start, red finish,
## amber stages and checkpoints. A bonus track's start and finish are drawn cooler
## (cyan, magenta) so a player can tell the main route's line from a bonus beside it.
const COLOURS := {
	DotTimerZone.Kind.START: Color(0.25, 1.0, 0.45),
	DotTimerZone.Kind.END: Color(1.0, 0.28, 0.28),
	DotTimerZone.Kind.STAGE: Color(1.0, 0.72, 0.18),
	DotTimerZone.Kind.CHECKPOINT: Color(1.0, 0.9, 0.3),
	DotTimerZone.Kind.TELEPORT: Color(0.35, 0.55, 1.0),
	DotTimerZone.Kind.RESPAWN: Color(0.75, 0.25, 0.95),
	DotTimerZone.Kind.STOP: Color(1.0, 0.5, 0.15),
	DotTimerZone.Kind.SPEED_LIMIT: Color(0.5, 0.85, 1.0),
}
const BONUS_START := Color(0.2, 0.9, 1.0)
const BONUS_END := Color(1.0, 0.3, 0.85)

## The kinds drawn by default. A pit is not on the route and there are hundreds of them;
## [member show_pits] adds them.
const DRAWN := [DotTimerZone.Kind.START, DotTimerZone.Kind.END, DotTimerZone.Kind.STAGE,
	DotTimerZone.Kind.CHECKPOINT, DotTimerZone.Kind.STOP, DotTimerZone.Kind.SPEED_LIMIT]

@export var core_units: float = 1.6
@export var halo_units: float = 7.0
@export var energy: float = 2.4

## Draw pits (RESPAWN) and doors (TELEPORT) too. Off by default; the zone editor turns it on.
var show_pits: bool = false

## A box being drawn by the zone editor, shown beside the real ones. AABB() for none.
var preview: AABB = AABB()
var preview_colour: Color = Color.WHITE

var _core: MultiMeshInstance3D = null
var _halo: MultiMeshInstance3D = null
var _zones: DotTimerZoneSet = null


func _ready() -> void:
	_core = _layer("Core", _core_material())
	_halo = _layer("Halo", _halo_material())


## Rebuilds every outline from [param zones] (null draws nothing).
func refresh(zones: DotTimerZoneSet) -> void:
	_zones = zones
	var boxes: Array = []    # [AABB, Color]
	if zones != null:
		for zone: DotTimerZone in zones.zones:
			if not (zone.kind in DRAWN) and not (show_pits and zone.kind in
					[DotTimerZone.Kind.RESPAWN, DotTimerZone.Kind.TELEPORT]):
				continue
			if zone.shape != DotTimerZone.Shape.BOX:
				continue
			var box := AABB(zone.from, zone.to - zone.from).abs()
			if box.size.length() <= 0.0:
				continue
			boxes.append([box, colour_for(zone)])
	if preview.size.length() > 0.0:
		boxes.append([preview, preview_colour])
	_fill(_core.multimesh, boxes, G2GUnits.to_metres(core_units), 1.0)
	_fill(_halo.multimesh, boxes, G2GUnits.to_metres(halo_units), 0.28)


## Redraws with the last zone set, after [member preview] or [member show_pits] moved.
func redraw() -> void:
	refresh(_zones)


static func colour_for(zone: DotTimerZone) -> Color:
	if zone.track != DotTimerTrack.MAIN:
		if zone.kind == DotTimerZone.Kind.START:
			return BONUS_START
		if zone.kind == DotTimerZone.Kind.END:
			return BONUS_END
	return COLOURS.get(zone.kind, Color.WHITE)


## Edges drawn, for a check.
func edge_count() -> int:
	return _core.multimesh.instance_count if _core != null else 0


func _fill(mm: MultiMesh, boxes: Array, thick: float, alpha: float) -> void:
	mm.instance_count = boxes.size() * 12
	var i := 0
	for entry: Array in boxes:
		var box: AABB = entry[0]
		var colour: Color = entry[1]
		colour.a = alpha
		for edge in _edges(box):
			var a: Vector3 = edge[0]
			var b: Vector3 = edge[1]
			var mid := (a + b) * 0.5
			var size := (b - a).abs() + Vector3.ONE * thick
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), mid))
			mm.set_instance_color(i, colour)
			i += 1


static func _edges(box: AABB) -> Array:
	var lo := box.position
	var hi := box.end
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	return [
		[c[0], c[1]], [c[1], c[2]], [c[2], c[3]], [c[3], c[0]],
		[c[4], c[5]], [c[5], c[6]], [c[6], c[7]], [c[7], c[4]],
		[c[0], c[4]], [c[1], c[5]], [c[2], c[6]], [c[3], c[7]],
	]


func _layer(name_: String, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	var inst := MultiMeshInstance3D.new()
	inst.name = name_
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _core_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float energy = 2.4;
void fragment() {
	ALBEDO = COLOR.rgb * energy;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"energy", energy)
	return m


## The glow: additive, never writing depth, fading toward the edge of the halo's own box
## so it reads as light round a line rather than as a second, fatter line.
func _halo_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
void fragment() {
	float edge = 1.0 - max(max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0, 0.0);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * smoothstep(0.0, 0.9, edge);
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m

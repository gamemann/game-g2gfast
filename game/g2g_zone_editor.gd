extends Node

const G2GBindings := preload("g2g_bindings.gd")
const G2GUnits := preload("g2g_units.gd")
const G2GZoneOutlines := preload("g2g_zone_outlines.gd")

## Drawing zones in the world, the way the timer plugins' zone menus do it.
##
## Z opens it; the player keeps moving and looking. A crosshair point on the floor
## follows the aim (snapped to the genre's 16-unit grid), and the box being drawn is drawn
## live in [G2GZoneOutlines] from the first corner to it:
##
## [codeblock]
## 1..6        what to draw: start, end, stage, checkpoint, stop, pit
## T           which track: main, bonus 1, bonus 2, ...
## [ and ]     the stage or checkpoint number
## PgUp/PgDn   the height, 16 units a press (128 by default: a jumping player)
## E or click  put a corner where you are aiming; the second one makes the zone
## Backspace   take the last zone back
## Enter       save the map's zones
## Z or Esc    close
## [/codeblock]
##
## [b]Offline it edits the game's own zone set[/b] and saves to `user://zones/<map>.json`,
## which [method G2GGame._on_map_changed] reads in preference to the map's own zones the
## next time the map loads. [b]Online it is a pen, not the paper:[/b] each step is sent as
## the server's own zone command in chat (`/g2g_zone`, `/g2g_zone_mark x y z`,
## `/g2g_zone_save`), which the server refuses unless the player holds the changemap
## flag. The box is drawn here either way, so the admin sees what they are about to send.

signal changed()

const KINDS := [
	["start", DotTimerZone.Kind.START], ["end", DotTimerZone.Kind.END],
	["stage", DotTimerZone.Kind.STAGE], ["checkpoint", DotTimerZone.Kind.CHECKPOINT],
	["stop", DotTimerZone.Kind.STOP], ["respawn", DotTimerZone.Kind.RESPAWN],
]

## The grid an aim point snaps to, in genre units.
const SNAP_UNITS := 16.0

## How far an aim reaches for a floor, in genre units.
const REACH_UNITS := 8192.0

var game: Node = null
var client: Node = null
var outlines: G2GZoneOutlines = null
var offline: bool = true

## Sends one chat line to the server. Set by the client; unused offline.
var send_line: Callable = Callable()

var kind_index: int = 0
var track: int = DotTimerTrack.MAIN
var number: int = 1
var height_units: float = 128.0

var _open := false
var _first: Variant = null      # Vector3, metres, or null
var _aim := Vector3.ZERO
var _aim_ok := false
var _panel: PanelContainer = null
var _text: Label = null
var _layer: CanvasLayer = null

## What the panel is drawn with. The client hands over the menu's; the default theme otherwise.
var kit: DotMenuKit = DotMenuKit.new()


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 105
	add_child(_layer)
	_panel = PanelContainer.new()
	var s := kit.surface_box()
	s.bg_color.a = 0.82
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	_panel.add_theme_stylebox_override(&"panel", s)
	_panel.position = Vector2(18, 90)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text = kit.label("", kit.size_small, kit.palette.text)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_text)
	_layer.add_child(_panel)
	_panel.visible = false
	set_process(false)


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	_first = null
	_panel.visible = true
	if outlines != null:
		outlines.show_pits = true
		outlines.redraw()
	set_process(true)
	_update_text()


func close() -> void:
	_open = false
	_first = null
	_panel.visible = false
	if outlines != null:
		outlines.preview = AABB()
		outlines.show_pits = false
		outlines.redraw()
	set_process(false)


func kind() -> DotTimerZone.Kind:
	return KINDS[kind_index][1]


func kind_name() -> String:
	return KINDS[kind_index][0]


## A key while the editor is open. True when the editor used it, so it does not also do
## whatever it does in a run (R restarting, M opening the map list).
func handle_key(event: InputEventKey) -> bool:
	if not _open or not event.pressed or event.echo:
		return false
	var code := event.physical_keycode
	if code >= KEY_1 and code <= KEY_6:
		kind_index = code - KEY_1
		_first = null
	elif code == KEY_T:
		track = (track + 1) % DotTimerTrack.COUNT
	elif code == KEY_BRACKETLEFT:
		number = maxi(1, number - 1)
	elif code == KEY_BRACKETRIGHT:
		number = mini(99, number + 1)
	elif code == KEY_PAGEUP:
		height_units = minf(height_units + SNAP_UNITS, 2048.0)
	elif code == KEY_PAGEDOWN:
		height_units = maxf(height_units - SNAP_UNITS, SNAP_UNITS)
	elif code == KEY_E:
		place()
	elif code == KEY_BACKSPACE:
		undo()
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		save()
	elif code == KEY_ESCAPE or code == KEY_Z:
		close()
	else:
		return false
	_update_text()
	return true


## A mouse button while open: the left one places a corner.
func handle_click(event: InputEventMouseButton) -> bool:
	if not _open or not event.pressed:
		return false
	if event.button_index == MOUSE_BUTTON_LEFT:
		place()
		_update_text()
		return true
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		height_units = clampf(height_units + (SNAP_UNITS if event.button_index == MOUSE_BUTTON_WHEEL_UP
			else -SNAP_UNITS), SNAP_UNITS, 2048.0)
		_update_text()
		return true
	return false


func _process(_delta: float) -> void:
	_aim_ok = _find_aim()
	if outlines == null:
		return
	if _first != null and _aim_ok:
		outlines.preview = box_between(_first, _aim)
		outlines.preview_colour = G2GZoneOutlines.COLOURS.get(kind(), Color.WHITE)
	elif _aim_ok:
		# A marker where the corner would go: a flat 16-unit square on the floor.
		var half := G2GUnits.to_metres(SNAP_UNITS * 0.5)
		outlines.preview = AABB(_aim - Vector3(half, 0, half), Vector3(half * 2, G2GUnits.to_metres(2.0), half * 2))
		outlines.preview_colour = Color(1, 1, 1)
	else:
		outlines.preview = AABB()
	outlines.redraw()


## The zone a pair of corners makes: the floor rectangle between them, [member height_units]
## tall from the lower of the two.
func box_between(a: Vector3, b: Vector3) -> AABB:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), minf(a.y, b.y) + G2GUnits.to_metres(height_units), maxf(a.z, b.z))
	return AABB(lo, hi - lo)


func place() -> void:
	if not _aim_ok:
		_say("Aim at the floor.")
		return
	if _first == null:
		_first = _aim
		return
	var first: Vector3 = _first
	_first = null
	commit(first, _aim)


## Adds the zone between two corners: to the game offline, to the server online.
func commit(a: Vector3, b: Vector3) -> DotResult:
	var box := box_between(a, b)
	if box.size.x < G2GUnits.to_metres(8.0) or box.size.z < G2GUnits.to_metres(8.0):
		_say("Too small: drag the corners apart.")
		return DotResult.fail(DotError.CODE_INVALID, "too small")
	var numbered := kind() in [DotTimerZone.Kind.STAGE, DotTimerZone.Kind.CHECKPOINT]
	if offline:
		var zones: DotTimerZoneSet = game.timers.zones
		if zones == null:
			zones = DotTimerZoneSet.new()
			zones.map_id = game.maps.current.id if game.maps.current != null else &"map"
		var zone := DotTimerZone.make(kind(), track)
		zone.set_box(box.position, box.end)
		zone.number = float(number) if numbered else 0.0
		if kind() in [DotTimerZone.Kind.STAGE, DotTimerZone.Kind.START]:
			# Where `!s<n>` and a restart put you: the middle of the floor, facing as you are.
			zone.destination = Vector3(box.get_center().x, box.position.y + G2GUnits.to_metres(8.0), box.get_center().z)
			zone.destination_yaw = _yaw()
		var valid := zone.validate()
		if not valid.ok:
			_say(valid.error.message)
			return valid
		zones.add(zone)
		game.timers.set_zones(zones)
		if numbered:
			number += 1
		_say("Drew %s on %s." % [kind_name(), DotTimerTrack.name_of(track)])
		changed.emit()
		return DotResult.success(zone)
	var u_a := G2GUnits.vector_to_units(box.position)
	var u_b := G2GUnits.vector_to_units(Vector3(box.end.x, box.position.y, box.end.z))
	_send("/g2g_zone %s %d %d" % [kind_name(), track, number if numbered else 0])
	_send("/g2g_zone_mark %.0f %.0f %.0f 0" % [u_a.x, u_a.y, u_a.z])
	_send("/g2g_zone_mark %.0f %.0f %.0f %.0f" % [u_b.x, u_b.y, u_b.z, height_units])
	if numbered:
		number += 1
	_say("Sent %s on %s to the server." % [kind_name(), DotTimerTrack.name_of(track)])
	return DotResult.success(null)


func undo() -> void:
	if not offline:
		_send("/g2g_zone_undo")
		return
	var zones: DotTimerZoneSet = game.timers.zones
	if zones == null or zones.zones.is_empty():
		_say("Nothing to undo.")
		return
	var last := zones.zones[zones.zones.size() - 1]
	zones.remove_id(last.id)
	game.timers.set_zones(zones)
	changed.emit()
	_say("Took back a %s." % DotTimerZone.Kind.keys()[last.kind].to_lower())


func save() -> void:
	if not offline:
		_send("/g2g_zone_save")
		return
	var zones: DotTimerZoneSet = game.timers.zones
	if zones == null:
		_say("No zones to save.")
		return
	var problems := zones.problems()
	if not problems.is_empty():
		_say("Not saved: %s" % problems[0])
		return
	var path := "user://zones/%s.json" % String(zones.map_id)
	DirAccess.make_dir_recursive_absolute("user://zones")
	var wrote := zones.save_json(path)
	_say("Saved %s." % path if wrote.ok else wrote.error.message)
	if wrote.ok:
		DotWeb.sync_filesystem()


func _send(line: String) -> void:
	if send_line.is_valid():
		send_line.call(line)


func _say(text: String) -> void:
	if client != null and client.get("hud") != null:
		client.hud.notice(text)


func _yaw() -> float:
	var p: Variant = client.get("player") if client != null else null
	return (p as Node).controller.state.yaw if p != null else 0.0


## Where the player is aiming, on the world: a ray from the eye along the aim, snapped
## to the grid across and kept exact in height.
func _find_aim() -> bool:
	var p: Variant = client.get("player") if client != null else null
	if p == null or not (p is Node3D):
		return false
	var player: Node3D = p
	var from: Vector3 = player.eye_position()
	var dir: Vector3 = player.aim_direction()
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * G2GUnits.to_metres(REACH_UNITS))
	query.collide_with_areas = false
	query.collision_mask = player.collision_mask
	query.exclude = []
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var at: Vector3 = hit["position"]
	var snap := G2GUnits.to_metres(SNAP_UNITS)
	_aim = Vector3(snappedf(at.x, snap), at.y, snappedf(at.z, snap))
	return true


func _update_text() -> void:
	if _text == null:
		return
	var lines := PackedStringArray()
	lines.append("ZONE EDITOR  —  %s" % ("offline" if offline else "sent to the server"))
	for i in KINDS.size():
		lines.append("%s %d  %s" % ["▶" if i == kind_index else "  ", i + 1, KINDS[i][0]])
	lines.append("")
	lines.append("T  track: %s" % DotTimerTrack.name_of(track))
	lines.append("[ ]  number: %d" % number)
	lines.append("PgUp/PgDn  height: %d units" % int(height_units))
	lines.append("")
	lines.append("E / click  %s corner" % ("second" if _first != null else "first"))
	lines.append("Backspace undo   Enter save   Z close")
	_text.text = "\n".join(lines)

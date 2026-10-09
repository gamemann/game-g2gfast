extends Button

const G2GUi := preload("g2g_ui.gd")

## An on/off switch: a rounded track and a knob that slides across it.
##
## A [Button] in toggle mode underneath, so focus, keyboard activation, `toggled` and
## `disabled` are the engine's own and nothing here reimplements them; only the drawing is
## this file's. The knob eases toward its side rather than jumping, which is the one bit of
## motion in these menus, and it settles in about a tenth of a second.

const TRACK := Vector2(44, 24)

var _t: float = 0.0


func _init() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = TRACK
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The flat button draws nothing of its own; the focus ring is drawn below.
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())


func _ready() -> void:
	_t = 1.0 if button_pressed else 0.0
	toggled.connect(func(_on: bool) -> void: queue_redraw())


## Sets the state without emitting [signal BaseButton.toggled] — for showing a value, not
## choosing one.
func show_value(on: bool) -> void:
	set_pressed_no_signal(on)
	_t = 1.0 if on else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	var goal := 1.0 if button_pressed else 0.0
	if not is_equal_approx(_t, goal):
		_t = move_toward(_t, goal, delta * 9.0)
		queue_redraw()


func _draw() -> void:
	var origin := Vector2(size.x - TRACK.x, (size.y - TRACK.y) * 0.5)
	var rect := Rect2(origin, TRACK)
	var eased := _t * _t * (3.0 - 2.0 * _t)

	var off_fill := Color(G2GUi.TEXT, 0.12)
	var fill := off_fill.lerp(G2GUi.ACCENT_DEEP, eased)
	if disabled:
		fill = Color(G2GUi.TEXT, 0.05)

	var track := G2GUi.box(fill, int(TRACK.y * 0.5))
	if is_hovered() and not disabled:
		track.border_color = Color(G2GUi.TEXT, 0.18)
		track.set_border_width_all(1)
	draw_style_box(track, rect)

	if has_focus():
		var ring := G2GUi.box(Color(0, 0, 0, 0), int(TRACK.y * 0.5) + 3, Color(G2GUi.ACCENT, 0.6), 2)
		draw_style_box(ring, rect.grow(3))

	var r := TRACK.y * 0.5 - 3.0
	var x := lerpf(rect.position.x + 3.0 + r, rect.end.x - 3.0 - r, eased)
	var knob := G2GUi.TEXT if not disabled else G2GUi.DIM
	draw_circle(Vector2(x, rect.get_center().y + 1.0), r, Color(0, 0, 0, 0.25))
	draw_circle(Vector2(x, rect.get_center().y), r, knob)

extends Control

const G2GUi := preload("g2g_ui.gd")

## Moving the HUD: every piece a player can place is drawn with a frame round it, and is
## dragged where they want it.
##
## [b]A drag, not a form.[/b] Timer plugins in this genre offer a handful of fixed layouts
## because the engines they live in cannot draw anything else; here the HUD is Controls,
## so where a piece goes is wherever a player puts it, and the honest way to ask "where" is
## to let them point. What is stored is each piece's CENTRE as a fraction of the window
## (see [method G2GHud.positions_from_text]), so a layout made on a laptop lands in the same
## place on a 4K screen.
##
## The game keeps running underneath, as under the menu: the client counts this as an
## overlay, so the sampler is suspended and the pointer is free.
##
## [codeblock]
## editor.hud = hud
## editor.saved.connect(func(text): settings.set_value(&"hud_positions", text))
## editor.open()
## [/codeblock]

signal closed()

## The layout as the setting stores it, after a drag or a reset.
signal saved(text: String)

## The HUD being edited. Duck-typed: `element_rect`, `move_element`, `reset_element`,
## `positions`, `place` — see G2GHud.
var hud: Control = null

const LABELS := {
	&"timer": "Timer",
	&"keys": "Keys",
	&"status": "Status line",
	&"spectators": "Spectators",
}

var _dragging: StringName = &""
var _grab_offset := Vector2.ZERO
var _hover: StringName = &""
var _bar: PanelContainer = null


func _ready() -> void:
	G2GUi.fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


## Rebuilds the bar in the current theme. See G2GMenu.restyle.
func restyle() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _build() -> void:
	theme = G2GUi.theme()

	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override(&"panel", G2GUi.surface_box())
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar.offset_top = 90.0
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_bar)

	var pad := MarginContainer.new()
	for side in [&"margin_left", &"margin_right"]:
		pad.add_theme_constant_override(side, 18)
	for side in [&"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	_bar.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	pad.add_child(row)

	var words := VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 2)
	words.add_child(G2GUi.label("Move the HUD", G2GUi.SIZE_HEADING, G2GUi.TEXT, true))
	words.add_child(G2GUi.label("Drag a piece to move it. Right-click one to put it back.", G2GUi.SIZE_SMALL, G2GUi.MUTED))
	row.add_child(words)

	var reset := Button.new()
	reset.text = "Reset all"
	reset.pressed.connect(reset_all)
	row.add_child(reset)

	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(close)
	row.add_child(done)


func open() -> void:
	visible = true
	_dragging = &""
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = &""
	closed.emit()


func is_open() -> bool:
	return visible


## Every piece back where the layout puts it.
func reset_all() -> void:
	if hud == null:
		return
	for id: StringName in LABELS:
		hud.call("reset_element", id)
	_save()


## The piece under [param at] (HUD coordinates), or empty. The smallest one wins, so the
## keys can be picked up when they sit just under the clock's block.
func piece_at(at: Vector2) -> StringName:
	if hud == null:
		return &""
	var best := &""
	var best_area := INF
	for id: StringName in LABELS:
		var rect: Rect2 = (hud.call("element_rect", id) as Rect2).grow(6.0)
		if rect.has_point(at) and rect.get_area() < best_area:
			best = id
			best_area = rect.get_area()
	return best


## Drags piece [param id] so that the point grabbed is under [param at]. Public so a
## suite can drive a drag without a mouse.
func drag(id: StringName, from: Vector2, to: Vector2) -> void:
	if hud == null or id == &"":
		return
	var rect: Rect2 = hud.call("element_rect", id)
	var offset := rect.get_center() - from
	hud.call("move_element", id, to + offset)
	_save()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if hud == null:
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = piece_at(button.position)
				if _dragging != &"":
					var rect: Rect2 = hud.call("element_rect", _dragging)
					_grab_offset = rect.get_center() - button.position
			elif _dragging != &"":
				_dragging = &""
				_save()
			accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			var id := piece_at(button.position)
			if id != &"":
				hud.call("reset_element", id)
				_save()
			accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging != &"":
			hud.call("move_element", _dragging, motion.position + _grab_offset)
			accept_event()
		var over := piece_at(motion.position)
		if over != _hover:
			_hover = over
		queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		# The pieces change size as they draw (the clock's block, the list), so the frames
		# follow them every frame rather than only on a drag.
		queue_redraw()


func _draw() -> void:
	if hud == null:
		return
	# A wash over the game, lighter than the menu's: the point is to see the HUD on it.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	var font := get_theme_default_font()
	for id: StringName in LABELS:
		var rect: Rect2 = hud.call("element_rect", id)
		if rect.size == Vector2.ZERO:
			continue
		var live := id == _dragging or id == _hover
		var edge := G2GUi.ACCENT if live else Color(1, 1, 1, 0.75)
		draw_rect(rect.grow(4.0), Color(edge, 0.12 if live else 0.06), true)
		draw_rect(rect.grow(4.0), edge, false, 2.0)
		if font != null:
			var moved := (hud.get("positions") as Dictionary).has(id)
			var tag := "%s%s" % [LABELS[id], "  (moved)" if moved else ""]
			# Beside the frame rather than over it: the keys sit right under the clock,
			# and a tag above one is drawn on the other.
			var width := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var at := Vector2(rect.end.x + 12.0, rect.position.y + 16.0)
			if at.x + width > size.x - 4.0:
				at.x = rect.position.x - width - 12.0
			draw_string_outline(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
			draw_string(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, edge)


func _save() -> void:
	if hud == null:
		return
	var text: String = hud.get_script().positions_to_text(hud.get("positions"))
	saved.emit(text)

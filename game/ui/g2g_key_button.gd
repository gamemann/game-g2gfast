extends Button

const G2GUi := preload("g2g_ui.gd")

## One key binding as a button: shows the key, and on a click listens for the next one.
##
## [b]Listens in [method Node._input], ahead of everything else.[/b] A key pressed to bind
## must not ALSO do what it currently does — R restarting the run, F toggling the light —
## and the gameplay handlers run from `_unhandled_input`, after this has marked it handled.
##
## Three things a rebinder has to get right, and dot-ui's `DotBindingsPanel` names them:
## [b]Escape cancels[/b] (a player who opened the capture by accident must be able to back
## out, and binding Escape to something would leave them unable to leave any menu);
## [b]keys are stored by physical position[/b], through `DotInputBinding`, so a binding
## survives a layout change; and the left mouse button is refused, because it is how the
## player clicks on this button, and every other button, to begin with.

## The binding a player chose, as `DotInputBinding` text.
signal captured(text: String)

var binding: String = "":
	set(value):
		binding = value
		_refresh()

var listening: bool = false

var _cap: PanelContainer = null
var _cap_label: Label = null
var _hint: Label = null
var _opened_on_frame: int = -1


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(150, 34)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())


func _ready() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	G2GUi.fill_parent(row)
	add_child(row)

	_hint = G2GUi.label("", G2GUi.SIZE_SMALL, G2GUi.ACCENT)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_hint)

	_cap = G2GUi.keycap("")
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_label = _cap.get_child(0) as Label
	row.add_child(_cap)

	pressed.connect(_listen)
	focus_exited.connect(_stop)
	_refresh()


func _listen() -> void:
	listening = true
	_opened_on_frame = Engine.get_process_frames()
	_refresh()


func _stop() -> void:
	if listening:
		listening = false
		_refresh()


func _input(event: InputEvent) -> void:
	if not listening or not is_visible_in_tree():
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		var key := event as InputEventKey

		if key.physical_keycode == KEY_ESCAPE:
			_stop()
			return

		# A modifier on its own is a binding ("Ctrl" is Duck). Pressed with another key it
		# is part of that key; this is the moment it went down, so it is the key itself.
		var bare := InputEventKey.new()
		bare.physical_keycode = key.physical_keycode
		_finish(DotInputBinding.to_text(bare))
		return

	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton

		# The click that opened the capture is still being delivered on this frame.
		if Engine.get_process_frames() == _opened_on_frame:
			return

		get_viewport().set_input_as_handled()

		if button.button_index == MOUSE_BUTTON_LEFT:
			_stop()
			return

		_finish(DotInputBinding.to_text(button))


func _finish(text: String) -> void:
	listening = false
	_refresh()
	if text != DotInputBinding.UNBOUND:
		captured.emit(text)


func _refresh() -> void:
	if _cap_label == null:
		return

	# Wide enough for the prompt while it listens, and only then: the prompt sits inside
	# the button, and a button kept at the keycap's width draws it over its own edge.
	custom_minimum_size.x = 300.0 if listening else 150.0

	if listening:
		_hint.text = "Press a key  ·  Esc cancels"
		_cap_label.text = "…"
		_cap.add_theme_stylebox_override(&"panel", _cap_box(G2GUi.ACCENT_WASH, G2GUi.ACCENT))
	else:
		_hint.text = ""
		_cap_label.text = binding if binding != "" else "—"
		var edge := G2GUi.ACCENT if has_focus() or is_hovered() else G2GUi.KEYCAP_EDGE
		_cap.add_theme_stylebox_override(&"panel", _cap_box(G2GUi.KEYCAP, edge))


func _cap_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var s := G2GUi.box(fill, 6, edge, 1, Vector4(12, 4, 12, 5))
	s.border_width_bottom = 3
	return s


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT \
			or what == NOTIFICATION_FOCUS_ENTER:
		_refresh()

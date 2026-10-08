extends Control

const G2GBindings := preload("../g2g_bindings.gd")
const G2GUi := preload("g2g_ui.gd")

## The H screen: every key, every chat command, and — in a browser — what the browser does
## with keys the game never sees.
##
## [b]Nothing on it is written down here.[/b] The keys come from [G2GBindings] and show the
## player's own bindings, not the defaults; the commands come from the server, in the RULES
## event, read off its console when this client joined. So a key rebound a minute ago and a
## `!` command added to the server last week are both on it, and neither needed this file
## edited. A help screen that is a list somebody typed is one that is wrong the first time
## anybody changes anything, and nothing would ever say so.

signal closed()

## [code][[name, help], ...][/code] from the server. Empty offline.
var commands: Array = []

## Whether this client has a server to send commands to.
var online: bool = false

## Whether to draw the browser's tips. A browser by default; settable so a screenshot of a
## desktop build can show what a browser player sees.
var show_browser_tips: bool = DotPlatform.is_web()

var _window: PanelContainer = null
var _body: HBoxContainer = null
var _keys_column: VBoxContainer = null
var _side_column: VBoxContainer = null


func _ready() -> void:
	theme = G2GUi.theme()
	G2GUi.fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.05, 0.72)
	G2GUi.fill_parent(back)
	add_child(back)

	var centre := CenterContainer.new()
	G2GUi.fill_parent(centre)
	add_child(centre)

	_window = PanelContainer.new()
	var s := G2GUi.surface_box()
	s.content_margin_left = 30
	s.content_margin_right = 22
	s.content_margin_top = 24
	s.content_margin_bottom = 20
	_window.add_theme_stylebox_override(&"panel", s)
	centre.add_child(_window)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	_window.add_child(col)

	var head := HBoxContainer.new()
	var title := G2GUi.label("Help", G2GUi.SIZE_TITLE, G2GUi.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override(&"separation", 6)
	hint.add_child(G2GUi.keycap(G2GBindings.shown(G2GBindings.row_for_action(&"g2g_help"))))
	hint.add_child(G2GUi.label("or", G2GUi.SIZE_SMALL, G2GUi.DIM))
	hint.add_child(G2GUi.keycap("Esc"))
	hint.add_child(G2GUi.label("to close", G2GUi.SIZE_SMALL, G2GUi.DIM))
	head.add_child(hint)
	col.add_child(head)
	col.add_child(G2GUi.paragraph("Your keys as they are bound now — change them under Menu → Controls. Commands are typed in chat."))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_right", 10)
	pad.add_theme_constant_override(&"margin_top", 8)
	scroll.add_child(pad)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 22)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_body)

	_keys_column = VBoxContainer.new()
	_keys_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_column.add_theme_constant_override(&"separation", 10)
	_body.add_child(_keys_column)

	_side_column = VBoxContainer.new()
	_side_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_column.size_flags_stretch_ratio = 1.25
	_side_column.add_theme_constant_override(&"separation", 10)
	_body.add_child(_side_column)

	get_viewport().size_changed.connect(_fit)
	_fit()


func open() -> void:
	_rebuild()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _fit() -> void:
	if _window == null:
		return
	var view := get_viewport_rect().size
	_window.custom_minimum_size = Vector2(
		clampf(view.x - 48.0, 320.0, 1100.0), clampf(view.y - 48.0, 300.0, 700.0)
	)


func _rebuild() -> void:
	for column in [_keys_column, _side_column]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()

	# Keys, by group, as the player has them bound right now.
	for group in G2GBindings.groups():
		var card := _card(_keys_column, group)
		for row in G2GBindings.ROWS:
			if str(row["group"]) == group:
				_key_line(card, G2GBindings.shown(row), str(row["label"]))
		if group == "Interface":
			_key_line(card, "Esc", "Menu and settings")

	if show_browser_tips:
		_browser_tips(_card(_side_column, "Playing in a browser"))

	_commands(_card(_side_column, "Chat commands"))


func _browser_tips(card: VBoxContainer) -> void:
	var duck := G2GBindings.shown(G2GBindings.row_for_action(&"dot_fps_crouch"))
	var tips: Array[Array] = [
		["Esc", "Frees the mouse and opens the menu. Click the game, or Resume, to take the mouse back. The browser will not lock it again for about a second after Esc, so if a click does nothing, click once more."],
		["Ctrl + W", "Closes the tab, and no web page can stop it. Careful: Duck is on Ctrl, so ducking while you press W is exactly that shortcut. Rebind Duck under Menu → Controls — Shift is free."
			if duck == "Ctrl" else "Closes the tab, and no web page can stop it. Mind it if you ever bind a key to Ctrl."],
		["Ctrl + T  ·  Ctrl + N", "Open a new tab or window and take the keyboard with them."],
		["Ctrl + Q  ·  Alt + F4", "Close the whole browser on some systems."],
		["Alt + ←", "Goes back a page in some browsers. Nothing here uses Alt."],
		["F11", "The browser's own fullscreen. Fullscreen from Menu → Video instead also keeps Ctrl+W and the rest away from the game in browsers that support it; hold Esc to leave."],
		["Sound", "Starts after your first click. Browsers keep a page silent until you have touched it."],
		["Stutter", "Cap the frame rate or lower the render scale under Menu → Video."],
	]
	for tip in tips:
		_tip_line(card, str(tip[0]), str(tip[1]))


func _commands(card: VBoxContainer) -> void:
	if not online:
		_note(card, "You are playing offline. Commands are the server's, so they work once you join one.")
		return

	if commands.is_empty():
		_note(card, "This server did not send its command list.")
		return

	for row in commands:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 14)
		var name_label := G2GUi.label("!" + str(row[0]), G2GUi.SIZE_SMALL + 1, G2GUi.ACCENT, true)
		name_label.custom_minimum_size = Vector2(118, 0)
		line.add_child(name_label)
		line.add_child(G2GUi.paragraph(str(row[1]), G2GUi.SIZE_SMALL, G2GUi.MUTED))
		_line(card, line)


# --- Pieces -------------------------------------------------------------------

func _card(column: VBoxContainer, title: String) -> VBoxContainer:
	var head := MarginContainer.new()
	head.add_theme_constant_override(&"margin_left", 4)
	head.add_theme_constant_override(&"margin_top", 4)
	head.add_child(G2GUi.section(title))
	column.add_child(head)

	var card := G2GUi.card()
	column.add_child(card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 0)
	card.add_child(rows)
	return rows


func _key_line(card: VBoxContainer, key: String, what: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	var cap_box := HBoxContainer.new()
	cap_box.custom_minimum_size = Vector2(72, 0)
	cap_box.add_child(G2GUi.keycap(key))
	line.add_child(cap_box)
	var l := G2GUi.label(what, G2GUi.SIZE_BODY - 1, G2GUi.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(l)
	_line(card, line)


func _tip_line(card: VBoxContainer, key: String, text: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	var k := G2GUi.label(key, G2GUi.SIZE_SMALL, G2GUi.WARN, true)
	k.custom_minimum_size = Vector2(132, 0)
	line.add_child(k)
	line.add_child(G2GUi.paragraph(text, G2GUi.SIZE_SMALL, G2GUi.MUTED))
	_line(card, line)


func _note(card: VBoxContainer, text: String) -> void:
	_line(card, G2GUi.paragraph(text))


func _line(card: VBoxContainer, content: Control) -> void:
	if card.get_child_count() > 0:
		card.add_child(HSeparator.new())
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_top", 7)
	pad.add_theme_constant_override(&"margin_bottom", 7)
	pad.add_child(content)
	card.add_child(pad)


func describe() -> Dictionary:
	return {"open": visible, "commands": commands.size(), "online": online}

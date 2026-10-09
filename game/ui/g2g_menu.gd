extends Control

const G2GBindings := preload("../g2g_bindings.gd")
const G2GKeyButton := preload("g2g_key_button.gd")
const G2GSwitch := preload("g2g_switch.gd")
const G2GUi := preload("g2g_ui.gd")

## The Escape menu: resume, the settings by page, the key bindings, help, and leaving.
##
## [b]Every control here is a view of a setting, never a second copy of one.[/b] A switch
## reads [DotSettingsManager] when its page is built and writes it when it is flipped;
## [G2GPresentation] is the one place a setting is APPLIED. So a value changed from the
## console (`show_speed 0`) is what the menu shows the next time it opens, and a value
## changed here is applied by exactly the code that applies it at boot — there is no
## "apply" button because there is nothing to apply that has not already been.
##
## The few rows that are not settings — the style, the flashlight, third person — are
## state the server has a say in, and they ask [member host] (the client) rather than a
## setting, because a stored "flashlight on" or "third person on" would be a promise the
## next server is free to refuse.
##
## [b]It does not pause.[/b] dot-ui's `allow_pause` reason, and stronger here: the server
## keeps simulating, and a timer server's clock does not stop for a menu. The client
## suspends the sampler while this is open, so a runner who opens it stands still rather
## than walking off a block with the key they were holding.

const CHANNEL := "g2g.menu"

const PAGES: Array[Dictionary] = [
	{"id": &"general", "title": "General", "blurb": "What the HUD shows, and chat."},
	{"id": &"gameplay", "title": "Gameplay", "blurb": "Your style, your view, and what else is drawn on the course."},
	{"id": &"video", "title": "Video", "blurb": "Window, frame rate and image quality. Saved on this device."},
	{"id": &"audio", "title": "Audio", "blurb": "Volume by kind of sound."},
	{"id": &"controls", "title": "Controls", "blurb": "Mouse and key bindings. Keys are saved on this device."},
]

## The frame rates offered. 0 is unlimited, which is the default.
const FPS_CHOICES: Array[int] = [0, 30, 60, 75, 120, 144, 165, 240, 300]

signal closed()
signal help_requested()
signal leave_requested()

var settings: DotSettingsManager = null

## The client. Duck-typed — see the `menu_*` methods on `G2GClient`.
var host: Node = null

var _page: StringName = &"general"
var _nav: Dictionary = {}
var _window: PanelContainer = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _title: Label = null
var _blurb: Label = null
var _subtitle: Label = null
var _toast: Label = null
var _toast_until: float = 0.0
var _resume: Button = null
var _leave: Button = null


func _ready() -> void:
	theme = G2GUi.theme()
	G2GUi.fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	add_child(_backdrop())

	var centre := CenterContainer.new()
	G2GUi.fill_parent(centre)
	add_child(centre)

	_window = PanelContainer.new()
	_window.add_theme_stylebox_override(&"panel", G2GUi.surface_box())
	centre.add_child(_window)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 0)
	_window.add_child(columns)

	columns.add_child(_sidebar())
	columns.add_child(_content())

	get_viewport().size_changed.connect(_fit)
	_fit()


## Opens on [param page], or on the page it was last left on.
func open(page: StringName = &"") -> void:
	if page != &"":
		_page = page
	_refresh_sidebar()
	_show_page(_page)
	visible = true
	if _resume != null:
		_resume.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if _toast != null and _toast.text != "" and Time.get_ticks_msec() / 1000.0 > _toast_until:
		_toast.text = ""


## Says something small under the page title for a few seconds.
func toast(text: String, seconds: float = 4.0) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast_until = Time.get_ticks_msec() / 1000.0 + seconds


# --- Layout -----------------------------------------------------------------

## Sized to the window, within limits, so a laptop and a 4K screen both get a menu that
## fits rather than one that is either cramped or lost in the middle.
func _fit() -> void:
	if _window == null:
		return
	var view := get_viewport_rect().size
	_window.custom_minimum_size = Vector2(
		clampf(view.x - 48.0, 320.0, 1060.0), clampf(view.y - 48.0, 300.0, 680.0)
	)


func _backdrop() -> ColorRect:
	var back := ColorRect.new()
	back.name = "Backdrop"
	back.color = G2GUi.BACKDROP
	G2GUi.fill_parent(back)
	back.mouse_filter = Control.MOUSE_FILTER_STOP

	# The game behind, softened. A plain dim where the renderer has no screen mipmaps, which
	# is what the shader falls back to anyway.
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.05, 0.62);
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, 3.0).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	back.material = mat
	return back


func _sidebar() -> Control:
	var side := PanelContainer.new()
	var s := G2GUi.box(G2GUi.SIDEBAR, G2GUi.RADIUS + 4, Color(0, 0, 0, 0), 0, Vector4(18, 22, 18, 18))
	s.corner_radius_top_right = 0
	s.corner_radius_bottom_right = 0
	side.add_theme_stylebox_override(&"panel", s)
	side.custom_minimum_size = Vector2(236, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	side.add_child(col)

	var brand := HBoxContainer.new()
	brand.add_theme_constant_override(&"separation", 10)
	var mark := PanelContainer.new()
	mark.add_theme_stylebox_override(&"panel", G2GUi.box(G2GUi.ACCENT, 8, Color(0, 0, 0, 0), 0, Vector4(8, 2, 8, 3)))
	mark.add_child(G2GUi.label("g2g", G2GUi.SIZE_SMALL + 1, Color(0.03, 0.09, 0.08), true))
	brand.add_child(mark)
	brand.add_child(G2GUi.label("fast", G2GUi.SIZE_TITLE - 4, G2GUi.TEXT, true))
	col.add_child(brand)

	_subtitle = G2GUi.paragraph("", G2GUi.SIZE_SMALL, G2GUi.DIM)
	col.add_child(_subtitle)
	col.add_child(_gap(14))

	_resume = _primary_button("Resume")
	_resume.pressed.connect(close)
	col.add_child(_resume)
	col.add_child(_gap(10))

	var group := ButtonGroup.new()
	for page in PAGES:
		var b := _nav_button(str(page["title"]), group)
		var id: StringName = page["id"]
		b.pressed.connect(func() -> void: _show_page(id))
		_nav[id] = b
		col.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var help := _nav_button("Help & commands", null)
	help.pressed.connect(func() -> void: help_requested.emit())
	col.add_child(help)

	_leave = _nav_button("Leave", null)
	_leave.add_theme_color_override(&"font_color", G2GUi.DANGER)
	_leave.add_theme_color_override(&"font_hover_color", G2GUi.DANGER)
	_leave.pressed.connect(func() -> void: leave_requested.emit())
	col.add_child(_leave)
	return side


func _content() -> Control:
	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override(&"margin_left", 30)
	wrap.add_theme_constant_override(&"margin_right", 18)
	wrap.add_theme_constant_override(&"margin_top", 24)
	wrap.add_theme_constant_override(&"margin_bottom", 18)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	wrap.add_child(col)

	var head := HBoxContainer.new()
	_title = G2GUi.label("", G2GUi.SIZE_TITLE, G2GUi.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var esc := HBoxContainer.new()
	esc.add_theme_constant_override(&"separation", 6)
	esc.add_child(G2GUi.keycap("Esc"))
	esc.add_child(G2GUi.label("to resume", G2GUi.SIZE_SMALL, G2GUi.DIM))
	head.add_child(esc)
	col.add_child(head)

	_blurb = G2GUi.paragraph("", G2GUi.SIZE_SMALL, G2GUi.MUTED)
	col.add_child(_blurb)
	_toast = G2GUi.label("", G2GUi.SIZE_SMALL, G2GUi.ACCENT)
	col.add_child(_toast)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_right", 12)
	pad.add_theme_constant_override(&"margin_top", 6)
	pad.add_theme_constant_override(&"margin_bottom", 8)
	_scroll.add_child(pad)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 10)
	pad.add_child(_body)
	return wrap


func _refresh_sidebar() -> void:
	if _subtitle != null and host != null and host.has_method("menu_where"):
		_subtitle.text = str(host.call("menu_where"))
	if _leave != null and host != null and host.has_method("menu_leave_label"):
		var words := str(host.call("menu_leave_label"))
		_leave.text = words
		_leave.visible = words != ""


# --- Pages ------------------------------------------------------------------

func _show_page(id: StringName) -> void:
	_page = id
	for page in PAGES:
		if page["id"] == id:
			_title.text = str(page["title"])
			_blurb.text = str(page["blurb"])
	# Every button set by hand: `set_pressed_no_signal` goes round the ButtonGroup, so
	# pressing one this way leaves the last page's button lit as well.
	for key in _nav:
		(_nav[key] as Button).set_pressed_no_signal(key == id)

	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	match id:
		&"general":
			_page_general()
		&"gameplay":
			_page_gameplay()
		&"video":
			_page_video()
		&"audio":
			_page_audio()
		&"controls":
			_page_controls()

	_scroll.scroll_vertical = 0


func _page_general() -> void:
	var hud := _card("Heads-up display")
	_switch_setting(hud, &"show_speed", "Speed", "Your speed in units per second, under the clock.")
	_switch_setting(hud, &"show_splits", "Splits", "How each stage compares with your best and the record.")
	_switch_setting(hud, &"show_zones", "Zones", "The start, stages and finish drawn as glowing boxes in the world.")
	_switch_setting(hud, &"show_keys", "Key display", "Which movement keys the simulation saw this tick.")
	_switch_setting(hud, &"show_crosshair", "Crosshair", "")
	_switch_setting(hud, &"show_fps", "Frame rate counter", "In the top-right corner.")

	var chat := _card("Chat")
	_select_setting(chat, &"chat_window", "Chat box", "Auto hides it on a server that already shows chat somewhere else.",
		[[&"auto", "Auto"], [&"on", "Always"], [&"off", "Never"]])


func _page_gameplay() -> void:
	var run := _card("Your run")
	var styles: Array = host.call("menu_styles") if _host_has("menu_styles") else []
	if styles.is_empty():
		_note(run, "No styles yet — the server has not said which it runs.")
	else:
		var options: Array = []
		for s in styles:
			options.append([StringName(str(s["id"])), str(s["name"])])
		var current: StringName = host.call("menu_style") if _host_has("menu_style") else &""
		_select_live(run, "Style", "How you run: normal, sideways, half-sideways, W only and the rest. Changing it restarts your run.",
			options, current, true,
			func(value: StringName) -> void:
				if _host_has("menu_choose_style"):
					host.call("menu_choose_style", value)
		)

	var view := _card("View")
	var light_allowed: bool = host.call("menu_flashlight_allowed") if _host_has("menu_flashlight_allowed") else true
	_switch_live(view, "Flashlight", "Only you see it. %s toggles it." % _key_for(&"g2g_flashlight")
		if light_allowed else "This server has turned flashlights off (sv_flashlight 0).",
		bool(host.call("menu_flashlight_on")) if _host_has("menu_flashlight_on") else false,
		light_allowed,
		func(on: bool) -> void:
			if _host_has("menu_set_flashlight"):
				host.call("menu_set_flashlight", on)
	)
	var third_allowed: bool = host.call("menu_third_person_allowed") if _host_has("menu_third_person_allowed") else true
	_switch_live(view, "Third person", "Cosmetic — the run is the same movement either way. %s switches." % _key_for(&"g2g_third_person")
		if third_allowed else "This server keeps everybody in first person.",
		bool(host.call("menu_third_person_on")) if _host_has("menu_third_person_on") else false,
		third_allowed,
		func(on: bool) -> void:
			if _host_has("menu_set_third_person"):
				host.call("menu_set_third_person", on)
	)
	_switch_setting(view, &"show_own_body", "Your own body", "Draw your character's body in first person. The head is never drawn.")

	var others := _card("Other players")
	_switch_setting(others, &"hide_others", "Hide other players",
		"Hides every other runner, the record's ghost, and everything about them — beacons, their pings. %s toggles it." % _key_for(&"g2g_hide_others"))

	var comfort := _card("Comfort")
	_slider_setting(comfort, &"shake_scale", "Camera shake", "Zero by default: a shaken camera on a ramp is a lost run.",
		0.0, 2.0, 0.05, func(v: float) -> String: return "Off" if v <= 0.0 else "%d%%" % roundi(v * 100.0))
	_switch_setting(comfort, &"allow_flashes", "Screen flashes", "A green tint on a personal best.")


func _page_video() -> void:
	var display := _card("Display")
	if not DotPlatform.is_web():
		_select_setting(display, &"window_mode", "Window", "",
			[[&"windowed", "Windowed"], [&"borderless", "Borderless fullscreen"], [&"fullscreen", "Fullscreen"]])
	else:
		_select_setting(display, &"window_mode", "Window", "Fullscreen also keeps browser shortcuts like Ctrl+W away from the game, in browsers that allow it.",
			[[&"windowed", "In the page"], [&"fullscreen", "Fullscreen"]])
	_switch_setting(display, &"vsync", "V-Sync", "Locks the frame rate to the screen. Off by default; a browser always syncs.")

	var fps_options: Array = []
	var stored := settings.get_int(&"fps_max", 0) if settings != null else 0
	var choices := FPS_CHOICES.duplicate()
	if not choices.has(stored):
		choices.append(stored)
		choices.sort()
	for n in choices:
		fps_options.append([n, "Unlimited" if n == 0 else "%d fps" % n])
	_select_setting(display, &"fps_max", "Max frame rate", "Unlimited by default. Capping it saves power and can steady a stuttering machine.", fps_options)

	var image := _card("Image")
	_slider_setting(image, &"field_of_view", "Field of view", "Horizontal at 4:3, the genre's own measure — 90 is what you are used to.",
		75.0, 120.0, 1.0, func(v: float) -> String: return "%d°" % roundi(v))
	_slider_setting(image, &"render_scale", "Render scale", "Draw the 3D world at a lower resolution and scale it up.",
		0.5, 1.0, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_select_setting(image, &"fx_quality", "Effects", "Particles at the start and finish gates.",
		[[0, "Off"], [1, "Low"], [2, "Medium"], [3, "High"]])


func _page_audio() -> void:
	var volume := _card("Volume")
	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	_slider_setting(volume, &"master_volume", "Master", "", 0.0, 1.0, 0.01, pct)
	_slider_setting(volume, &"sfx_volume", "Effects", "Jumps, landings, beacons.", 0.0, 1.0, 0.01, pct)
	_slider_setting(volume, &"ui_volume", "Timer & interface", "The start, the splits, the finish and the vote.", 0.0, 1.0, 0.01, pct)
	_slider_setting(volume, &"voice_volume", "Voice chat", "", 0.0, 1.0, 0.01, pct)


func _page_controls() -> void:
	var mouse := _card("Mouse")
	_slider_setting(mouse, &"sensitivity", "Sensitivity", "The genre's own number: 0.022 degrees per count times this. Bring yours with you.",
		0.1, 10.0, 0.05, func(v: float) -> String: return "%.2f" % v)
	_switch_setting(mouse, &"invert_mouse", "Invert vertical look", "")

	for group in G2GBindings.groups():
		var card := _card(group)
		for row in G2GBindings.ROWS:
			if str(row["group"]) == group:
				_binding_row(card, row)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(_reset_bindings)
	footer.add_child(reset)
	_body.add_child(footer)


func _binding_row(card: VBoxContainer, row: Dictionary) -> void:
	var button := G2GKeyButton.new()
	var key: StringName = row["setting"]
	button.binding = settings.get_string(key, str(row["default"])) if settings != null else str(row["default"])
	button.captured.connect(func(text: String) -> void: _rebind(row, text))
	_row(card, str(row["label"]), "", button)


## Puts [param text] on [param row]; whatever already had that key gets this row's old one.
##
## [b]A swap, not a refusal and not a steal.[/b] Refusing ("F is already the flashlight")
## makes a player unbind one thing to bind another, and stealing leaves the other action on
## nothing — which for a movement key is a control they cannot use. Swapping is the one of
## the three that never leaves anything unbound.
func _rebind(row: Dictionary, text: String) -> void:
	if settings == null:
		return

	var key: StringName = row["setting"]
	var old := settings.get_string(key, str(row["default"]))
	var other := G2GBindings.row_using(text, key, settings)

	var res := settings.set_value(key, text)
	if not res.ok:
		toast(res.error.message)
		return

	if not other.is_empty():
		var _swapped := settings.set_value(other["setting"], old)
		toast("%s is on %s now, and %s moved to %s." % [str(row["label"]), text, str(other["label"]), old])
	else:
		toast("%s is on %s now." % [str(row["label"]), text])

	_show_page(&"controls")


func _reset_bindings() -> void:
	if settings == null:
		return
	for row in G2GBindings.ROWS:
		var _reset := settings.reset_value(row["setting"])
	toast("Every key is back on its default.")
	_show_page(&"controls")


# --- Rows -------------------------------------------------------------------

func _card(title: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override(&"separation", 8)
	_body.add_child(wrap)

	if title != "":
		var head := MarginContainer.new()
		head.add_theme_constant_override(&"margin_top", 6)
		head.add_theme_constant_override(&"margin_left", 4)
		head.add_child(G2GUi.section(title))
		wrap.add_child(head)

	var card := G2GUi.card()
	wrap.add_child(card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 0)
	card.add_child(rows)
	return rows


func _row(card: VBoxContainer, title: String, description: String, control: Control) -> void:
	if card.get_child_count() > 0:
		card.add_child(HSeparator.new())

	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 18)
	line.custom_minimum_size = Vector2(0, 52)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override(&"separation", 1)
	words.add_child(G2GUi.label(title, G2GUi.SIZE_BODY, G2GUi.TEXT))
	if description != "":
		words.add_child(G2GUi.paragraph(description, G2GUi.SIZE_SMALL, G2GUi.DIM))
	line.add_child(words)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_top", 6)
	pad.add_theme_constant_override(&"margin_bottom", 6)
	pad.add_child(line)
	card.add_child(pad)


func _note(card: VBoxContainer, text: String) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_top", 12)
	pad.add_theme_constant_override(&"margin_bottom", 12)
	pad.add_child(G2GUi.paragraph(text))
	card.add_child(pad)


func _switch_setting(card: VBoxContainer, key: StringName, title: String, description: String) -> void:
	if not _has_setting(key):
		return
	var sw := G2GSwitch.new()
	sw.show_value(bool(settings.get_value(key)))
	sw.toggled.connect(func(on: bool) -> void: _write(key, on))
	_row(card, title, description, sw)


func _switch_live(
	card: VBoxContainer, title: String, description: String, value: bool, enabled: bool,
	on_toggle: Callable
) -> void:
	var sw := G2GSwitch.new()
	sw.show_value(value)
	sw.disabled = not enabled
	sw.toggled.connect(on_toggle)
	_row(card, title, description, sw)


func _slider_setting(
	card: VBoxContainer, key: StringName, title: String, description: String,
	low: float, high: float, step: float, shown: Callable
) -> void:
	if not _has_setting(key):
		return

	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size = Vector2(190, 22)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value = float(settings.get_value(key))

	var readout := G2GUi.label(shown.call(slider.value), G2GUi.SIZE_SMALL, G2GUi.MUTED)
	readout.custom_minimum_size = Vector2(52, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	slider.value_changed.connect(func(v: float) -> void:
		readout.text = shown.call(v)
		_write(key, v)
	)

	box.add_child(slider)
	box.add_child(readout)
	_row(card, title, description, box)


func _select_setting(
	card: VBoxContainer, key: StringName, title: String, description: String, options: Array
) -> void:
	if not _has_setting(key):
		return
	_select_live(card, title, description, options, settings.get_value(key), true,
		func(value: Variant) -> void: _write(key, value))


func _select_live(
	card: VBoxContainer, title: String, description: String, options: Array, current: Variant,
	enabled: bool, on_select: Callable
) -> void:
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(200, 36)
	pick.focus_mode = Control.FOCUS_ALL
	pick.fit_to_longest_item = true
	pick.disabled = not enabled

	for i in range(options.size()):
		pick.add_item(str(options[i][1]), i)
		if str(options[i][0]) == str(current):
			pick.select(i)

	pick.item_selected.connect(func(index: int) -> void: on_select.call(options[index][0]))
	_row(card, title, description, pick)


func _write(key: StringName, value: Variant) -> void:
	if settings == null:
		return
	var res := settings.set_value(key, value)
	if not res.ok:
		toast(res.error.message)
		DotLog.warn(CHANNEL, "a setting was refused", {"key": String(key), "why": res.error.message})


func _has_setting(key: StringName) -> bool:
	return settings != null and settings.schema != null and settings.schema.find(key) != null


func _host_has(method: String) -> bool:
	return host != null and host.has_method(method)


func _key_for(action: StringName) -> String:
	var row := G2GBindings.row_for_action(action)
	return G2GBindings.shown(row) if not row.is_empty() else "—"


# --- Buttons ----------------------------------------------------------------

func _primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	var pad := Vector4(16, 10, 16, 10)
	b.add_theme_stylebox_override(&"normal", G2GUi.box(G2GUi.ACCENT_DEEP, G2GUi.RADIUS_SMALL, Color(0, 0, 0, 0), 0, pad))
	b.add_theme_stylebox_override(&"hover", G2GUi.box(G2GUi.ACCENT_DEEP.lightened(0.12), G2GUi.RADIUS_SMALL, Color(0, 0, 0, 0), 0, pad))
	b.add_theme_stylebox_override(&"pressed", G2GUi.box(G2GUi.ACCENT, G2GUi.RADIUS_SMALL, Color(0, 0, 0, 0), 0, pad))
	b.add_theme_stylebox_override(&"focus", G2GUi.box(Color(0, 0, 0, 0), G2GUi.RADIUS_SMALL, Color(G2GUi.ACCENT, 0.8), 2))
	b.add_theme_color_override(&"font_color", Color(0.96, 1.0, 0.99))
	b.add_theme_color_override(&"font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override(&"font_focus_color", Color(0.96, 1.0, 0.99))
	b.add_theme_font_override(&"font", G2GUi.bold())
	return b


func _nav_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_ALL
	if group != null:
		b.toggle_mode = true
		b.button_group = group

	var pad := Vector4(14, 8, 12, 8)
	var clear := G2GUi.box(Color(0, 0, 0, 0), G2GUi.RADIUS_SMALL, Color(0, 0, 0, 0), 0, pad)
	var selected := G2GUi.box(G2GUi.ACCENT_WASH, G2GUi.RADIUS_SMALL, Color(0, 0, 0, 0), 0, pad)
	selected.border_color = G2GUi.ACCENT
	selected.border_width_left = 3
	b.add_theme_stylebox_override(&"normal", clear)
	b.add_theme_stylebox_override(&"hover", G2GUi.box(G2GUi.CARD_HOVER, G2GUi.RADIUS_SMALL, Color(0, 0, 0, 0), 0, pad))
	b.add_theme_stylebox_override(&"pressed", selected)
	b.add_theme_stylebox_override(&"hover_pressed", selected)
	b.add_theme_color_override(&"font_color", G2GUi.MUTED)
	b.add_theme_color_override(&"font_hover_color", G2GUi.TEXT)
	b.add_theme_color_override(&"font_focus_color", G2GUi.TEXT)
	return b


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func describe() -> Dictionary:
	return {"open": visible, "page": String(_page)}

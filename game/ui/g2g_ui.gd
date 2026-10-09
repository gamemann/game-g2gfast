extends RefCounted

## How this game's menus look: one palette, one [Theme], and the handful of pieces every
## screen is assembled from.
##
## [b]Here rather than in dot-ui, and that is dot-ui's own rule.[/b] dot-ui ships no art so
## that a game can bring its own; `DotUiTheme` is the legible default for a game that has
## none. This is a game bringing its own. It is also delivered as a pack into a client shell
## built with whatever dot-ui that shell had, so nothing here may depend on a dot-ui class
## newer than the shell — it builds on plain [Control]s and asks dot-ui for nothing.
##
## [b]Everything is a StyleBoxFlat and a colour.[/b] No texture, no font file: the pack
## stays small, and the menus look the same in a browser as on a desktop.

# --- Palette ----------------------------------------------------------------

## The palette in use. [b]Static vars rather than constants, with the constants' names[/b],
## so a theme can be switched while the game runs and not one call site had to change:
## `G2GUi.ACCENT` reads the same either way. Set only by [method use]; a screen built
## before a switch keeps the colours it was built with until it is rebuilt, which is why
## every screen here has a `restyle()`.
static var BACKDROP := Color(0.02, 0.03, 0.05, 0.62)
static var SURFACE := Color(0.075, 0.085, 0.115, 0.97)
static var SIDEBAR := Color(0.055, 0.063, 0.088, 1.0)
static var CARD := Color(1.0, 1.0, 1.0, 0.035)
static var CARD_HOVER := Color(1.0, 1.0, 1.0, 0.06)
static var LINE := Color(1.0, 1.0, 1.0, 0.07)
static var TEXT := Color(0.93, 0.945, 0.965)
static var MUTED := Color(0.63, 0.67, 0.73)
static var DIM := Color(0.44, 0.48, 0.55)
static var ACCENT := Color(0.33, 0.87, 0.78)
static var ACCENT_DEEP := Color(0.13, 0.58, 0.52)
static var ACCENT_WASH := Color(0.33, 0.87, 0.78, 0.13)
static var WARN := Color(0.98, 0.74, 0.35)
static var DANGER := Color(0.95, 0.43, 0.45)
static var KEYCAP := Color(0.16, 0.18, 0.23)
static var KEYCAP_EDGE := Color(0.27, 0.3, 0.37)

## The HUD's half of a theme: the plate behind the clock, the clock's own colours, and the
## text drawn straight over the world. Read by [G2GHud] whenever the theme changes.
static var HUD_PLATE := Color(0.0, 0.0, 0.0, 0.45)
static var HUD_TEXT := Color(0.92, 0.92, 0.92)
static var HUD_DETAIL := Color(0.72, 0.74, 0.78)
static var HUD_AHEAD := Color(0.35, 0.9, 0.4)
static var HUD_BEHIND := Color(0.95, 0.4, 0.35)

## The theme [method use] last applied.
static var current: StringName = &"midnight"

## Every theme, in the order the menu offers them and the key cycles them. The first is
## the default and is exactly the palette this file had before themes existed.
##
## [b]Whole palettes, not an accent swap.[/b] A different accent on the same dark surface
## is one theme in four colours; "Paper" is a light theme and "Contrast" is for a player
## who cannot read grey on grey, and both need the surfaces and the text to move with it.
## A light theme's HUD still draws on a dark plate: the HUD is over the world, and a bhop
## map is mostly sky, so a white plate is a white plate on a white sky.
const THEMES: Array[Dictionary] = [
	{
		"id": &"midnight", "name": "Midnight",
		"BACKDROP": Color(0.02, 0.03, 0.05, 0.62), "SURFACE": Color(0.075, 0.085, 0.115, 0.97),
		"SIDEBAR": Color(0.055, 0.063, 0.088, 1.0), "CARD": Color(1, 1, 1, 0.035),
		"CARD_HOVER": Color(1, 1, 1, 0.06), "LINE": Color(1, 1, 1, 0.07),
		"TEXT": Color(0.93, 0.945, 0.965), "MUTED": Color(0.63, 0.67, 0.73), "DIM": Color(0.44, 0.48, 0.55),
		"ACCENT": Color(0.33, 0.87, 0.78), "ACCENT_DEEP": Color(0.13, 0.58, 0.52),
		"WARN": Color(0.98, 0.74, 0.35), "DANGER": Color(0.95, 0.43, 0.45),
		"KEYCAP": Color(0.16, 0.18, 0.23), "KEYCAP_EDGE": Color(0.27, 0.3, 0.37),
		"HUD_PLATE": Color(0, 0, 0, 0.45), "HUD_TEXT": Color(0.92, 0.92, 0.92), "HUD_DETAIL": Color(0.72, 0.74, 0.78),
		"HUD_AHEAD": Color(0.35, 0.9, 0.4), "HUD_BEHIND": Color(0.95, 0.4, 0.35),
	},
	{
		"id": &"ember", "name": "Ember",
		"BACKDROP": Color(0.05, 0.03, 0.02, 0.62), "SURFACE": Color(0.11, 0.08, 0.065, 0.97),
		"SIDEBAR": Color(0.085, 0.06, 0.05, 1.0), "CARD": Color(1, 0.9, 0.8, 0.04),
		"CARD_HOVER": Color(1, 0.9, 0.8, 0.07), "LINE": Color(1, 0.9, 0.8, 0.08),
		"TEXT": Color(0.97, 0.94, 0.9), "MUTED": Color(0.74, 0.66, 0.6), "DIM": Color(0.55, 0.47, 0.42),
		"ACCENT": Color(1.0, 0.6, 0.25), "ACCENT_DEEP": Color(0.72, 0.36, 0.1),
		"WARN": Color(1.0, 0.82, 0.4), "DANGER": Color(0.95, 0.38, 0.38),
		"KEYCAP": Color(0.21, 0.16, 0.13), "KEYCAP_EDGE": Color(0.36, 0.27, 0.22),
		"HUD_PLATE": Color(0.08, 0.03, 0.0, 0.5), "HUD_TEXT": Color(1.0, 0.95, 0.88), "HUD_DETAIL": Color(0.92, 0.75, 0.6),
		"HUD_AHEAD": Color(0.5, 0.92, 0.45), "HUD_BEHIND": Color(1.0, 0.42, 0.32),
	},
	{
		"id": &"violet", "name": "Violet",
		"BACKDROP": Color(0.03, 0.02, 0.06, 0.62), "SURFACE": Color(0.09, 0.075, 0.13, 0.97),
		"SIDEBAR": Color(0.065, 0.055, 0.1, 1.0), "CARD": Color(0.9, 0.85, 1, 0.04),
		"CARD_HOVER": Color(0.9, 0.85, 1, 0.07), "LINE": Color(0.9, 0.85, 1, 0.08),
		"TEXT": Color(0.95, 0.93, 0.99), "MUTED": Color(0.69, 0.65, 0.78), "DIM": Color(0.5, 0.46, 0.6),
		"ACCENT": Color(0.72, 0.55, 1.0), "ACCENT_DEEP": Color(0.46, 0.3, 0.78),
		"WARN": Color(0.98, 0.76, 0.4), "DANGER": Color(1.0, 0.45, 0.6),
		"KEYCAP": Color(0.18, 0.15, 0.26), "KEYCAP_EDGE": Color(0.31, 0.26, 0.42),
		"HUD_PLATE": Color(0.04, 0.0, 0.1, 0.48), "HUD_TEXT": Color(0.96, 0.94, 1.0), "HUD_DETAIL": Color(0.8, 0.74, 0.95),
		"HUD_AHEAD": Color(0.45, 0.95, 0.65), "HUD_BEHIND": Color(1.0, 0.45, 0.6),
	},
	{
		"id": &"classic", "name": "Classic",
		"BACKDROP": Color(0.0, 0.0, 0.0, 0.55), "SURFACE": Color(0.17, 0.18, 0.16, 0.97),
		"SIDEBAR": Color(0.13, 0.14, 0.12, 1.0), "CARD": Color(0.0, 0.0, 0.0, 0.18),
		"CARD_HOVER": Color(0.0, 0.0, 0.0, 0.28), "LINE": Color(1, 1, 1, 0.09),
		"TEXT": Color(0.86, 0.87, 0.82), "MUTED": Color(0.66, 0.68, 0.6), "DIM": Color(0.5, 0.52, 0.45),
		"ACCENT": Color(0.85, 0.78, 0.3), "ACCENT_DEEP": Color(0.55, 0.5, 0.18),
		"WARN": Color(0.95, 0.7, 0.3), "DANGER": Color(0.9, 0.35, 0.3),
		"KEYCAP": Color(0.24, 0.25, 0.22), "KEYCAP_EDGE": Color(0.38, 0.39, 0.34),
		"HUD_PLATE": Color(0.0, 0.0, 0.0, 0.6), "HUD_TEXT": Color(1.0, 1.0, 1.0), "HUD_DETAIL": Color(0.85, 0.82, 0.6),
		"HUD_AHEAD": Color(0.3, 1.0, 0.3), "HUD_BEHIND": Color(1.0, 0.3, 0.3),
	},
	{
		"id": &"paper", "name": "Paper",
		"BACKDROP": Color(0.92, 0.93, 0.95, 0.5), "SURFACE": Color(0.97, 0.97, 0.96, 0.98),
		"SIDEBAR": Color(0.92, 0.92, 0.9, 1.0), "CARD": Color(0, 0, 0, 0.035),
		"CARD_HOVER": Color(0, 0, 0, 0.06), "LINE": Color(0, 0, 0, 0.09),
		"TEXT": Color(0.1, 0.11, 0.13), "MUTED": Color(0.34, 0.36, 0.4), "DIM": Color(0.5, 0.52, 0.56),
		"ACCENT": Color(0.1, 0.45, 0.85), "ACCENT_DEEP": Color(0.1, 0.4, 0.78),
		"WARN": Color(0.75, 0.45, 0.0), "DANGER": Color(0.78, 0.15, 0.2),
		"KEYCAP": Color(1.0, 1.0, 1.0), "KEYCAP_EDGE": Color(0.72, 0.73, 0.76),
		"HUD_PLATE": Color(0.98, 0.98, 0.97, 0.82), "HUD_TEXT": Color(0.08, 0.09, 0.11), "HUD_DETAIL": Color(0.28, 0.3, 0.35),
		"HUD_AHEAD": Color(0.05, 0.55, 0.2), "HUD_BEHIND": Color(0.8, 0.12, 0.15),
	},
	{
		"id": &"contrast", "name": "High contrast",
		"BACKDROP": Color(0, 0, 0, 0.8), "SURFACE": Color(0, 0, 0, 1.0),
		"SIDEBAR": Color(0.06, 0.06, 0.06, 1.0), "CARD": Color(1, 1, 1, 0.06),
		"CARD_HOVER": Color(1, 1, 1, 0.14), "LINE": Color(1, 1, 1, 0.3),
		"TEXT": Color(1, 1, 1), "MUTED": Color(0.9, 0.9, 0.9), "DIM": Color(0.78, 0.78, 0.78),
		"ACCENT": Color(1.0, 0.86, 0.0), "ACCENT_DEEP": Color(0.85, 0.7, 0.0),
		"WARN": Color(1.0, 0.7, 0.0), "DANGER": Color(1.0, 0.35, 0.35),
		"KEYCAP": Color(0.12, 0.12, 0.12), "KEYCAP_EDGE": Color(1, 1, 1, 0.7),
		"HUD_PLATE": Color(0, 0, 0, 0.85), "HUD_TEXT": Color(1, 1, 1), "HUD_DETAIL": Color(1.0, 0.92, 0.4),
		"HUD_AHEAD": Color(0.3, 1.0, 0.4), "HUD_BEHIND": Color(1.0, 0.35, 0.35),
	},
]


## The theme ids, in order. What the settings schema offers.
static func theme_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in THEMES:
		out.append(t["id"])
	return out


## The theme called [param id], or the first one for an id nobody knows — a settings file
## from a newer build, or one edited by hand, gets the default rather than no palette.
static func theme_named(id: StringName) -> Dictionary:
	for t in THEMES:
		if t["id"] == id:
			return t
	return THEMES[0]


## The theme after [param id], round the end. What the theme key does.
static func next_theme(id: StringName) -> StringName:
	var ids := theme_ids()
	var at := ids.find(id)
	return ids[(at + 1) % ids.size()] if at >= 0 else ids[0]


## Makes [param id] the palette. Returns whether anything changed; a screen rebuilds only
## when it did.
static func use(id: StringName) -> bool:
	var t := theme_named(id)
	if t["id"] == current:
		return false
	current = t["id"]
	BACKDROP = t["BACKDROP"]
	SURFACE = t["SURFACE"]
	SIDEBAR = t["SIDEBAR"]
	CARD = t["CARD"]
	CARD_HOVER = t["CARD_HOVER"]
	LINE = t["LINE"]
	TEXT = t["TEXT"]
	MUTED = t["MUTED"]
	DIM = t["DIM"]
	ACCENT = t["ACCENT"]
	ACCENT_DEEP = t["ACCENT_DEEP"]
	ACCENT_WASH = Color(ACCENT, 0.13)
	WARN = t["WARN"]
	DANGER = t["DANGER"]
	KEYCAP = t["KEYCAP"]
	KEYCAP_EDGE = t["KEYCAP_EDGE"]
	HUD_PLATE = t["HUD_PLATE"]
	HUD_TEXT = t["HUD_TEXT"]
	HUD_DETAIL = t["HUD_DETAIL"]
	HUD_AHEAD = t["HUD_AHEAD"]
	HUD_BEHIND = t["HUD_BEHIND"]
	return true


## Whether the surfaces are light. A few pieces drawn straight in white — a switch's knob
## on its track — need to know.
static func is_light() -> bool:
	return SURFACE.get_luminance() > 0.5


## Black or white, whichever reads on [param fill]. For text on the accent, which is a dark
## teal in one theme and a bright yellow in another.
static func ink_on(fill: Color) -> Color:
	return Color(0.04, 0.04, 0.05) if fill.get_luminance() > 0.55 else Color(0.97, 0.99, 1.0)

const RADIUS := 14
const RADIUS_SMALL := 9

const SIZE_TITLE := 26
const SIZE_HEADING := 19
const SIZE_BODY := 15
const SIZE_SMALL := 13


# --- Fonts ------------------------------------------------------------------

static var _bold: FontVariation = null


## The engine's own font, emboldened. A font file would be the first binary in the pack
## that is not a map, for a weight the engine can synthesise.
static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


# --- Boxes ------------------------------------------------------------------

static func box(
	fill: Color, radius: int = RADIUS, border: Color = Color(0, 0, 0, 0), border_width: int = 0,
	pad: Vector4 = Vector4(0, 0, 0, 0)
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.corner_detail = 6
	s.anti_aliasing = true
	if border_width > 0:
		s.border_color = border
		s.set_border_width_all(border_width)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s


## The big card a menu sits on: rounded, bordered faintly, and lifted off the game by a
## soft shadow rather than by a heavy outline.
static func surface_box() -> StyleBoxFlat:
	var s := box(SURFACE, RADIUS + 4, LINE, 1)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 28
	s.shadow_offset = Vector2(0, 10)
	return s


# --- The theme --------------------------------------------------------------

## A fresh [Theme] every call, for dot-ui's reason: a Theme is mutable and shared.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = SIZE_BODY

	t.set_color(&"font_color", &"Label", TEXT)

	# Buttons: quiet by default, a wash of the accent on hover, the accent itself pressed.
	var pad := Vector4(16, 9, 16, 9)
	t.set_stylebox(&"normal", &"Button", box(CARD, RADIUS_SMALL, LINE, 1, pad))
	t.set_stylebox(&"hover", &"Button", box(CARD_HOVER, RADIUS_SMALL, Color(TEXT, 0.12), 1, pad))
	t.set_stylebox(&"pressed", &"Button", box(ACCENT_WASH, RADIUS_SMALL, ACCENT, 1, pad))
	t.set_stylebox(&"hover_pressed", &"Button", box(ACCENT_WASH, RADIUS_SMALL, ACCENT, 1, pad))
	t.set_stylebox(&"disabled", &"Button", box(Color(TEXT, 0.015), RADIUS_SMALL, LINE, 1, pad))
	t.set_stylebox(&"focus", &"Button", box(Color(0, 0, 0, 0), RADIUS_SMALL, Color(ACCENT, 0.7), 2))
	t.set_color(&"font_color", &"Button", TEXT)
	t.set_color(&"font_hover_color", &"Button", TEXT)
	t.set_color(&"font_pressed_color", &"Button", ACCENT)
	t.set_color(&"font_hover_pressed_color", &"Button", ACCENT)
	t.set_color(&"font_focus_color", &"Button", TEXT)
	t.set_color(&"font_disabled_color", &"Button", DIM)

	# A select box looks like a button with a caret.
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		t.set_stylebox(state, &"OptionButton", t.get_stylebox(state, &"Button"))
	# A well on a dark surface and a raised field on a light one: a dark wash over a light
	# card reads as a disabled control.
	var field := Color(1, 1, 1, 0.85) if is_light() else Color(0, 0, 0, 0.25)
	var field_hover := Color(1, 1, 1, 1.0) if is_light() else Color(0, 0, 0, 0.32)
	t.set_stylebox(&"normal", &"OptionButton", box(field, RADIUS_SMALL, LINE, 1, Vector4(14, 8, 14, 8)))
	t.set_stylebox(&"hover", &"OptionButton", box(field_hover, RADIUS_SMALL, Color(TEXT, 0.16), 1, Vector4(14, 8, 14, 8)))
	t.set_color(&"font_color", &"OptionButton", TEXT)
	t.set_color(&"font_hover_color", &"OptionButton", TEXT)
	t.set_color(&"font_pressed_color", &"OptionButton", ACCENT)
	t.set_color(&"font_disabled_color", &"OptionButton", DIM)
	t.set_constant(&"arrow_margin", &"OptionButton", 10)

	# The list a select box opens.
	t.set_stylebox(&"panel", &"PopupMenu", box(Color(SURFACE, 0.99), RADIUS_SMALL, Color(TEXT, 0.1), 1, Vector4(6, 6, 6, 6)))
	t.set_stylebox(&"hover", &"PopupMenu", box(ACCENT_WASH, 6))
	t.set_color(&"font_color", &"PopupMenu", TEXT)
	t.set_color(&"font_hover_color", &"PopupMenu", ACCENT)
	t.set_constant(&"v_separation", &"PopupMenu", 10)
	t.set_constant(&"item_start_padding", &"PopupMenu", 10)
	t.set_constant(&"item_end_padding", &"PopupMenu", 14)

	# Sliders: a thin rail, the filled part in the accent, a round grabber.
	var rail := box(Color(TEXT, 0.09), 3)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	var filled := box(ACCENT_DEEP, 3)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	t.set_stylebox(&"slider", &"HSlider", rail)
	t.set_stylebox(&"grabber_area", &"HSlider", filled)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", box(ACCENT, 3))
	t.set_icon(&"grabber", &"HSlider", _dot(16, TEXT))
	t.set_icon(&"grabber_highlight", &"HSlider", _dot(18, ACCENT))
	t.set_icon(&"grabber_disabled", &"HSlider", _dot(16, DIM))

	# Scroll bars that stay out of the way.
	t.set_stylebox(&"scroll", &"VScrollBar", box(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, Vector4(3, 0, 3, 0)))
	t.set_stylebox(&"grabber", &"VScrollBar", box(Color(TEXT, 0.12), 4))
	t.set_stylebox(&"grabber_highlight", &"VScrollBar", box(Color(TEXT, 0.22), 4))
	t.set_stylebox(&"grabber_pressed", &"VScrollBar", box(ACCENT_DEEP, 4))

	t.set_stylebox(&"panel", &"PanelContainer", box(Color(0, 0, 0, 0), 0))
	t.set_stylebox(&"separator", &"HSeparator", box(LINE, 0))
	t.set_constant(&"separation", &"HSeparator", 1)

	t.set_color(&"font_color", &"TooltipLabel", TEXT)
	t.set_stylebox(&"panel", &"TooltipPanel", box(Color(SURFACE, 0.98), 8, Color(TEXT, 0.1), 1, Vector4(10, 6, 10, 6)))
	return t


## A filled circle, for a slider's grabber. Drawn into an image once per call.
static func _dot(diameter: int, colour: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in range(diameter):
		for x in range(diameter):
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(colour.r, colour.g, colour.b, colour.a * a))
	return ImageTexture.create_from_image(img)


# --- Pieces -----------------------------------------------------------------

static func label(
	text: String, size: int = SIZE_BODY, colour: Color = TEXT, heavy: bool = false
) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	if heavy:
		l.add_theme_font_override(&"font", bold())
	return l


## A paragraph that wraps inside whatever width it is given.
static func paragraph(text: String, size: int = SIZE_SMALL, colour: Color = MUTED) -> Label:
	var l := label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(1, 0)
	return l


## A key drawn as a key. [param text] is a binding's own spelling ("Ctrl", "F5", "Mouse 4").
static func keycap(text: String, size: int = SIZE_SMALL) -> PanelContainer:
	var cap := PanelContainer.new()
	var s := box(KEYCAP, 6, KEYCAP_EDGE, 1, Vector4(9, 3, 9, 4))
	s.border_width_bottom = 3
	cap.add_theme_stylebox_override(&"panel", s)
	var l := label(text, size, TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap


## A rounded group of rows, with a little air between them.
static func card() -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override(&"panel", box(CARD, RADIUS, LINE, 1, Vector4(18, 8, 18, 8)))
	return c


## The section title over a card.
static func section(text: String) -> Label:
	var l := label(text.to_upper(), SIZE_SMALL - 1, ACCENT, true)
	return l


## A [Control] sized by the anchors of its parent, every offset set explicitly — the trap
## dot-ui's own notes have paid for seven times: an anchor set on a Control with no rectangle
## yet keeps a zero size.
static func fill_parent(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

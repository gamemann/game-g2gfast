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

const BACKDROP := Color(0.02, 0.03, 0.05, 0.62)
const SURFACE := Color(0.075, 0.085, 0.115, 0.97)
const SIDEBAR := Color(0.055, 0.063, 0.088, 1.0)
const CARD := Color(1.0, 1.0, 1.0, 0.035)
const CARD_HOVER := Color(1.0, 1.0, 1.0, 0.06)
const LINE := Color(1.0, 1.0, 1.0, 0.07)
const TEXT := Color(0.93, 0.945, 0.965)
const MUTED := Color(0.63, 0.67, 0.73)
const DIM := Color(0.44, 0.48, 0.55)
const ACCENT := Color(0.33, 0.87, 0.78)
const ACCENT_DEEP := Color(0.13, 0.58, 0.52)
const ACCENT_WASH := Color(0.33, 0.87, 0.78, 0.13)
const WARN := Color(0.98, 0.74, 0.35)
const DANGER := Color(0.95, 0.43, 0.45)
const KEYCAP := Color(0.16, 0.18, 0.23)
const KEYCAP_EDGE := Color(0.27, 0.3, 0.37)

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
	t.set_stylebox(&"hover", &"Button", box(CARD_HOVER, RADIUS_SMALL, Color(1, 1, 1, 0.12), 1, pad))
	t.set_stylebox(&"pressed", &"Button", box(ACCENT_WASH, RADIUS_SMALL, ACCENT, 1, pad))
	t.set_stylebox(&"hover_pressed", &"Button", box(ACCENT_WASH, RADIUS_SMALL, ACCENT, 1, pad))
	t.set_stylebox(&"disabled", &"Button", box(Color(1, 1, 1, 0.015), RADIUS_SMALL, LINE, 1, pad))
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
	t.set_stylebox(&"normal", &"OptionButton", box(Color(0, 0, 0, 0.25), RADIUS_SMALL, LINE, 1, Vector4(14, 8, 14, 8)))
	t.set_stylebox(&"hover", &"OptionButton", box(Color(0, 0, 0, 0.32), RADIUS_SMALL, Color(1, 1, 1, 0.16), 1, Vector4(14, 8, 14, 8)))
	t.set_color(&"font_color", &"OptionButton", TEXT)
	t.set_color(&"font_hover_color", &"OptionButton", TEXT)
	t.set_color(&"font_pressed_color", &"OptionButton", ACCENT)
	t.set_color(&"font_disabled_color", &"OptionButton", DIM)
	t.set_constant(&"arrow_margin", &"OptionButton", 10)

	# The list a select box opens.
	t.set_stylebox(&"panel", &"PopupMenu", box(Color(0.09, 0.1, 0.135, 0.99), RADIUS_SMALL, Color(1, 1, 1, 0.1), 1, Vector4(6, 6, 6, 6)))
	t.set_stylebox(&"hover", &"PopupMenu", box(ACCENT_WASH, 6))
	t.set_color(&"font_color", &"PopupMenu", TEXT)
	t.set_color(&"font_hover_color", &"PopupMenu", ACCENT)
	t.set_constant(&"v_separation", &"PopupMenu", 10)
	t.set_constant(&"item_start_padding", &"PopupMenu", 10)
	t.set_constant(&"item_end_padding", &"PopupMenu", 14)

	# Sliders: a thin rail, the filled part in the accent, a round grabber.
	var rail := box(Color(1, 1, 1, 0.09), 3)
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
	t.set_stylebox(&"grabber", &"VScrollBar", box(Color(1, 1, 1, 0.12), 4))
	t.set_stylebox(&"grabber_highlight", &"VScrollBar", box(Color(1, 1, 1, 0.22), 4))
	t.set_stylebox(&"grabber_pressed", &"VScrollBar", box(ACCENT_DEEP, 4))

	t.set_stylebox(&"panel", &"PanelContainer", box(Color(0, 0, 0, 0), 0))
	t.set_stylebox(&"separator", &"HSeparator", box(LINE, 0))
	t.set_constant(&"separation", &"HSeparator", 1)

	t.set_color(&"font_color", &"TooltipLabel", TEXT)
	t.set_stylebox(&"panel", &"TooltipPanel", box(Color(0.1, 0.11, 0.15, 0.98), 8, Color(1, 1, 1, 0.1), 1, Vector4(10, 6, 10, 6)))
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

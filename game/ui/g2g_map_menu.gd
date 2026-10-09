extends Control

const G2GUi := preload("g2g_ui.gd")

## The M screen: every map this server has, a page at a time, to change to.
##
## [b]Every map, not the rotation.[/b] An operator keeps maps installed that the rotation
## does not play (`cfg/map_rotation.yml`); this list shows them all and marks the ones
## that are not in rotation, because "which maps does this box have" and "which ones
## come round on their own" are two questions and the second hides the first. A combat
## map -- one for game-arena's deathmatch, which this game can load and does not rotate
## -- is marked too.
##
## Keys are the timer plugins' menu keys, because that is what a bhop player's fingers
## already know: 1-7 pick a row, 8 is the previous page, 9 the next, 0 (or Esc, or M)
## closes. The mouse works as well -- the screen frees the pointer like the help screen
## does -- and a row says its number so the two never disagree.
##
## Offline the list is the local catalogue and a pick changes the map here. Online it is
## the SERVER's list, sent only to a player who holds the changemap flag, and a pick asks
## the server, which checks the flag again: see `G2GNetBridge.ask_maps`.

signal closed()

## The player picked [param id].
signal chosen(id: StringName)

## Rows per page. Seven, so 8 and 9 stay the page keys.
const PAGE_SIZE := 7

## `{id, name, tier, kind, rotation, current}` per map, in the order shown.
var maps: Array = []

## Shown in the title: "this server" online, "offline" otherwise.
var where: String = "offline"

var page: int = 0

var _window: PanelContainer = null
var _rows: VBoxContainer = null
var _title: Label = null
var _footer: Label = null


func _ready() -> void:
	theme = G2GUi.theme()
	G2GUi.fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.05, 0.55)
	G2GUi.fill_parent(back)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var centre := CenterContainer.new()
	G2GUi.fill_parent(centre)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_window = PanelContainer.new()
	var s := G2GUi.surface_box()
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 20
	s.content_margin_bottom = 18
	_window.add_theme_stylebox_override(&"panel", s)
	_window.custom_minimum_size = Vector2(560, 0)
	centre.add_child(_window)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	_window.add_child(col)

	_title = G2GUi.label("Change map", G2GUi.SIZE_TITLE, G2GUi.TEXT, true)
	col.add_child(_title)
	col.add_child(G2GUi.paragraph("1–7 or click to change to it. 8 and 9 turn the page. 0, M or Esc closes."))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 4)
	col.add_child(_rows)

	_footer = G2GUi.label("", G2GUi.SIZE_SMALL, G2GUi.DIM)
	col.add_child(_footer)


func open(list: Array, p_where: String = "offline") -> void:
	maps = list
	where = p_where
	# Open on the page with the map being played, so "what is on now" is the first thing seen.
	page = 0
	for i in maps.size():
		if bool((maps[i] as Dictionary).get("current", false)):
			page = i / PAGE_SIZE
			break
	_rebuild()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func pages() -> int:
	return maxi(1, ceili(float(maps.size()) / float(PAGE_SIZE)))


func turn(by: int) -> void:
	page = clampi(page + by, 0, pages() - 1)
	_rebuild()


## The map on row [param row] (1-based) of the page, or null.
func at_row(row: int) -> Variant:
	var i := page * PAGE_SIZE + row - 1
	if row < 1 or row > PAGE_SIZE or i < 0 or i >= maps.size():
		return null
	return maps[i]


func pick(row: int) -> bool:
	var m: Variant = at_row(row)
	if m == null:
		return false
	chosen.emit(StringName(str((m as Dictionary)["id"])))
	close()
	return true


## The number keys, from the client's overlay handler. True when the key was the menu's.
func key(keycode: Key) -> bool:
	var digit := -1
	if keycode >= KEY_0 and keycode <= KEY_9:
		digit = keycode - KEY_0
	elif keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		digit = keycode - KEY_KP_0
	match digit:
		-1:
			return false
		0:
			close()
		8:
			turn(-1)
		9:
			turn(1)
		_:
			var _picked := pick(digit)
	return true


func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()

	_title.text = "Change map — %s" % where
	if maps.is_empty():
		_rows.add_child(G2GUi.paragraph("No maps."))

	for row in range(1, PAGE_SIZE + 1):
		var m: Variant = at_row(row)
		if m == null:
			break
		_rows.add_child(_row(row, m as Dictionary))

	var out_of := 0
	for m: Dictionary in maps:
		if not bool(m.get("rotation", true)):
			out_of += 1
	_footer.text = "Page %d of %d  ·  %d maps, %d not in rotation  ·  8 previous  9 next" % [
		page + 1, pages(), maps.size(), out_of]


func _row(row: int, m: Dictionary) -> Control:
	var button := Button.new()
	button.flat = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 38)
	button.pressed.connect(func() -> void: var _p := pick(row))

	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	G2GUi.fill_parent(line)
	line.offset_left = 10
	line.offset_right = -10
	button.add_child(line)

	var cap := G2GUi.keycap(str(row))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(cap)

	var name := G2GUi.label(str(m.get("name", m.get("id", "?"))), G2GUi.SIZE_BODY,
		G2GUi.ACCENT if bool(m.get("current", false)) else G2GUi.TEXT, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name)

	var tags := PackedStringArray()
	if bool(m.get("current", false)):
		tags.append("playing")
	if str(m.get("kind", "")) == "arena":
		tags.append("combat")
	if not bool(m.get("rotation", true)):
		tags.append("not in rotation")
	if int(m.get("tier", 0)) > 0:
		tags.append("tier %d" % int(m["tier"]))
	var tag := G2GUi.label("  ·  ".join(tags), G2GUi.SIZE_SMALL,
		G2GUi.WARN if not bool(m.get("rotation", true)) else G2GUi.MUTED)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(tag)
	return button


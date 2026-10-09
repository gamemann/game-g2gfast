extends RefCounted

## Every key this client reads, as one table: the action, the setting that stores it, the
## words a player sees, and the default.
##
## [b]Data, because four things read it and they must never disagree.[/b] The client
## matches events against the actions, the settings schema declares one binding per row,
## the menu's key-binding page draws a row per entry, and the help screen (H) lists what
## each key does. Before this the keys were a `match` on keycodes in `G2GClient` and a
## sentence in its doc comment, and the sentence had already drifted once — the README
## said Shift for duck for as long as the dead `[input]` block did.
##
## [b]The movement actions are dot-player-controller's own names.[/b] `DotFpsSampler` polls
## `dot_fps_*` and `register_default_actions` only creates what is missing, so a binding
## applied here first is the one it reads — there is no second copy of the movement keys.
##
## [b]Stored per DEVICE, except chat.[/b] A key is a fact about a keyboard: the laptop and
## the desktop are laid out differently, and a binding synchronised between them breaks one
## of the two. The two chat keys were ACCOUNT scope before this table existed and keep it,
## because changing a stored setting's scope would quietly reset somebody's chosen key.
##
## Escape is not in the table and cannot be bound: it is the menu, it is how a browser
## releases the pointer, and a player who bound it to something else could never leave.

const CHANNEL := "g2g.bindings"

## Rows, in the order the menu and the help screen draw them. [code]setting[/code] is the
## [DotSettingsManager] key; a [code]bind_[/code] key is declared by [method add_to_schema],
## the two chat keys by the presentation layer, which owned them first.
const ROWS: Array[Dictionary] = [
	{"action": &"dot_fps_forward", "setting": &"bind_forward", "label": "Forward", "default": "W", "group": "Movement"},
	{"action": &"dot_fps_back", "setting": &"bind_back", "label": "Back", "default": "S", "group": "Movement"},
	{"action": &"dot_fps_left", "setting": &"bind_left", "label": "Strafe left", "default": "A", "group": "Movement"},
	{"action": &"dot_fps_right", "setting": &"bind_right", "label": "Strafe right", "default": "D", "group": "Movement"},
	{"action": &"dot_fps_jump", "setting": &"bind_jump", "label": "Jump", "default": "Space", "group": "Movement"},
	{"action": &"dot_fps_crouch", "setting": &"bind_duck", "label": "Duck", "default": "Ctrl", "group": "Movement"},

	{"action": &"g2g_restart", "setting": &"bind_restart", "label": "Restart run", "default": "R", "group": "Running"},
	{"action": &"g2g_checkpoint_save", "setting": &"bind_checkpoint_save", "label": "Save checkpoint", "default": "C", "group": "Running"},
	{"action": &"g2g_checkpoint_load", "setting": &"bind_checkpoint_load", "label": "Go to checkpoint", "default": "V", "group": "Running"},
	{"action": &"g2g_style_next", "setting": &"bind_style_next", "label": "Next style", "default": "Tab", "group": "Running"},
	{"action": &"g2g_map_next", "setting": &"bind_map_next", "label": "Map list (offline, or an admin)", "default": "M", "group": "Running"},
	{"action": &"g2g_zones", "setting": &"bind_zones", "label": "Zone editor (offline, or an admin)", "default": "Z", "group": "Running"},

	{"action": &"g2g_flashlight", "setting": &"bind_flashlight", "label": "Flashlight", "default": "F", "group": "View"},
	{"action": &"g2g_hide_others", "setting": &"bind_hide_others", "label": "Hide other players", "default": "O", "group": "View"},
	{"action": &"g2g_third_person", "setting": &"bind_third_person", "label": "First / third person", "default": "F5", "group": "View"},

	{"action": &"g2g_chat", "setting": &"chat_open_key", "label": "Chat", "default": "Y", "group": "Communication"},
	{"action": &"g2g_chat_team", "setting": &"chat_team_key", "label": "Team chat", "default": "U", "group": "Communication"},
	{"action": &"g2g_voice", "setting": &"bind_voice", "label": "Push to talk", "default": "K", "group": "Communication"},

	{"action": &"g2g_help", "setting": &"bind_help", "label": "Help", "default": "H", "group": "Interface"},
	{"action": &"g2g_servers", "setting": &"bind_servers", "label": "Server list", "default": "F3", "group": "Interface"},
]


## Declares a DEVICE-scoped binding for every row this file owns.
static func add_to_schema(s: DotSettingsSchema) -> void:
	for row in ROWS:
		var key: StringName = row["setting"]

		if not String(key).begins_with("bind_"):
			continue

		s.add(DotSettingsDef.binding(key, str(row["default"]), &"bindings")
			.with_description(str(row["label"])))


## The row whose setting is [param key], or an empty dictionary.
static func row_for_setting(key: StringName) -> Dictionary:
	for row in ROWS:
		if row["setting"] == key:
			return row

	return {}


## The row for [param action], or an empty dictionary.
static func row_for_action(action: StringName) -> Dictionary:
	for row in ROWS:
		if row["action"] == action:
			return row

	return {}


## The groups, in table order, each once.
static func groups() -> PackedStringArray:
	var out := PackedStringArray()

	for row in ROWS:
		if not out.has(str(row["group"])):
			out.append(str(row["group"]))

	return out


## Puts one stored binding on its action. Returns what ended up bound.
##
## [b]Empty falls back to the default rather than unbinding.[/b] A settings file somebody
## cleared by hand would otherwise leave Forward bound to nothing, and the menu that could
## put it back is reached with a key the same file may have broken. Unbinding on purpose
## is done by binding the key to something else, which swaps (see the menu).
static func apply_row(row: Dictionary, text: String) -> String:
	var wanted := text if DotInputBinding.is_bound(text) else str(row["default"])
	var bound := DotInputBinding.apply(row["action"], wanted)

	if bound == DotInputBinding.UNBOUND:
		DotLog.warn(CHANNEL, "a key binding names no input; the default is used", {
			"action": String(row["action"]), "binding": text,
		})
		bound = DotInputBinding.apply(row["action"], str(row["default"]))

	return bound


## Every row from [param settings] onto the [InputMap]. Boot, and a reset.
static func apply_all(settings: DotSettingsManager) -> void:
	for row in ROWS:
		var stored := settings.get_string(row["setting"], str(row["default"])) \
			if settings != null else str(row["default"])
		apply_row(row, stored)


## The key a row is on right now, for a button or a help line. "—" for nothing.
static func shown(row: Dictionary) -> String:
	var text := DotInputBinding.describe_action(row["action"])
	return text if text != DotInputBinding.UNBOUND else "—"


## The row already using [param text], other than [param except], or an empty dictionary.
## What the menu swaps with, so binding F to jump does not leave F on the flashlight too.
static func row_using(text: String, except: StringName, settings: DotSettingsManager) -> Dictionary:
	var wanted := DotInputBinding.from_text(text)

	if wanted == null:
		return {}

	for row in ROWS:
		if row["setting"] == except:
			continue

		var other := DotInputBinding.from_text(settings.get_string(row["setting"], str(row["default"])))

		if other != null and _same_input(wanted, other):
			return row

	return {}


## Physical key and modifiers, or the same mouse button. The rebinder's own comparison,
## for the reason dot-ui gives: a binding is where the key is, not what it says.
static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		return ka.physical_keycode == kb.physical_keycode \
			and ka.shift_pressed == kb.shift_pressed and ka.ctrl_pressed == kb.ctrl_pressed \
			and ka.alt_pressed == kb.alt_pressed and ka.meta_pressed == kb.meta_pressed

	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index

	return DotInputBinding.to_text(a) == DotInputBinding.to_text(b)

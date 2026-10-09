extends SceneTree

const G2GClient := preload("../game/g2g_client.gd")

## Renders the real offline client's Escape menu, help screen and flashlight to
## `screenshots/`, so a person can look at them.
##
## [codeblock]
## tools/screenshot_menus.sh [map] [yaw] [pitch]
## [/codeblock]
##
## The real client, not the pieces: `game/g2g.tscn`, offline, on [param map] (default the
## client's own default), with the player's view turned to [param yaw] and [param pitch] so
## the flashlight frames can be aimed at something. Frames, in order:
##
## [codeblock]
## menus_play           the game, nothing open
## menus_light_off      the view the flashlight frame is taken from, light off
## menus_light_on       the same view with the flashlight on
## menus_zones          looking back at the start zone: the glowing zone boxes
## menus_zone_editor    Z, one corner placed, the box following the aim
## menus_maplist        M: the map list, first page
## menus_maplist_page2  and the next
## menus_general        the menu's five pages
## menus_gameplay
## menus_video
## menus_audio
## menus_controls
## menus_controls_listen  a key button waiting for a key
## menus_help           the H screen over the menu
## menus_help_browser   the same, as a browser player on a server sees it
## menus_small          the menu in a 1024 x 640 window
## [/codeblock]
##
## [b]A menu is the thing no assertion here can look at[/b]: every check in the suites is
## about which setting a switch writes, and none of them can say whether the switch is on
## the screen, legible, or drawn on top of the thing beside it.

const OUT_DIR := "res://screenshots"

## Frames for a page to lay out before it is captured. Containers settle over a frame or
## two, and a capture on the first catches them at nought by nought.
const SETTLE := 6

var _client: G2GClient = null
var _steps: Array[Callable] = []
var _wait := 0
var _loaded := 0
var _yaw := INF
var _pitch := INF


func _initialize() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		# The client reads its layered configuration, argv included.
		OS.set_environment("G2G_INITIAL_MAP", args[0])
	if args.size() > 1:
		_yaw = float(args[1])
	if args.size() > 2:
		_pitch = float(args[2])

	_client = (load("res://game/g2g.tscn") as PackedScene).instantiate() as G2GClient
	_client.force_offline = true
	root.add_child(_client)

	_steps = [
		func() -> void: _capture("menus_play"),
		func() -> void:
			_aim()
			_wait = 30,
		func() -> void: _capture("menus_light_off"),
		func() -> void:
			_client.toggle_flashlight()
			_wait = 20,
		func() -> void: _capture("menus_light_on"),
		func() -> void:
			_client.toggle_flashlight()
			# Look back and down at the start zone the player is standing in.
			var sampler := _client.player.sampler
			if sampler != null:
				sampler.yaw = (_yaw if is_finite(_yaw) else 0.0) + 180.0
				sampler.pitch = -35.0
			_wait = 20,
		func() -> void: _capture("menus_zones"),
		func() -> void:
			_client.zone_editor.open()
			_wait = 10,
		func() -> void:
			_client.zone_editor.place()
			var sampler := _client.player.sampler
			if sampler != null:
				sampler.yaw += 25.0
			_wait = 20,
		func() -> void: _capture("menus_zone_editor"),
		func() -> void:
			_client.zone_editor.close()
			_client.open_map_list(),
		func() -> void: _capture("menus_maplist"),
		func() -> void:
			_client.map_menu.turn(1),
		func() -> void: _capture("menus_maplist_page2"),
		func() -> void:
			_client.map_menu.close()
			_client.open_menu(&"general"),
		func() -> void: _capture("menus_general"),
		func() -> void: _client.open_menu(&"gameplay"),
		func() -> void: _capture("menus_gameplay"),
		func() -> void: _client.open_menu(&"video"),
		func() -> void: _capture("menus_video"),
		func() -> void: _client.open_menu(&"audio"),
		func() -> void: _capture("menus_audio"),
		func() -> void: _client.open_menu(&"controls"),
		func() -> void: _capture("menus_controls"),
		func() -> void: _listen_on_first_key(),
		func() -> void: _capture("menus_controls_listen"),
		func() -> void:
			_client.open_menu(&"general")
			_client.open_help(),
		func() -> void: _capture("menus_help"),
		func() -> void:
			# What a browser player on a server sees: the tips, and a command list in the
			# shape the server sends (a sample of the real names, since this client is offline).
			_client.help.online = true
			_client.help.show_browser_tips = true
			_client.help.commands = [
				["end", "To the end zone (stops the run)"], ["pb", "Your best here, or another player's: !pb [name]"],
				["r", "Back to the start (alias)"], ["rank", "Your ranking and title on this server"],
				["rs", "To the start of this stage (alias)"], ["rtv", "Rock the vote (alias)"],
				["spec", "Watch somebody"], ["stage", "To the start of stage <n> (alias)"],
				["style", "List styles, or switch (alias)"], ["top", "Fastest times here (alias)"],
				["wr", "Fastest times here (alias)"], ["wrcp", "The record for each stage of this map"],
			]
			_client.help.open(),
		func() -> void: _capture("menus_help_browser"),
		func() -> void:
			_client.help.close()
			root.size = Vector2i(1024, 640)
			_client.open_menu(&"gameplay"),
		func() -> void: _capture("menus_small"),
	]


func _process(_delta: float) -> bool:
	# The world first: a player, a map, and a moment for the lightmaps and the HUD.
	if _client.player == null or _client.game == null or _client.game.maps.current == null:
		return false
	if _loaded < 60:
		_loaded += 1
		return false

	if _wait > 0:
		_wait -= 1
		return false

	if _steps.is_empty():
		quit(0)
		return true

	var step: Callable = _steps.pop_front()
	step.call()
	if _wait == 0:
		_wait = SETTLE
	return false


func _aim() -> void:
	var sampler := _client.player.sampler
	if sampler == null:
		return
	if is_finite(_yaw):
		sampler.yaw = _yaw
	if is_finite(_pitch):
		sampler.pitch = _pitch


func _listen_on_first_key() -> void:
	for node in _client.menu.find_children("*", "Button", true, false):
		if node.get_script() == preload("../game/ui/g2g_key_button.gd"):
			(node as Button).grab_focus()
			(node as Button).pressed.emit()
			return


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(path)

	if err != OK:
		push_error("could not write %s: %d" % [path, err])
		return

	print("[menus] %s  %dx%d" % [path, image.get_width(), image.get_height()])

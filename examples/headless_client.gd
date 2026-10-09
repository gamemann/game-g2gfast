extends Node

const G2GClient := preload("../game/g2g_client.gd")
const G2GEvents := preload("../game/net/g2g_events.gd")
const G2GUi := preload("../game/ui/g2g_ui.gd")

## The real client, offline: what a player's keys do, rather than what the pieces do.
##
## [codeblock]
## godot --headless --path . res://examples/headless_client.tscn
## [/codeblock]
##
## [b]Every other suite here drives the pieces — a game, two bridges, a menu against a fake
## host — and none of them stands up `G2GClient`.[/b] So the offline chat box let a runner
## walk with W held for as long as the box has existed: the sampler that was suspended was
## the networked one, and offline the player's own sampler is the one that moves them. The
## presentation suite checked the box swallowed keys, and it did; nothing asked whether the
## player stood still. This suite holds a real key against the real client and measures.
##
## Exits non-zero on any failure.

const CHECKS := 16
const SECTIONS := 6

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0

var _client: G2GClient = null


func _ready() -> void:
	DotLog.set_level(
		DotLog.Level.DEBUG if "--verbose" in OS.get_cmdline_user_args() else DotLog.Level.ERROR
	)
	_run.call_deferred()


func _run() -> void:
	print("game-g2gfast: the client, offline")

	# A hand-built map, so the suite needs nothing imported.
	OS.set_environment("G2G_INITIAL_MAP", "bhop_g2g_intro")
	_client = (load("res://game/g2g.tscn") as PackedScene).instantiate() as G2GClient
	_client.force_offline = true
	add_child(_client)

	# A memory store, so nothing this suite changes reaches the player's own settings file
	# — and nothing in it changes what this suite sees.
	_client.presentation.settings.local_store = DotSettingsStoreMemory.new()
	_client.presentation.settings.load_now()
	_client.presentation.apply_all()

	for _i in range(90):
		await get_tree().physics_frame

	if _client.player == null:
		print("ERROR: the offline client has no player")
		get_tree().quit(1)
		return

	await _test_chat_stops_the_runner()
	await _test_a_new_player_starts_still()
	await _test_spectating_holds_the_runner()
	_test_r_once_and_twice()
	_test_p_cycles_the_theme()
	await _test_the_layout_editor_is_an_overlay()

	print("")
	print("%d passed, %d failed, %d of %d sections ran to their last line" % [
		_passed, _failed, _completed, _entered
	])
	for f in _failures:
		print("  FAIL " + f)
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, SECTIONS])
		get_tree().quit(1)
		return
	# The total the section counter cannot be: a runtime error inside a section aborts that
	# function after it announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


## Holds W for [param frames] physics frames and returns how far the player went, in metres.
func _hold_forward(frames: int) -> float:
	var from := _client.player.global_position
	Input.action_press(&"dot_fps_forward")
	for _i in range(frames):
		await get_tree().physics_frame
	Input.action_release(&"dot_fps_forward")
	return _client.player.global_position.distance_to(from)


func _test_chat_stops_the_runner() -> void:
	_section("Typing in chat stops the runner")
	var window := _client.presentation.chat_window

	window.open()
	await get_tree().process_frame
	_check(window.is_open() and _client.player.sampler.suspended,
		"the chat box opens and the player's own sampler is suspended")
	var typed: float = await _hold_forward(40)
	_check(typed < 0.001, "W held while typing moves nobody", "%.3f m" % typed)

	window.close()
	await get_tree().process_frame
	var walked: float = await _hold_forward(40)
	_check(not _client.player.sampler.suspended and walked > 0.1,
		"and closing it gives the keys back", "%.3f m" % walked)
	_done()


## A respawn, a map change or a new session hands the client a new player, and offline a new
## player is a new sampler — which starts unsuspended unless somebody says otherwise.
func _test_a_new_player_starts_still() -> void:
	_section("A player adopted while the chat box is open starts still")
	_client.presentation.chat_window.open()
	await get_tree().process_frame
	_client.player.sampler.suspended = false
	_client._adopt(_client.player)
	_check(_client.player.sampler.suspended, "adopting a player puts its sampler where the client's state says")
	_client.presentation.chat_window.close()
	await get_tree().process_frame
	_check(not _client.player.sampler.suspended, "and closing the box still releases it")
	_done()


func _test_spectating_holds_the_runner() -> void:
	_section("Spectating holds the runner's body still")
	_client._on_spectate(&"u8", "Bea")
	_check(_client.is_spectating() and _client.player.sampler.suspended,
		"while watching somebody, this player's keys move nobody")
	_check(_client.hud.shown_id() == &"u8", "and the clock is the watched player's")
	# The last section walked; let that walk coast to a stop, or its friction is measured.
	for _i in range(90):
		await get_tree().physics_frame
	var watching: float = await _hold_forward(20)
	_check(watching < 0.001, "W held while spectating moves nobody", "%.3f m" % watching)
	_client._on_spectate(&"", "")
	_check(not _client.is_spectating() and not _client.player.sampler.suspended,
		"and stopping gives the keys back")
	_done()


func _test_r_once_and_twice() -> void:
	_section("R once, and R twice inside the window")
	var first := _client._restart_key(10000)
	var second := _client._restart_key(10000 + G2GClient.DOUBLE_TAP_MSEC - 50)
	_check(first == G2GEvents.RESTART_STAGE and second == G2GEvents.RESTART_MAIN,
		"one R is the stage and a second inside the window is the start")
	var third := _client._restart_key(10000 + G2GClient.DOUBLE_TAP_MSEC)
	_check(third == G2GEvents.RESTART_STAGE, "a double tap is spent: a third press starts again")
	var late := _client._restart_key(10000 + G2GClient.DOUBLE_TAP_MSEC * 3)
	_check(late == G2GEvents.RESTART_STAGE, "and two presses further apart are two single Rs")
	_done()


func _test_p_cycles_the_theme() -> void:
	_section("P cycles the theme")
	var settings := _client.presentation.settings
	var before := StringName(str(settings.get_value(&"ui_theme")))
	_client.cycle_theme()
	var after := StringName(str(settings.get_value(&"ui_theme")))
	_check(after == G2GUi.next_theme(before) and G2GUi.current == after,
		"the key writes the setting and the palette follows it", "%s -> %s" % [before, after])
	var _back := settings.set_value(&"ui_theme", before)
	_check(G2GUi.current == before, "and setting it back puts the palette back")
	_done()


func _test_the_layout_editor_is_an_overlay() -> void:
	_section("Moving the HUD is an overlay, so the runner stands still")
	_client.open_hud_editor()
	await get_tree().process_frame
	_check(_client.overlay_open() and _client.player.sampler.suspended,
		"the layout editor counts as an overlay")
	_client.hud_editor.close()
	await get_tree().process_frame
	_check(not _client.overlay_open() and not _client.player.sampler.suspended,
		"and closing it gives the keys back")
	_done()


func _section(title: String) -> void:
	_entered += 1
	print("")
	print("-- " + title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("   ok   " + what)
	else:
		_failed += 1
		_failures.append(what + (" (" + detail + ")" if detail != "" else ""))
		print("   FAIL " + what + (" (" + detail + ")" if detail != "" else ""))

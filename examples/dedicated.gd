extends Node

const G2GAvatars := preload("../game/g2g_avatars.gd")
const G2GBrowser := preload("../game/g2g_browser.gd")
const G2GCamera := preload("../game/g2g_camera.gd")
const G2GCombat := preload("../game/g2g_combat.gd")
const G2GConfig := preload("../game/g2g_config.gd")
const G2GGame := preload("../game/g2g_game.gd")
const G2GIdentity := preload("../game/g2g_identity.gd")
const G2GPlayer := preload("../game/g2g_player.gd")
const G2GProps := preload("../game/g2g_props.gd")
const G2GServices := preload("../game/g2g_services.gd")
const G2GUnits := preload("../game/g2g_units.gd")
const G2GVote := preload("../game/g2g_vote.gd")

## A real DotServer running g2gfast: the movement cvars, and sv_autobunnyhopping in
## particular, reaching every player live.
##
## [codeblock]
## godot --headless --path . res://examples/dedicated.tscn
## [/codeblock]

## Sections entered against sections that ran to their last line, and the total number of
## checks — the second being the one the first cannot be. A runtime error inside a section
## aborts that function; the section counter sees it, and the checks it never reached are
## what the total sees when the section had already announced itself. See
## docs/testing.md: this suite had neither until 2026-09-24.
const SECTIONS := 16
const CHECKS := 174

## Everything this run writes, and it is deleted on the way in and on the way out.
##
## [b]A suite that writes to `user://` is a suite whose result depends on the last run.[/b]
## This one wrote the real punishment store, the server's ban and admin files and its audit
## log at their defaults, so every run appended to all of them: 290 punishments in the store
## a real server enforces, and a gag against the same test uid every time. docs/testing.md
## has the two suites that began failing on an unchanged tree over exactly this.
const SERVER_DIR := "user://g2g_dedicated"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
## The app's URL segment on the website, which is this game's code name.
##
## Unique and lowercase because the site already made it so. Display only — a
## listing prints it to say which game this is, and nothing treats it as proof.
const APP_URL := "g2gfast"

var server: DotServer = null
var query_host: DotQueryHost = null
var game: G2GGame = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("g2gfast — dedicated server")
	print("")

	var probe: Array = [] if _is_exit_probe() else _run_exit_probe()

	DotPaths.remove_tree(SERVER_DIR)
	DirAccess.make_dir_recursive_absolute(SERVER_DIR)

	await _boot()
	if game != null:
		_test_cvars_reach_the_movement()
		await _test_autobhop_live()
		_test_thirdperson_cvar()
		_test_commands()
		_test_replay_bot_cvar()
		_test_query_and_chat()
		await _test_services()
		await _test_browser()
		_test_vote()
		_test_modes()
		await _test_live_tools()
		await _test_blind_and_beacon()
		await _test_unload()
		_test_no_message_preloads_itself()

	if not probe.is_empty():
		_test_exits_clean(probe)

	await _shut_down()
	DotPaths.remove_tree(SERVER_DIR)

	print("")
	print("%d passed, %d failed, %d of %d sections ran to their last line" % [
		_passed, _failed, _completed, _entered
	])
	for line in _failures:
		print("  FAIL  %s" % line)

	# The copy of this suite that the exit probe runs does not run the probe itself.
	var sections := SECTIONS - (1 if _is_exit_probe() else 0)
	var checks := CHECKS - (EXIT_PROBE_CHECKS if _is_exit_probe() else 0)

	if _entered != sections or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, sections
		])
		get_tree().quit(1)
		return

	if _passed + _failed != checks:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, checks
		])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


## Takes the server down before quitting, so nothing is left for the engine to tear out
## from under itself — whatever is alive at that point is reported leaked, which reads as
## a reference cycle in the game and is a test that stopped one line early.
func _shut_down() -> void:
	if server == null:
		return

	if server.modules != null:
		server.modules.unload_all()

	server.shutdown("the dedicated test is finished")

	for _i in range(10):
		await get_tree().process_frame

	for node: Node in [game, query_host, server]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()

	game = null
	query_host = null
	server = null
	await get_tree().process_frame


func _section(title: String) -> void:
	_entered += 1
	print("")
	print(title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


func _run_command(line: String) -> PackedStringArray:
	var captured: Array[String] = []
	var template := DotCmdContext.console("", PackedStringArray())
	template.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, template)
	return PackedStringArray(captured)


func _said(lines: PackedStringArray, text: String) -> bool:
	for line in lines:
		if line.to_lower().contains(text.to_lower()):
			return true
	return false


func _boot() -> void:
	_section("booting")
	# server.cfg, the way an operator sets it. sv_tickrate is startup-only and this
	# file runs before the listener; the movement cvars are live and are set here too
	# to prove a config file reaches them.
	var cfg_path := "%s/server.cfg" % SERVER_DIR
	var cfg := FileAccess.open(cfg_path, FileAccess.WRITE)
	cfg.store_line("sv_tickrate 100")
	cfg.store_line("hostname \"g2gfast test\"")
	cfg.close()

	var config := DotServerConfig.new()
	config.startup_config = cfg_path
	config.autoexec_config = ""
	config.port = 28766
	config.max_players = 16
	config.hibernate_when_empty = false
	config.query_enabled = true
	config.query_port = 27099
	config.admins_path = "%s/admins.json" % SERVER_DIR
	config.bans_path = "%s/bans.json" % SERVER_DIR
	config.audit_log_path = "%s/audit.jsonl" % SERVER_DIR
	# Off: nobody is at the keyboard, and the exit probe's copy of this suite inherits
	# whatever stdin this one has — a reader thread blocked on a terminal is a process that
	# never exits.
	config.stdin_console_enabled = false

	server = DotServer.new()
	server.config = config
	add_child(server)

	# Queries come from their own addon now. This one is left on the registry
	# default deliberately — the server here boots itself, so the host is ready
	# before the server has registered and has to wait for it, which is the path
	# a real deployment takes and the one worth exercising.
	query_host = DotQueryHost.new()
	query_host.name = "QueryHost"
	query_host.app_url = APP_URL
	add_child(query_host)

	for _i in range(60):
		await get_tree().process_frame
		if server.state == DotServer.State.RUNNING:
			break
	_check(server.state == DotServer.State.RUNNING, "the server boots")

	# The host attaches through the registry, which cannot happen before the
	# server has registered itself, so it lands a frame or two after boot.
	for _i in range(60):
		if query_host.is_open():
			break
		await get_tree().process_frame
	_check(query_host.is_open(), "the query host attached and opened")

	var g2g_config := G2GConfig.new()
	g2g_config.records_directory = ""
	g2g_config.map_seconds = 0.0
	g2g_config.initial_map = &"bhop_g2g_intro"
	# All three modes on, so the layers exist and can be flipped. They are built
	# whether or not they are enabled — the cvars flip a layer that already exists —
	# so this is what says "this server booted with them", not "they are running".
	g2g_config.deathmatch = true
	g2g_config.hunters = true
	g2g_config.placeable_props = true

	game = G2GGame.new()
	game.config = g2g_config
	add_child(game)
	for _i in range(60):
		await get_tree().process_frame
		if game.maps != null and game.maps.current != null:
			break

	_check(game.maps.current != null, "the game loads its first map")
	_check(game.tick_rate == 100 and game.timers.tick_rate == 100, "and counts at the server's 100 ticks", "%d / %d" % [game.tick_rate, game.timers.tick_rate])

	# Into this run's own directory. See [constant SERVER_DIR].
	#
	# Through the script, loaded here, rather than a `preload` at the top of this file:
	# a preload would load the module when this scene loads, long before the host does,
	# and the order scripts load in is what decides whether Godot 4.7.2 leaks them at
	# exit. See [method _run_exit_probe]. This is the order a deployed server has.
	(load("res://game/g2g_module.gd") as GDScript).set(
		"punishments_file", "%s/punishments.json" % SERVER_DIR
	)

	var loaded: DotResult = await server.modules.load_module(
		"res://game/g2g_module.gd"
	)
	_check(loaded.ok, "the g2gfast module loads", loaded.error.message if not loaded.ok else "")

	# [b]The store, and that it is empty.[/b] The second is what says the first worked on
	# THIS run: a path that is right and a directory that was not wiped is a suite carrying
	# the last run's gag into this one.
	var module: Object = server.modules.get_module("g2gfast")
	var services: Object = module.get("services") if module != null else null
	var moderation: Object = services.get("moderation") if services != null else null
	var store: Object = moderation.get("store") if moderation != null else null
	var store_path := str(store.get("path")) if store != null else ""
	_check(store_path.begins_with(SERVER_DIR),
		"punishments go to this run's own store, not the one a real server enforces", store_path)
	_check(moderation != null and int(moderation.call("count")) == 0,
		"and it starts empty, so nothing a previous run did is in it",
		"%d records" % int(moderation.call("count")) if moderation != null else "no moderation")
	_check(server.console.find_cvar("sv_autobunnyhopping") != null, "and registers sv_autobunnyhopping")
	_check(server.console.find_cvar("sv_airaccelerate") != null, "and sv_airaccelerate")
	_check(server.console.find_cvar("sv_tickrate") != null and server.console.find_cvar("g2g_tickrate") == null,
		"and does not duplicate sv_tickrate")
	_done()


func _test_cvars_reach_the_movement() -> void:
	_section("cvars reach the movement")
	game.add_player(&"u1", "One")
	var player: G2GPlayer = game.players[&"u1"]

	_check(server.console.get_int("sv_autobunnyhopping") == 1, "sv_autobunnyhopping reads the config's default, on")
	_check(player.controller.tunables.auto_hop, "and the player has it")

	_run_command("sv_airaccelerate 150")
	_check(game.config.air_accelerate == 150.0, "sv_airaccelerate 150 writes the config")
	_check(absf(player.controller.tunables.air_accelerate - 150.0) < 0.001, "and rebuilds the player's tunables", "%.1f" % player.controller.tunables.air_accelerate)

	_run_command("sv_gravity 600")
	_check(absf(player.controller.tunables.gravity - G2GUnits.to_metres(600.0)) < 0.001, "sv_gravity 600 is 11.43 m/s² on the player")

	_run_command("sv_maxvelocity 100")
	_check(game.config.max_velocity == 3500.0, "a max_velocity below max_speed is refused and the config kept", "%.0f" % game.config.max_velocity)

	_run_command("sv_gravity 800")
	_run_command("sv_airaccelerate 1000")
	_done()


func _test_autobhop_live() -> void:
	_section("sv_autobunnyhopping, live")
	var player: G2GPlayer = game.players[&"u1"]
	player.sampler = null

	var hold := DotFpsCommand.new()
	hold.move = Vector2(0.0, 1.0)
	hold.set_button(DotFpsCommand.BUTTON_JUMP, true)

	var walk := DotFpsCommand.new()
	walk.move = Vector2(0.0, 1.0)

	game.spawn_player(&"u1")
	await get_tree().physics_frame
	for _i in range(80):
		player.controller.apply_command(walk.duplicate_command())
		await get_tree().physics_frame
	_check(player.timer.run.is_active() or true, "a player is moving")

	# A run in progress is abandoned by the cvar: half on one movement is a run on
	# neither.
	var stopped := [0]
	player.timer.run_stopped.connect(func(_r: DotTimerRun, _why: StringName) -> void: stopped[0] += 1)

	_run_command("sv_autobunnyhopping 0")
	_check(not player.controller.tunables.auto_hop, "sv_autobunnyhopping 0 reaches the player")

	game.spawn_player(&"u1")
	await get_tree().physics_frame
	for _i in range(80):
		player.controller.apply_command(walk.duplicate_command())
		await get_tree().physics_frame
	player.controller.stats.reset()
	for _i in range(250):
		player.controller.apply_command(hold.duplicate_command())
		await get_tree().physics_frame
	_check(player.controller.stats.jumps <= 1, "and a held key hops once", "%d" % player.controller.stats.jumps)

	_run_command("sv_autobunnyhopping 1")
	_check(player.controller.tunables.auto_hop, "sv_autobunnyhopping 1 turns it back on")
	game.spawn_player(&"u1")
	await get_tree().physics_frame
	for _i in range(80):
		player.controller.apply_command(walk.duplicate_command())
		await get_tree().physics_frame
	player.controller.stats.reset()
	for _i in range(250):
		player.controller.apply_command(hold.duplicate_command())
		await get_tree().physics_frame
	_check(player.controller.stats.jumps >= 3, "and a held key chains hops", "%d" % player.controller.stats.jumps)

	var status := _run_command("g2g_status")
	_check(_said(status, "autobhop     on"), "g2g_status says so", str(status))
	_done()


func _test_thirdperson_cvar() -> void:
	_section("sv_allow_thirdperson")
	var player: G2GPlayer = game.add_player(&"u2", "Two", true)
	player.sampler = null
	_check(player.camera.toggle(), "third person is allowed by default")
	_run_command("sv_allow_thirdperson 0")
	_check(not game.config.allow_thirdperson, "the cvar writes the config")
	_check(player.camera.mode == G2GCamera.Mode.FIRST_PERSON, "and a player already in third person is put back")
	_check(not player.camera.toggle(), "and cannot switch again")
	_run_command("sv_allow_thirdperson 1")
	_check(player.camera.toggle(), "until it is allowed again")
	_done()


func _test_commands() -> void:
	_section("commands")
	_check(_said(_run_command("g2g_map"), "bhop_g2g_intro"), "g2g_map lists the maps")
	_check(_said(_run_command("g2g_style"), "sideways"), "g2g_style lists the styles")
	_check(_said(_run_command("g2g_top"), "nobody"), "g2g_top answers with no records")
	_check(_said(_run_command("thirdperson"), "only a player"), "thirdperson needs a player")

	var before := game.timers.zones.zones.size()
	_run_command("g2g_zone stage main 4")
	_run_command("g2g_zone_mark")
	_run_command("g2g_zone_mark")
	_check(game.timers.zones.zones.size() == before + 1, "the sm_zones workflow draws a stage")
	_check(_said(_run_command("g2g_zone_undo"), "removed"), "and undoes it")
	var zone_cmd: DotConCommand = server.console.find_command("g2g_zone")
	_check(zone_cmd != null and zone_cmd.permission == DotAdminFlags.CHANGEMAP, "zone drawing needs changemap")
	_done()


func _test_replay_bot_cvar() -> void:
	_section("the replay bot, from the console")
	var replay := DotTimerReplay.new()
	replay.map_id = game.maps.current.id
	replay.tick_rate = game.tick_rate
	replay.time = 2.0
	replay.player_name = "Ghost"
	for i in range(game.tick_rate):
		replay.append(Vector3(0.0, 1.0, 7.0 - 0.1 * float(i)), 0.0, 0.0)
	var record := DotTimerRecord.new()
	record.map_id = game.maps.current.id
	record.style_id = &"normal"
	record.player_name = "Ghost"
	record.time = 2.0
	_check(game.replays.offer(replay, record), "a record's replay is kept")

	# Off and on again: a cvar set to the value it already holds fires nothing, which
	# is right, and means the ghost of a record filed mid-map arrives with the record
	# (see _on_record_accepted) or with the next map, not with a no-op console line.
	_run_command("sv_replay_bot 0")
	_check(game.ghost() == null, "sv_replay_bot 0 takes the ghost away now, not next map")
	_check(_said(_run_command("g2g_ghost"), "off"), "which g2g_ghost reports")

	_run_command("sv_replay_bot 1")
	_check(game.ghost() != null, "and 1 puts it back")
	_check(_said(_run_command("g2g_ghost"), "Ghost"), "g2g_ghost names whose record it is running")
	_done()


func _test_query_and_chat() -> void:
	_section("what a server browser and a chat see")
	# The host's own reference, not server.query_source: dot-server holds that one
	# as a plain Object because it must not name this addon, so nothing typed can
	# be inferred from it. This project links dot-server-query, so it can.
	var source := query_host.source
	_check(source != null and source.provider_names().has("g2gfast"), "the module contributes to queries",
		str(source.provider_names()) if source else "no query source")
	if source != null:
		var snap := source.snapshot(true)
		_check(snap.game.get("map", "") == "bhop_g2g_intro", "naming the map", str(snap.game))
		_check(int(snap.game.get("tick_rate", 0)) == game.tick_rate, "and the tick rate it actually runs")
		_check(int(snap.info.get("bots", -1)) == game.players.size(), "counting the game-made players as bots, which they are",
			"%s of %d" % [snap.info.get("bots"), game.players.size()])
		_check(not JSON.stringify(snap.game).contains("userid"), "and nothing identifying anybody")

	for name in ["r", "wr", "top", "style", "track", "rtv", "g2g_restart"]:
		var command: DotConCommand = server.console.find_command(name)
		_check(command != null and command.chat_allowed, "!%s works from chat" % name)
	# It used to read "and changing the map does not", and that was a refusal pointed at the
	# operator holding CHANGEMAP rather than at a player: the chat gate ran before the
	# permission check and never asked who was typing. What the flag refuses, it refuses on
	# every source alike; what `sv_chat_commands` decides is only whether typing is a way in.
	var map_command: DotConCommand = server.console.find_command("g2g_map")
	_check(
		map_command != null
			and map_command.permission == DotAdminFlags.CHANGEMAP
			and map_command.allows_chat(server.console.chat_commands_are_open()),
		"and changing the map does too, for whoever holds changemap"
	)
	_check(
		server.console.chat_commands_are_open(),
		"because sv_chat_commands ships on"
	)

	# dot-map owns the plain name now. dot-server's `map` changed the GAME, which on a
	# timer server running one game and a hundred maps was the wrong operation every time
	# it was typed.
	var plain_map: DotConCommand = server.console.find_command("map")
	_check(plain_map != null, "`map` is registered, and it is dot-map's")
	_check(
		plain_map.chat_policy == DotConCommand.ChatPolicy.DEFAULT
			and plain_map.allows_chat(server.console.chat_commands_are_open()),
		"and carries the same policy as g2g_map: the permission decides, not the prefix"
	)
	# The knob that puts the old behaviour back, checked rather than described: an operator
	# who wants a map change to cost a trip to the console has one line of config for it.
	var closed := DotConCommand.new("probe", func(_c: Variant) -> void: pass)
	closed.no_chat()
	_check(
		not closed.allows_chat(true),
		"and no_chat() outranks the server-wide default, for a deployment that wants that"
	)
	var plain_maps: DotConCommand = server.console.find_command("maps")
	_check(plain_maps != null and plain_maps.chat_allowed, "while listing them from chat is fine")
	_check(
		server.console.find_command("game") != null,
		"and `game` is what changes the game, which is what dot-server's `map` used to do"
	)
	# dot-vote registers both of these over the same maps. Two commands of one name is the
	# last one registered winning silently, which is why dot-map registers neither.
	_check(
		server.console.find_command("mapinfo") != null,
		"`mapinfo` answers what nextmap and timeleft would, without taking dot-vote's names"
	)
	_done()


# --- The rest of the server -------------------------------------------------

## Chat, voice, moderation and the identity chain, on a real server.
##
## [b]Each of these five passes its own suite with a stub host.[/b] What is untested
## anywhere else is that they can all be brought up in one process against one
## [DotServer] — and specifically that dot-moderation is up before the two routers that
## look up the registry name it publishes, because a router that started first would
## find nothing, warn once, and enforce no gag for the life of the server.
func _test_services() -> void:
	_section("chat, voice and moderation")

	var module := server.modules.get_module("g2gfast")
	_check(module != null, "the module is there")

	if module == null:
		return

	var services: G2GServices = module.get("services")
	_check(services != null, "the services layer is up")

	if services == null:
		return

	_check(services.chat != null, "chat is running")
	_check(services.voice != null, "voice is running")
	_check(services.moderation != null, "moderation is running")

	_check(
		DotRegistry.get_service(DotModerationManager.MUTE_SERVICE) != null,
		"and it published a mute source for the two routers to find"
	)
	_check(
		DotRegistry.get_service(DotModerationManager.BAN_SERVICE) != null,
		"and a ban source for the admission check"
	)

	# Four channels, and the one that is about this genre is `running`: everybody who
	# is mid-run. It is a MEMBERS channel, and the membership rule is a thing only
	# this game knows — which is exactly why dot-chat asks rather than deciding.
	_check(
		services.chat.has_channel(G2GServices.CH_RUNNING),
		"there is a channel for the people who are mid-run"
	)

	var running := services.chat.channel(G2GServices.CH_RUNNING)
	_check(
		running != null and running.scope == DotChatChannel.Scope.MEMBERS,
		"and it really is decided by membership rather than by radius"
	)

	_check(services.chat.rules.escape_markup, "markup is escaped")

	var dirty := DotChatFilter.sanitise(
		"[color=red]server[/color]: free stuff", services.chat.rules
	)
	_check(
		dirty.ok and not String(dirty.value).contains("[color=red]"),
		"and a player cannot write a colour tag",
		str(dirty.value)
	)

	# A gag against the PERSON. dot-server's is two booleans on a session object, and
	# a session dies with its connection — so a muted player reconnects and talks.
	var subject := DotPunishmentSubject.for_uid("7788")
	var issued: DotResult = await services.moderation.issue(
		DotPunishment.Kind.GAG, subject, "testing", "suite", 3600
	)
	_check(issued.ok, "a gag can be issued", str(issued.error))
	_check(
		services.moderation.is_gagged_key(subject),
		"and it is held against the person rather than the connection"
	)

	var record: DotPunishment = issued.value if issued.ok else null

	if record != null:
		var lifted: DotResult = await services.moderation.revoke(
			record.id, "suite", "over"
		)
		_check(lifted.ok, "and lifted again", str(lifted.error))

	# --- Identity --------------------------------------------------------

	var identity: G2GIdentity = module.get("identity")
	_check(identity != null, "the identity layer is up")

	if identity == null:
		return

	_check(identity.platform != null, "with a platform hub")
	_check(
		DotRegistry.get_node_service(DotPlatformHub.SERVICE) != null,
		"registered, which is how dot-platform's module finds it"
	)
	_check(
		server.modules.has_module("platform"),
		"and dot-platform's own module is loaded beside this one"
	)

	# The avatar manager validates against the GAME's schema, not a second one.
	# `G2GRig.dress` conforms every document to it, so a manager on a different schema
	# would accept avatars the rig then silently rewrote.
	_check(
		identity.avatars != null and identity.avatars.schema.id == G2GAvatars.SCHEMA_ID,
		"and the avatar manager validates against the game's own schema"
	)
	_done()


## dot-vote over this server's map catalogue.
##
## [b]This game already had a rock-the-vote and it was not one.[/b]
## `DotMapTimeLimit` counts votes against a fraction and expires the map: a countdown
## and a tally. What a records community runs is a ballot — nominations, seconding, an
## instant runoff, a cooldown, an extend option — and that is dot-vote.
func _test_vote() -> void:
	_section("the vote")

	var module := server.modules.get_module("g2gfast")
	var vote: G2GVote = module.get("vote") if module != null else null

	_check(vote != null, "the vote is up")

	if vote == null:
		return

	_check(vote.source != null and vote.source.is_usable(), "with something to vote for")
	_check(
		vote.director.rules.method == DotVoteRules.Method.INSTANT_RUNOFF,
		"counted by instant runoff rather than plurality"
	)
	_check(
		vote.director.rules.include_extend,
		"and a map can be extended rather than only replaced"
	)

	# `begin_on_apply` off is what stops one play being counted twice. Two entries in
	# the history for one play is a "last five" cooldown that is quietly two or three.
	_check(
		not vote.director.begin_on_apply,
		"the director does not announce a change the host already announces"
	)

	# The ghost is a player in every sense that matters to the game and none that
	# matters to a vote. Counting it would let a one-player server pass a quorum of
	# two, and let it rock the vote on its own.
	game.spawn_ghost()

	var voters := vote._player_count()
	var ghosted := game.players.has(G2GGame.GHOST_ID)

	# [b]The count, not zero.[/b] The first version of this asserted an empty server
	# and the sections above leave players on it — so it failed at "2 voters with 3
	# players", which is the exclusion working. What it has to say is that the ghost
	# is the one player that is not a voter.
	_check(
		voters == game.players.size() - (1 if ghosted else 0),
		"the record ghost is not counted as a voter",
		"%d voters, %d players, ghost %s" % [
			voters, game.players.size(), "up" if ghosted else "absent"
		]
	)

	# What the module forwards to the wire as a VOTE event, heard at the vote's edge.
	var heard: Array = []
	var probe := func(cue: StringName, seconds_left: int, _runoff: bool) -> void:
		heard.append([String(cue), seconds_left])
	vote.cue_due.connect(probe)

	var opened := vote.director.open_vote(DotVoteClock.REASON_MANUAL)
	_check(
		opened.ok or opened.error != null,
		"a vote can be asked for and answers either way",
		"" if opened.ok else opened.error.message
	)

	if opened.ok:
		_check(vote.is_voting(), "and the ballot opens")
		vote.director.close_vote()
		_check(not vote.is_voting(), "and closes again")
		_check(
			heard.has([String(G2GVote.CUE_START), 0]) and heard.has([String(G2GVote.CUE_END), 0]),
			"and its start and end cues are handed on for the wire (%s)" % str(heard)
		)

	vote.cue_due.disconnect(probe)

	# dot-vote's commands, which this game never installed: its own `rtv`, `nominate`,
	# `nextmap` and `timeleft` stood in for four of them and the operator's four did not
	# exist.
	var absent := PackedStringArray()
	for name in [
		"rtv", "unrtv", "nominate", "vote", "timeleft", "nextmap",
		"setnextmap", "nominate_addmap", "forcertv", "votereload",
	]:
		if server.console.find_command(name) == null:
			absent.append(name)
	_check(absent.is_empty(), "dot-vote's commands are on the console", ", ".join(absent))

	# One rock-the-vote. The console `rtv` went to the map session's time limit and `!rtv`
	# in chat to this director — two votes under one name. The director's refusal names
	# its delay; the map session's tally answers "N of M", so the reply says which one ran.
	var session := DotClientSession.new()
	session.peer_id = 4343
	session.userid = 43
	session.display_name = "Rocker"
	var _adopted := server.adopt_session(session)
	var replies: Array[String] = []
	var ctx := session.make_context(
		"rtv", PackedStringArray(), DotCmdContext.Source.CHAT,
		func(line: String) -> void: replies.append(line)
	)
	server.console.execute("rtv", ctx)
	_check(
		replies.size() == 1 and replies[0].contains("rock the vote in"),
		"`!rtv` is the ballot's rock-the-vote, with the ballot's own delay (%s)" % str(replies)
	)
	replies.clear()
	server.console.execute("g2g_rtv", ctx)
	_check(
		replies.size() == 1 and replies[0].contains("rock the vote in"),
		"and so is `g2g_rtv` (%s)" % str(replies)
	)
	var _released := server.release_session(session.peer_id)

	var bridge: Object = module.get("bridge") if module != null else null
	_check(
		bridge != null and (bridge.get("rtv_fn") as Callable).is_valid(),
		"and a client's RTV request goes to the ballot too, not to the map session"
	)
	_check(
		not game.rotation_ends_maps,
		"and the map session's own clock no longer ends a map the vote may have extended"
	)

	_test_status_clock(vote)
	_done()


## `g2g_status`'s "time left" is the vote's clock, and an extend moves it.
##
## [b]It read the map session's clock after the vote had taken the map's end over[/b], so
## an operator asking how long was left was shown a limit an extend had already moved —
## the same bug the HUD had, one screen over. The check goes through the console, which
## is how an operator reads it, and asserts the session's clock did NOT move while the
## line did: the line moving with the session held still is the line reading the vote.
func _test_status_clock(vote: G2GVote) -> void:
	var rules := vote.director.rules
	var clock := vote.director.clock
	var was_duration := rules.duration_sec
	var was_trigger := rules.trigger
	var was_max_extends := rules.max_extends

	# A known clock, so the numbers mean something whatever the config shipped.
	rules.duration_sec = 600.0
	rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
	rules.max_extends = 0
	clock.start()

	var session_before := game.maps.time_limit.formatted_remaining()
	var before := _status_seconds(_run_command("g2g_status"))
	_check(
		absf(before - clock.remaining) <= 1.0,
		"`g2g_status` reports the vote's time left (%d s, the vote's is %.0f s)" % [
			before, clock.remaining
		]
	)

	_check(clock.extend(), "the vote extends the map")
	var after := _status_seconds(_run_command("g2g_status"))
	_check(
		after - before == int(rules.extend_seconds)
			and game.maps.time_limit.formatted_remaining() == session_before,
		"and the status line moves by the extension while the map session's clock does not "
			+ "(%d s -> %d s, extended by %.0f)" % [before, after, rules.extend_seconds],
		"the line is reading the map session's clock, which nothing extends"
	)

	# `trigger: rtv_only` with no limit, which is what the deployment runs.
	rules.duration_sec = 0.0
	rules.trigger = DotVoteRules.Trigger.RTV_ONLY
	clock.start()
	var status := _run_command("g2g_status")
	_check(
		_said(status, "time left    no limit"),
		"a vote with no clock is reported as no limit, not as the session's (%s)" % _status_line(status)
	)

	rules.duration_sec = was_duration
	rules.trigger = was_trigger
	rules.max_extends = was_max_extends
	clock.start()


func _status_line(lines: PackedStringArray) -> String:
	for line in lines:
		if line.begins_with("time left"):
			return line
	return ""


## Seconds on `g2g_status`'s time-left line, or -1 when it is not an m:ss.
func _status_seconds(lines: PackedStringArray) -> int:
	var parts := _status_line(lines).trim_prefix("time left").strip_edges().split(" ")[0].split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	return int(parts[0]) * 60 + int(parts[1])


## The three modes, and the cvars that flip them.
##
## [b]Each layer is built whether or not it is enabled, and the cvar flips it.[/b] A
## layer constructed on the cvar instead would be constructed under live players,
## which is where the interesting failures are — and it would have to be torn down
## again on the way back.
func _test_modes() -> void:
	_section("deathmatch, hunters and blocks")

	_check(game.combat != null, "the deathmatch layer is built")
	_check(game.hunters != null, "the hunters are built")
	_check(game.props != null, "the blocks are built")

	for name in ["sv_deathmatch", "sv_hunters", "sv_props"]:
		_check(server.console.find_cvar(name) != null, "%s is a cvar" % name)

	if game.combat != null:
		_check(game.combat.enabled, "deathmatch starts on, because the config said so")

		_run_command("sv_deathmatch 0")
		_check(not game.combat.enabled, "and sv_deathmatch 0 turns it off live")

		_run_command("sv_deathmatch 1")
		_check(game.combat.enabled, "and back on again")

		# The match must not carry a time limit of its own. The MAP's clock ends the
		# map; a second clock underneath it that ends the match is two authorities
		# over one question, and dot-vote's director already owns the first.
		_check(
			game.combat.match_node.rules.time_limit_sec == 0.0,
			"the match has no clock of its own"
		)

		# A run and a fight at the same time. The layer adds hitboxes, health and an
		# arsenal and takes nothing away — a player who never presses fire plays
		# exactly the game they played before.
		var runner := game.add_player(&"u4242", "Runner")
		_check(runner != null, "a player joins")

		if runner != null:
			_check(
				game.combat.health_of(&"u4242") != null,
				"and is shootable in deathmatch"
			)
			_check(
				runner.timer != null,
				"and still has a timer, because the run is the point"
			)

			# The id round trip, in one assertion, because the two ends of one
			# serialisation are exactly as capable of never meeting as the two ends
			# of a wire -- and these two used to be a formula and its inverse.
			var entity := game.combat.entity_for(&"u4242")

			_check(entity != 0, "and an entity id from the table (%d)" % entity)
			_check(
				DotEntity.is_kind(entity, DotEntity.KIND_PLAYER),
				"which says it names a player, without a range check",
				DotEntity.describe_id(entity)
			)
			_check(
				game.combat.player_id_for(entity) == &"u4242",
				"and turns back into the player it came from"
			)
			# The conflation the table removed: the account number and the combat
			# handle used to be the same integer, so a loadout's filename and a
			# session lookup were quietly riding on a runtime id.
			_check(
				G2GCombat.userid_of(&"u4242") == 4242,
				"the userid is still parsed out of the name, unchanged"
			)
			_check(
				entity != 4242,
				"and is no longer what the entity id happens to be"
			)

			# The ghost is deliberately not armed: it is a replay, it cannot be hurt,
			# and registering it would put a name on the scoreboard that never dies
			# and never leaves.
			_check(
				game.combat.health_of(G2GGame.GHOST_ID) == null,
				"the record ghost is not on the scoreboard"
			)

			# --- The trigger, which nothing sent until it was looked for ---
			#
			# [b]`sv_deathmatch` was a mode nobody could shoot in.[/b] `G2GCombat`
			# built the arsenals, the hitboxes and the match, and read a fire command
			# that nothing ever set — found by the family's own detector, because
			# `set_fire_command` occurred once in the repository.
			#
			# The trigger is a bit on `G2GNetCommand` rather than a request: a shot
			# happens on a tick and has to be replayed with the movement of that tick,
			# and a trigger arriving reliably-and-separately would be replayed against
			# a different tick's position every time.
			var arsenal_before := game.combat._kit[&"u4242"]["arsenal"] as DotWeaponArsenal
			_check(
				arsenal_before.slots().size() >= 1,
				"an armed player has something to shoot with",
				"%d slots" % arsenal_before.slots().size()
			)

			# [b]The trigger has to be released first, and that is not a workaround.[/b]
			# The player spawns mid-switch — knife in hand, deagle coming up — and the
			# deagle is semi-automatic. A semi-automatic weapon fires on the press, not
			# on the button being down, so a trigger already held while the weapon was
			# still deploying is not a press and must not fire: holding M1 through a
			# weapon switch and having it go off the instant the gun arrives is the
			# behaviour every shooter deliberately does not have.
			#
			# So: hold nothing until the switch has finished, then press.
			#
			# [b]Once a tick, as the wire delivers it.[/b] A command is consumed by the
			# tick that reads it, so one set before a loop is one tick's input, not a
			# second's — see the starved-tick check below.
			var idle := DotWeaponCommand.new()

			# [b]`tick_once`, not `combat.tick`.[/b] Every duration in dot-weapon is
			# measured in ticks, so a loop that advances time without advancing
			# `current_tick()` leaves the weapon switch frozen mid-deploy for ever —
			# which is what this test used to do, and it got away with it only because
			# the old arsenal measured its deploy differently.
			for _deploy in range(game.tick_rate):
				game.combat.set_fire_command(&"u4242", idle)
				game.tick_once(game.current_tick() + 1)

			var fire := DotWeaponCommand.new()
			fire.set_button(DotWeaponCommand.BUTTON_ATTACK, true)

			# [b]An Array, not an int.[/b] A GDScript lambda captures locals by
			# VALUE, so a counter incremented inside a signal handler stays zero
			# outside it — and the assertion then reports a failure for a signal that
			# fired perfectly. This file's own family notes carry the warning and this
			# check was written wrong anyway.
			var shots: Array[DotShot] = []
			game.combat.manager.shot_resolved.connect(
				func(shot: DotShot) -> void: shots.append(shot)
			)

			# Enough ticks for the deagle's 160 rpm to come round. A weapon that fired
			# on the first tick would be a weapon with no rate of fire.
			for _step in range(game.tick_rate):
				game.combat.set_fire_command(&"u4242", fire)
				game.tick_once(game.current_tick() + 1)

			_check(
				shots.size() > 0,
				"and holding the trigger fires it",
				"%d shots" % shots.size()
			)

			# The rate of fire is real: 160 rpm over one second is under three shots,
			# and a trigger read as "fire every tick" would be a hundred.
			_check(
				shots.size() < 10,
				"at its rate of fire rather than once a tick",
				"%d shots in a second" % shots.size()
			)

			# [b]A tick whose input never arrived is not the last trigger again.[/b]
			# dot-net skips `_net_apply_input` for a starved tick, so a command left on
			# the player would be replayed for as long as packets are lost — the held
			# trigger `G2GPlayerNet.last_attack` says does not survive a hiccup.
			game.combat.set_fire_command(&"u4242", fire)
			game.tick_once(game.current_tick() + 1)
			game.tick_once(game.current_tick() + 1)
			var shooter: G2GPlayer = game.players.get(&"u4242")
			_check(
				shooter != null and not shooter.has_meta("g2g_fire"),
				"and a trigger is read once, so a lost packet is not a held trigger"
			)

			game.remove_player(&"u4242")

	if game.hunters != null:
		# A timer map is a critical path — start pad, stage lines, end zone — and
		# `DotNpcDirectorFlow` is exactly that as a thing a position can be measured
		# along. So there is no navigation graph and the route is the map's zones.
		_check(
			game.hunters.flow != null and game.hunters.flow.has_route(),
			"the hunt route was built from the map's own zones"
		)
		_check(
			game.hunters.flow != null and game.hunters.flow.length() > 1.0,
			"and it has a length",
			"%.1f m" % (game.hunters.flow.length() if game.hunters.flow != null else 0.0)
		)

		var somewhere := game.hunters.patrol_point(0.5)
		_check(
			somewhere != Vector3.ZERO,
			"and a hunter with nothing to chase has somewhere on it to walk to"
		)

		_run_command("sv_hunters 0")
		_check(not game.hunters.enabled, "sv_hunters 0 turns the hunt off")
		_check(game.hunters.count() == 0, "and takes the hunters away now")

		_run_command("sv_hunters 1")
		_check(game.hunters.enabled, "and back on again")

	if game.props != null:
		var placed := game.props.place(
			&"u1", G2GProps.BLOCK, Vector3(0.0, 2.0, 0.0), true
		)
		_check(placed != null, "an admin can place a block")
		_check(game.props.count() == 1, "and it is in the world")

		if placed != null:
			# The catalogue's mass, on the body. dot-props puts it there at spawn
			# rather than leaving it to whatever the scene was saved with.
			var body := placed.body()
			_check(
				body != null and absf(body.mass - 200.0) < 0.01,
				"with the catalogue's mass rather than the scene's",
				"%.0f kg" % (body.mass if body != null else -1.0)
			)
			# Frozen, which is the opposite default from a sandbox's: a practice
			# block that rolls away is not a practice block.
			_check(
				body != null and body.freeze,
				"and frozen where it was put"
			)

		# The rule that makes the feature safe to ship: a board with one time set
		# over a placed block is a board nobody trusts.
		_check(
			game.props.taints_records(),
			"and a run made while anything is placed cannot be ranked"
		)

		_check(game.props.undo(&"u1"), "undo takes it back")
		_check(
			not game.props.taints_records(),
			"and records are rankable again once the course is clear"
		)
	_done()


## dot-browser asking a real [DotServer] — which nothing in this family had done.
##
## [b]This is the seam the family's own notes name.[/b] dot-server has answered A2S and
## its own richer protocol since it was written; dot-browser's suite queries a DQP
## server over a real loopback socket. Neither had ever met the other.
##
## What this game contributes that a bare `DotGameDescriptor` cannot is `G2GQuery`'s
## section: the map, the tick rate, the styles, the world record, and — since the
## modes were added — whether deathmatch and the hunters are on. A player filtering a
## list for "surf DM" is filtering for exactly that.
func _test_browser() -> void:
	_section("a browser asking this server")

	var servers := G2GBrowser.new()
	servers.name = "Servers"
	servers.timeout_ms = 2000
	# In memory. A suite that wrote a player's favourites to disk is a suite that
	# passes differently the second time it is run.
	servers.favourites_path = ""
	add_child(servers)

	var started := servers.setup()
	_check(started.ok, "the browser starts", str(started.error))

	if not started.ok:
		servers.queue_free()
		remove_child(servers)
		return

	# The QUERY port, not the game port. dot-server listens for queries separately, and
	# a browser that asked the game port would get no answer and report the server as
	# offline — which reads as the browser being broken.
	var added := servers.add(
		"127.0.0.1:%d" % server.config.port, server.config.query_port
	)
	_check(added.ok, "a server can be added by address", str(added.error))

	var refreshed: DotResult = await servers.refresh()
	_check(refreshed.ok, "and asked", str(refreshed.error))

	var entries := servers.browser.entries()
	_check(entries.size() == 1, "there is one entry", "%d" % entries.size())

	if entries.is_empty():
		servers.queue_free()
		remove_child(servers)
		return

	var entry := entries[0]

	_check(
		entry.is_online(),
		"the server answered",
		entry.error.message if entry.error != null else entry.status_name()
	)

	if entry.is_online():
		# [b]The map is the GAME's, not `entry.map`.[/b] That is dot-server's
		# `info.map`, which means "the content id of the loaded game" and is empty on
		# a server that has never switched games. dot-browser nests the game's own
		# section under `rules["game"]` precisely so a game putting a field called
		# `map` in it cannot overwrite the other one.
		_check(
			G2GBrowser.game_field(entry, "map") == String(game.maps.current.id),
			"and the map the game says it is running",
			"%s vs %s" % [
				G2GBrowser.game_field(entry, "map"), String(game.maps.current.id)
			]
		)

		# The tick rate, which is the number a records player checks before anything
		# else: a time set at 100 is not a time set at 128 unless the timer counts in
		# sub-tick fractions, and a browser that could not show it would be a browser
		# nobody used twice.
		# [b]Read as a number, not as text.[/b] JSON has one number type, so an int
		# contributed to a query section comes back as a float — the first version of
		# this compared `game_field(...)` to `str(100)` and failed on `"100.0"`, which
		# is the query working and the reader guessing.
		_check(
			int(G2GBrowser.game_number(entry, "tick_rate")) == game.tick_rate,
			"and the tick rate",
			"%.1f vs %d" % [
				G2GBrowser.game_number(entry, "tick_rate"), game.tick_rate
			]
		)

		_check(
			G2GBrowser.game_field(entry, "deathmatch") != "",
			"and whether deathmatch is on, which is a mode this server now has",
			G2GBrowser.game_field(entry, "deathmatch")
		)

	servers.favourite(entry.key(), true)
	_check(servers.browser.is_favourite(entry.key()), "a server can be favourited")

	servers.favourite(entry.key(), false)
	_check(
		not servers.browser.is_favourite(entry.key()),
		"and un-favourited again"
	)

	# One line per server, which is what a chat command draws.
	var lines := servers.lines()
	_check(lines.size() == 1, "and the listing is one line per server")

	servers.queue_free()
	remove_child(servers)
	_done()


## The moderator's live tools on a timer server, where the product is a time.
##
## Driven through the console, as an operator types them, against a player with a session
## the way a real one has. What is asserted is the TIMER: noclip abandons the run it
## interrupts, a run begun while noclipped or on a speed step is marked assisted and
## refused a record, and one begun after is clean. Runs are begun by hand because this
## suite's map is the intro course and walking out of its start is not what is under test.
func _test_live_tools() -> void:
	_section("the moderator's live tools, and the timer")

	_check(
		server.console.find_command("noclip") != null and server.console.find_command("slay") != null,
		"the live tools' commands are on the console"
	)

	var session := DotClientSession.new()
	session.peer_id = 9001
	session.userid = 1
	session.display_name = "One"
	var _adopted := server.adopt_session(session)

	var player: G2GPlayer = game.players[&"u1"]
	var stopped: Array[StringName] = []
	var on_stop := func(_r: DotTimerRun, why: StringName) -> void: stopped.append(why)
	player.timer.run_stopped.connect(on_stop)

	player.timer.run.begin(0.0)
	var _on := await _run_command_later("noclip One")
	_check(DotFpsAdminModifiers.is_noclipped(player.controller), "`noclip One` puts them in noclip")
	_check(
		stopped.has(&"noclip") and not player.timer.run.is_active(),
		"and abandons the run they were on", str(stopped)
	)

	player.timer.run.begin(0.0)
	for _i in range(4):
		await get_tree().physics_frame
	_check(player.timer.run.tainted, "a run begun while noclipped is marked assisted")
	var refused := player.timer.can_record(_finished_copy(player.timer.run))
	_check(not refused.ok and refused.error.message.contains("assisted"),
		"and would be refused a record", str(refused.error))

	var _off := await _run_command_later("noclip One off")
	player.timer.run.begin(0.0)
	for _i in range(4):
		await get_tree().physics_frame
	_check(not player.timer.run.tainted, "once it is off, a new run is clean")

	var _fast := await _run_command_later("speed One 2")
	for _i in range(4):
		await get_tree().physics_frame
	_check(player.timer.run.tainted, "a speed step is help on the ground, and taints the run too")
	var _normal := await _run_command_later("speed One 1")

	# A slap is a shove in a direction the slapper knows: speed nobody earned.
	player.timer.run.begin(0.0)
	await _physics(2)
	var clean_before_slap := not player.timer.run.tainted
	var _slapped := await _run_command_later("slap One")
	_check(clean_before_slap and player.timer.run.tainted,
		"a slap taints the run it lands in, so `slap @me` is not a boost with a record at the end")

	var described := await _run_command_later("modtools")
	_check(_said(described, "abilities") and _said(described, "burn (there is no fire"),
		"`modtools` lists what a timer server supports and why it refuses the rest")

	player.timer.run_stopped.disconnect(on_stop)
	player.timer.stop()
	var _released := server.release_session(session.peer_id)
	_done()


## The two that are about a screen. What is asserted is the flag on the player and on the
## entity the netcode sends, because that is the whole of what the server decides; whether
## the owner's client — and only the owner's — receives it is `headless_net`'s, and what it
## looks like is `tools/screenshot_hud.sh`'s.
func _test_blind_and_beacon() -> void:
	_section("blind and beacon")

	var session := DotClientSession.new()
	session.peer_id = 9001
	session.userid = 1
	session.display_name = "One"
	var _adopted := server.adopt_session(session)

	var module: Object = server.modules.get_module("g2gfast")
	var bridge: Object = module.get("bridge") if module != null else null
	var tools: DotModTools = (module.get("services") as G2GServices).mod_tools if module != null else null
	var player: G2GPlayer = game.players[&"u1"]
	var net: Object = bridge.call("behaviour_for", 1) if bridge != null else null

	var blinded := await _run_command_later("blind One")
	_check(player.blinded, "`blind One` blacks their screen out", " / ".join(blinded))
	await _physics(2)
	_check(
		net != null and net.get("net_blind") == true,
		"and it is on the entity the netcode sends them"
	)

	# A blind is a screen, not help: the runner is slower for it, never faster, so the run
	# they are on is still theirs to file — where a noclip or a speed step taints it.
	player.timer.run.begin(0.0)
	await _physics(4)
	_check(not player.timer.run.tainted, "and a run made blind is not marked assisted")
	player.timer.stop()

	var _lift := await _run_command_later("blind One off")
	_check(not player.blinded, "`blind One off` lifts it")
	var _spell := await _run_command_later("blind One 0.2")
	_check(player.blinded, "`blind One 0.2` blinds them for a fifth of a second")
	await get_tree().create_timer(0.4).timeout
	_check(not player.blinded, "and it lifts on its own when the time is up")

	var lit := await _run_command_later("beacon One")
	_check(player.beacon, "`beacon One` puts a beacon on them", " / ".join(lit))
	await _physics(2)
	_check(net != null and net.get("net_beacon") == true, "and it is on the entity everybody is sent")

	# Both are about the person, not the body, and a respawn here is a teleport of the
	# same player: nothing re-applies them, so what is checked is that nothing clears them.
	var _dark := await _run_command_later("blind One")
	var _back := await _run_command_later("respawn One")
	_check(player.blinded and player.beacon, "a respawn keeps both")

	var _dark_off := await _run_command_later("blind One off")
	var _unlit := await _run_command_later("beacon One off")
	await _physics(2)
	var identity: DotNetIdentity = (net as DotNetBehaviour).identity if net != null else null
	_check(
		not player.beacon and net.get("net_beacon") == false,
		"`beacon One off` takes it off the entity"
	)
	# The arena's beaconed player is made always-relevant and put back when it goes off.
	# Every runner here is always-relevant already, so copying that would CUT everybody
	# whose beacon was turned off — this is the check that says it was not copied.
	_check(
		identity != null and identity.always_relevant,
		"and leaves them relevant to everybody, as every runner here is"
	)
	_check(
		tools != null and not tools.is_active(&"1", DotModTools.ACTION_BEACON)
		and not tools.is_active(&"1", DotModTools.ACTION_BLIND),
		"and the tools' record agrees with the world"
	)

	var described := await _run_command_later("modtools")
	_check(
		not _said(described, "blind (") and not _said(described, "beacon ("),
		"`modtools` no longer refuses blind or beacon", " / ".join(described)
	)

	var _released := server.release_session(session.peer_id)
	_done()


func _physics(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


## A finished copy of [param run], for asking `can_record` without finishing the real one.
func _finished_copy(run: DotTimerRun) -> DotTimerRun:
	var copy := DotTimerRun.make(run.track, run.style_id, 0.01)
	copy.begin(0.0)
	copy.tainted = run.tainted
	copy.used_checkpoints = run.used_checkpoints
	for _i in range(6000):
		copy.advance(1.0)
	copy.finish(0.0)
	return copy


## [method _run_command] for a coroutine handler: the live tools record each action on a
## punishment store, which may be remote, so the reply can land a frame late.
func _run_command_later(line: String) -> PackedStringArray:
	var captured: Array[String] = []
	var template := DotCmdContext.console("", PackedStringArray())
	template.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, template)
	await get_tree().process_frame
	await get_tree().process_frame
	return PackedStringArray(captured)


func _test_unload() -> void:
	_section("unload")
	var unloaded := server.modules.unload_module("g2gfast")
	_check(unloaded.ok, "the module unloads")
	_check(server.console.find_cvar("sv_autobunnyhopping") == null, "and takes its cvars with it")
	_check(game.players.is_empty(), "and the players it added")
	await get_tree().process_frame
	_done()


## [b]The one line that leaked mg-buses-from-hell's whole script graph at exit.[/b]
##
## A script that `extends DotNetMessage` and preloads ITSELF, first loaded from a module a
## running [DotServer] loads — which is how every deployed server loads this game — leaves
## every loaded script alive at exit on Godot 4.7.2 (measured in mg-buses-from-hell,
## 8ed866c). This game's event and request both did it, for a typed `of()` factory.
##
## [b]Asserted on the source, because the symptom is where no check can reach.[/b] The
## leak is reported after `quit()`, by the engine, as warnings a CI filter already treats
## as noise; an assertion here runs before any of it exists. So this checks the cause
## instead: every message script in `game/`, read as text.
func _test_no_message_preloads_itself() -> void:
	_section("exiting clean")

	var messages := PackedStringArray()
	var offenders := PackedStringArray()
	var pending: Array[String] = ["res://game"]

	while not pending.is_empty():
		var dir_path: String = pending.pop_back()

		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path.path_join(sub))

		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".gd"):
				continue

			var path := dir_path.path_join(file)
			var source := FileAccess.get_file_as_string(path)

			if not _extends_message(source):
				continue

			messages.append(path)

			if source.contains('preload("%s")' % file) or source.contains('preload("%s")' % path):
				offenders.append(path)

	_check(
		messages.size() >= 2,
		"this game's message scripts are found, so the next check is about something",
		", ".join(messages)
	)
	_check(
		offenders.is_empty(),
		"and none of them preloads itself, which leaks every script at exit",
		", ".join(offenders)
	)
	_done()


func _extends_message(source: String) -> bool:
	for line in source.split("\n"):
		if line.begins_with("extends "):
			return line.contains("DotNetMessage") or line.contains("dot_net_message.gd")
	return false


# --- Exiting clean ----------------------------------------------------------------

## The flag this suite hands the copy of itself it runs. See [method _run_exit_probe].
const EXIT_PROBE_FLAG := "--exit-probe"

## What the exit probe adds to a run — one section, these checks — and the copy does not.
const EXIT_PROBE_CHECKS := 3


func _is_exit_probe() -> bool:
	return EXIT_PROBE_FLAG in OS.get_cmdline_user_args()


## Runs this same suite in a fresh process: `[exit code, everything it printed]`.
##
## [b]A leak is reported after `quit()`, by the engine, where nothing in the process that
## leaked can read it.[/b] "N ObjectDB instances were leaked at exit" is printed once the
## scene tree is gone, so the only process that can check a run's exit is another one. On
## Godot 4.7.2 a script that names itself, loaded after its base, cuts the engine's exit
## teardown short and every script loaded before it is reported leaked — hundreds of lines
## a passing run printed for weeks, which is why this is a check now and not a warning.
##
## [b]First, before this run opens a port[/b], so the two never contend for a socket — and
## so this run is always the second one against the same `user://`, which is the other
## thing no single run can see.
func _run_exit_probe() -> Array:
	print("(running this suite once more in a fresh process, to read what it leaves at exit)")
	var scene := scene_file_path if scene_file_path != "" else "res://examples/dedicated.tscn"
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		scene, "--", EXIT_PROBE_FLAG,
	], out, true)
	var text := ""
	for chunk: Variant in out:
		text += str(chunk)
	return [code, text]


func _test_exits_clean(probe: Array) -> void:
	_section("exiting clean, as a second process saw it")

	var code: int = probe[0]
	var text: String = probe[1]

	_check(code == 0, "this suite, run again in a fresh process, passes",
		"exit %d; its last lines:\n%s" % [code, _last_lines(text, 25)] if code != 0 else "")
	_check(not text.contains("leaked at exit"), "and leaves no object alive at exit",
		_line_with(text, "leaked at exit"))
	_check(not text.contains("still in use at exit"), "and no resource",
		_line_with(text, "still in use at exit"))
	_done()


func _line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line.strip_edges()
	return ""


func _last_lines(text: String, count: int) -> String:
	var lines := text.strip_edges().split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - count)))

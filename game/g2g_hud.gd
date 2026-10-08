extends Control

const G2GConfig := preload("g2g_config.gd")
const G2GGame := preload("g2g_game.gd")
const G2GMapCatalogue := preload("g2g_map_catalogue.gd")
const G2GPlayer := preload("g2g_player.gd")

## The competitive-shooter timer HUD: the clock, the speed in u/s, the keys, the strafes.
##
## Composed from [DotTimerHud] rather than replacing it. What this adds is the genre's
## conventions: speed in genre units, a key display (the thing every bhop stream has
## in the corner), the stage, and PRACTICE the moment a checkpoint is used.

var timer_hud: DotTimerHud = null
var _keys: Label = null
var _status: Label = null
var _notice: Label = null
var _crosshair: DotCrosshair = null
var _notice_until: float = 0.0

var game: G2GGame = null
var player_id: StringName = &"local"

## The map's time left as the server's vote last described it. Null, or never adopted,
## when nothing has told this HUD anything — offline, where the local map session IS the
## clock that ends the map, and the only case in which it is.
##
## [b]The map session's clock was what this drew, and on a client it is wrong.[/b] A
## client's session starts its own clock when it loads the map and nothing the server
## decides ever reaches it: an extend added ten minutes on the server and none here, and
## under `trigger: rtv_only` it counted down a limit the server did not have.
var clock_view: DotVoteClockView = null

## How far up from the bottom the notice line starts, in pixels.
##
## The clock block's own margin is 92 and it draws about 90 tall, so anything below 182
## is inside it. This is that plus a gap, in one place, so moving the clock moves this.
const NOTICE_CLEARANCE := 196.0

## An administrator's `blind`, over the world and under the rest of the HUD.
##
## [b]Under the widgets, on purpose.[/b] A blind takes the course away, not the runner's
## bearings: the clock still counts, the keys still light and the notice line still says
## what happened, which is what makes it read as "an admin did this" rather than as a
## client that stopped drawing. The chat box and the console are the presentation
## layer's, above this HUD altogether, so a blinded runner can still ask why.
##
## Black rather than white. A white screen at full brightness is a thing a player can be
## hurt by in a dark room, and taking the picture away is the whole of the point.
var blind_overlay: ColorRect = null

## Seconds a blind takes to come down and to lift. Short, so it is unmistakably on, and
## not instant, so it reads as something done to the screen rather than a frame dropped.
const BLIND_FADE_SEC := 0.25

const BLIND_COLOUR := Color(0.01, 0.01, 0.015)

## Over everything this HUD draws while the server is on a map this client has not loaded.
##
## [b]Over the widgets, unlike the blind.[/b] There is no run to read: the clock, the keys
## and the speed all describe a player the client is not simulating (see
## [method G2GNetBridge.in_transit]). What a player saw instead was the engine's clear
## colour with a live HUD on it — a grey screen that looked like a game that had broken —
## for as long as the map took to download and build. The chat box is the presentation
## layer's and stays above this, so the wait can still be talked through.
var loading_cover: ColorRect = null
var _loading_label: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# set_anchors_preset does NOT set offsets; a Control built in code keeps its zero
	# size otherwise and lays out inside nothing. Cost this family a day in dot-ui.
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# First, so every widget added below draws over it. See [member blind_overlay].
	# Anchored to nothing and sized to the VIEWPORT in `present_blind`, not to this HUD's
	# rect: game-arena's first rendered blind left a sixteen-pixel frame of the world
	# round the edge because its HUD was inset by the safe area, and this one being the
	# full rect today is a property of its parent that nothing here promises.
	blind_overlay = ColorRect.new()
	blind_overlay.name = "Blind"
	blind_overlay.color = BLIND_COLOUR
	blind_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_overlay.modulate.a = 0.0
	blind_overlay.visible = false
	add_child(blind_overlay)

	# THE WHOLE RECT, not a box in the corner.
	#
	# `DotTimerHud` places its own block in a corner of whatever rect it is given, so
	# the rect is the AREA it lays out inside rather than the block. Handing it the
	# 360 x 200 it used to have would pin an overlay to the corner of a box in the
	# corner, which is the thing being fixed.
	timer_hud = DotTimerHud.new()
	timer_hud.name = "Timer"
	timer_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	timer_hud.offset_left = 0.0
	timer_hud.offset_top = 0.0
	timer_hud.offset_right = 0.0
	timer_hud.offset_bottom = 0.0
	timer_hud.corner = DotTimerHud.Placement.BOTTOM_CENTRE
	timer_hud.margin = Vector2(24.0, 92.0)
	timer_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(timer_hud)

	# The key display, directly under the clock, which is where every bhop stream in
	# this genre has had it for fifteen years. Centred rather than left-aligned so it
	# reads as part of the same block; monospaced-by-padding, because a proportional
	# font makes the four keys jump sideways as they light up.
	_keys = _label("Keys", HORIZONTAL_ALIGNMENT_CENTER)
	_keys.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_keys.offset_left = 0.0
	_keys.offset_right = 0.0
	_keys.offset_top = -80.0
	_keys.offset_bottom = -52.0

	# Reference rather than gameplay: the map, the track, the time limit, the rules
	# in force. Along the top, out of the way of both the crosshair and the clock.
	_status = _label("Status", HORIZONTAL_ALIGNMENT_CENTER)
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.offset_left = 0.0
	_status.offset_right = 0.0
	_status.offset_top = 14.0
	_status.offset_bottom = 40.0
	_status.modulate = Color(1.0, 1.0, 1.0, 0.62)

	# A crosshair, which this game did not have.
	#
	# It was survivable while the HUD was a column of text down the left: there was
	# something to look at. With the clock moved under the centre there is nothing at
	# all in the middle of the screen, and a first-person game with an empty centre
	# reads as broken rather than as clean. dot-ui draws one rather than shipping art,
	# which is why it can be used here without an asset.
	_crosshair = DotCrosshair.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.offset_left = 0.0
	_crosshair.offset_top = 0.0
	_crosshair.offset_right = 0.0
	_crosshair.offset_bottom = 0.0
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	# Things that just happened: a finish, a rank, a map change, a cvar an admin
	# moved. Above the clock, where a player's eye already is.
	#
	# [b]Clear of the clock, and the number is derived from the clock rather than
	# guessed.[/b] It sat at -160 and the clock block is 92 up from the bottom and about
	# 90 tall, so a finish time was drawn straight through "0:00.000" — two numbers in
	# the same font at the same size overlapping to the pixel, which reads as a font
	# glitch rather than as a layout bug. Nothing could assert it: both Labels had the
	# right text, the right size and the right anchors, and a rect that overlaps another
	# rect is a legitimate rect. `tools/screenshot_hud.sh` found it on its first run.
	_notice = _label("Notice", HORIZONTAL_ALIGNMENT_CENTER)
	_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.offset_left = -600.0
	_notice.offset_right = 600.0
	_notice.offset_top = -(NOTICE_CLEARANCE + 26.0)
	_notice.offset_bottom = -NOTICE_CLEARANCE

	# Last, so it draws over every widget above. Sized to the viewport in
	# `show_loading`, for the reason the blind is. See [member loading_cover].
	loading_cover = ColorRect.new()
	loading_cover.name = "Loading"
	loading_cover.color = BLIND_COLOUR
	loading_cover.set_anchors_preset(Control.PRESET_TOP_LEFT)
	loading_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_cover.visible = false
	add_child(loading_cover)

	_loading_label = Label.new()
	_loading_label.name = "Text"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.offset_left = 0.0
	_loading_label.offset_top = 0.0
	_loading_label.offset_right = 0.0
	_loading_label.offset_bottom = 0.0
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_cover.add_child(_loading_label)


## What the player chose to see: the four HUD switches in the menu's General page.
##
## The speed and the splits are `DotTimerHud`'s own fields, so turning one off removes its
## line from the clock's block rather than leaving a gap; the key display and the
## crosshair are this HUD's.
func apply_visibility(show_speed: bool, show_splits: bool, show_keys: bool, show_crosshair: bool) -> void:
	if timer_hud != null:
		timer_hud.show_speed = show_speed
		timer_hud.show_split = show_splits
	if _keys != null:
		_keys.visible = show_keys
	if _crosshair != null:
		_crosshair.visible = show_crosshair


func _label(p_name: String, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.name = p_name
	label.horizontal_alignment = align
	# `set_anchors_preset` does NOT set offsets — every caller above sets its own four
	# — and a Label that never got them keeps the zero size it was created with while
	# every one of its properties reads correctly. This family has shipped that twice.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func bind(p_game: G2GGame, p_player: StringName) -> void:
	game = p_game
	player_id = p_player

	game.run_filed.connect(_on_run_filed)
	# Where an authoritative game is in this process (offline, a listen server), it says
	# these itself; on a client they arrive from the server instead (G2GClient).
	game.standing_changed.connect(
		func(id: StringName, standing: Dictionary) -> void:
			if id == player_id:
				apply_standing(standing)
	)
	game.announced.connect(
		func(id: StringName, text: String, everyone: bool) -> void:
			if everyone or id == player_id:
				notice(text)
	)
	game.map_ready.connect(func(map: DotMapDef) -> void: notice(now_playing_text(map)))
	game.movement_changed.connect(
		func(config: G2GConfig) -> void:
			notice("Movement changed: autobhop %s, airaccel %.0f" % [
				"on" if config.auto_bhop else "off", config.air_accelerate
			])
	)
	game.timers.player_staged.connect(
		func(id: StringName, number: int, split: float) -> void:
			if id == player_id:
				notice("Stage %d — %s" % [number, DotTimerRun.format_time(split)])
	)

	# How many stages this map's track has, and the player's own best split at each,
	# so the clock block can say "Stage 2 / 5  -0.42" rather than only "Stage 2".
	#
	# Refreshed on a map change and on a filed run, which are the only two things that
	# change either — NOT per frame. `stage_splits_for` goes to the store, and a store
	# is a database handle behind an interface written to be asynchronous; asking it
	# 128 times a second for a number that changes twice an hour is the cost this HUD
	# would never notice locally and a server would.
	game.map_ready.connect(func(_map: DotMapDef) -> void: refresh_stage_reference())
	game.run_filed.connect(
		func(id: StringName, _run: DotTimerRun, _rank: int, _reason: String) -> void:
			if id == player_id:
				refresh_stage_reference()
	)

	refresh_stage_reference()


## Re-reads what the stage line counts and compares against.
##
## Public because a net bridge changes the track under the HUD — a player pressing T
## for the bonus is on a different track with a different stage count — and there is
## no signal for that.
func refresh_stage_reference() -> void:
	if game == null or game.timers == null:
		return

	var timer := game.timers.timer_for(player_id)

	if timer == null:
		timer_hud.set_stage_reference(0, {})
		return

	timer_hud.set_stage_reference(
		game.timers.stage_count(timer.track), game.timers.stage_splits_for(player_id)
	)


func notice(text: String) -> void:
	_notice.text = text
	_notice_until = Time.get_ticks_msec() / 1000.0 + 4.0


func _process(delta: float) -> void:
	present_blind(delta)

	if game == null:
		return

	if Time.get_ticks_msec() / 1000.0 > _notice_until:
		_notice.text = ""

	var player: G2GPlayer = game.players.get(player_id)
	if player == null:
		return

	var state := player.controller.state

	timer_hud.style_name = player.timer_style.display_name if player.timer_style != null else ""
	timer_hud.show_run(player.timer.run if player.timer != null else null, player.speed(),
		player.controller.stats.to_dictionary())

	# The key display. Read from the state's own buttons — what the SIMULATION saw —
	# rather than from Input, so it shows what the server would show for a replay.
	var cmd := player.controller.current_command
	var move := cmd.move if cmd != null else Vector2.ZERO
	var buttons := cmd.buttons if cmd != null else 0

	# The speed is NOT repeated here. `DotTimerHud` draws it in the block this line
	# sits under, and the same number twice, six pixels apart, in two different
	# formats, is the shape the old layout had.
	_keys.text = "%s %s %s %s    %s  %s" % [
		"W" if move.y > 0.1 else "·",
		"A" if move.x < -0.1 else "·",
		"S" if move.y < -0.1 else "·",
		"D" if move.x > 0.1 else "·",
		"JUMP" if buttons & DotFpsCommand.BUTTON_JUMP else "····",
		"DUCK" if buttons & DotFpsCommand.BUTTON_CROUCH else "····",
	]

	# The track is not repeated here either — `DotTimerHud` draws it beside the style,
	# where a player reads the two together.
	var parts := PackedStringArray([
		game.maps.current.name_or_id() if game.maps.current != null else "-",
	])

	var time_left := time_left_text(
		clock_view, game.maps.time_limit.formatted_remaining(), Time.get_ticks_msec() / 1000.0
	)

	# Nothing at all when the vote has no clock, rather than "no limit": a status line
	# spending a slot on something that is not happening is a slot a player learns to skip.
	if time_left != "":
		parts.append(time_left)

	parts.append("autobhop %s" % ("on" if game.config.auto_bhop else "off"))
	parts.append(player.camera.describe()["mode"] if player.camera != null else "")

	if player.timer != null and player.timer.run.used_checkpoints:
		parts.append("PRACTICE")

	if state.is_grounded():
		parts.append("ground")

	_status.text = "   ·   ".join(parts)


## Covers the screen with [param text], or uncovers it when [param text] is empty.
##
## Pushed by the client every frame from [method G2GNetBridge.transit_text] rather than
## read off the game, because whether the server is somewhere this client is not is a
## fact about the connection, and offline there is no connection to ask.
func show_loading(text: String) -> void:
	if loading_cover == null:
		return

	loading_cover.visible = text != ""

	if not loading_cover.visible:
		return

	_loading_label.text = text

	if is_inside_tree():
		var inverse := get_global_transform().affine_inverse()
		loading_cover.position = inverse * Vector2.ZERO
		loading_cover.size = inverse.basis_xform(get_viewport_rect().size)


## Fades [member blind_overlay] toward whether the followed player is blinded.
##
## Read off the player rather than pushed by anybody, because the flag arrives in a
## snapshot on a networked client and is set directly offline, and a HUD that had to be
## told would need telling from two places. Public so a check can step it.
func present_blind(delta: float) -> void:
	if blind_overlay == null:
		return

	var player: G2GPlayer = game.players.get(player_id) if game != null else null
	var want := 1.0 if player != null and player.blinded else 0.0
	blind_overlay.modulate.a = move_toward(
		blind_overlay.modulate.a, want, maxf(delta, 0.0) / BLIND_FADE_SEC
	)
	blind_overlay.visible = blind_overlay.modulate.a > 0.0

	if blind_overlay.visible and is_inside_tree():
		# The whole viewport, in this HUD's own coordinates — whatever its parent and the
		# interface scale did to where this HUD starts.
		var inverse := get_global_transform().affine_inverse()
		blind_overlay.position = inverse * Vector2.ZERO
		blind_overlay.size = inverse.basis_xform(get_viewport_rect().size)


## The line a map change puts on screen: the map, and who made it when that is known.
##
## [b]The credit is the point.[/b] The imported maps are other people's work, kept on the
## condition that their authors are credited, and `DotMapDef.author` carried each name
## from its zones file into the catalogue while nothing ever drew it (`[credit-1]`). A
## credit nobody can see is not a credit. A hand-built map has no author field and reads
## as it always did, and so does an import nobody has credited yet.
static func now_playing_text(map: DotMapDef) -> String:
	if map == null:
		return ""
	var line := "Now playing %s" % map.name_or_id()
	var who := G2GMapCatalogue.credit(map)
	if not who.is_empty():
		line += ", by %s" % who
	return line


## What the status line says about the map's time left: the server's clock when it has
## said anything — empty when that clock does not exist — and [param local] otherwise.
static func time_left_text(view: DotVoteClockView, local: String, now: float) -> String:
	if view != null and view.known:
		return view.formatted_at(now)

	return local


## The standing line: the record, the player's best and their place.
func apply_standing(standing: Dictionary) -> void:
	timer_hud.set_comparisons(float(standing.get("pb", 0.0)), float(standing.get("wr", 0.0)))
	timer_hud.set_standing(int(standing.get("rank", 0)), int(standing.get("total", 0)))
	# The stage splits come from the store's cache (`stage_splits_for` peeks, it never
	# waits), and a standing update is what has just filled it. Without this, the first
	# read after a map change on a database-backed server finds nothing cached and the
	# stage line shows no gap until the next finish.
	refresh_stage_reference()


func _on_run_filed(id: StringName, run: DotTimerRun, rank: int, reason: String) -> void:
	if id != player_id:
		return
	# A game with a store says more through `announced` (the personal best, the gap, the
	# place a refused run would have taken); this line is for one without.
	if game.timers != null and game.timers.store != null:
		return
	if reason != "":
		notice("%s — not recorded: %s" % [run.formatted_time(), reason])
	else:
		notice("%s — rank %d" % [run.formatted_time(), rank])

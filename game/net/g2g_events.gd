extends RefCounted

const G2GConfig := preload("../g2g_config.gd")
const G2GMovement := preload("../g2g_movement.gd")

## The wire format for everything that is not a snapshot or an input.
##
## Encoders and decoders in pairs, because they have to be exact inverses and nothing
## checks that for you — the headless net suite round-trips each of them.
##
## [b]Movement travels as the CONFIG, not as the tunables.[/b] A client rebuilds its
## tunables from the same [G2GConfig] fields through the same [G2GMovement] the server
## used, so the two derive bit-identical values — which is what prediction needs. A
## fingerprint rides with it so a mismatch is one log line rather than a week of "the
## netcode feels bad".

enum Kind {
	## Tick rate, who you are, the movement, the server tick. NOT the map: see [constant MAP].
	HELLO,
	## A player joined, or changed: name, peer, net id, avatar, style, track.
	JOIN,
	LEAVE,
	## The movement changed under everybody. Carries the config fields.
	MOVEMENT,
	## One message of dot-map's map-change protocol, host to peer: announce, load or abort.
	## A [DotMapMessage] as JSON. See [method write_map_message] and G2GNetBridge's
	## "Map changes" section. It used to be a bare map id sent AFTER the server had
	## changed, which a client resolved against its own build.
	MAP,
	## A player's run state changed: started, stopped, paused. A DotTimerNet.RunState.
	TIMER,
	## A player finished. A DotTimerNet.Finish plus the rank.
	FINISH,
	## Somebody set a record worth announcing.
	RECORD,
	## Text for everyone: a stage split, a refusal, a vote result.
	NOTICE,
	## The map vote: a sound cue to play, or a second of the countdown before a ballot.
	## Last, because a kind is its index on the wire.
	VOTE,
	## The map's time left, from the vote's clock: sent when it changes rather than
	## counted, so an extend reaches the HUD. Last, for the same reason.
	CLOCK,
	## A hunter now exists, or is being described to a client that just connected: its net
	## id, its kind, where it is. Its movement comes in snapshots. Appended: a kind is its
	## index on the wire.
	NPC,
	## A hunter is gone — killed, reclaimed or cleared.
	NPC_GONE,
	## Where one player stands on the board they are on: their best, the record, their
	## rank and the board's size. Server to that player only — a client has no store to
	## ask. Appended: a kind is its index on the wire.
	STANDING,
	## What a client is allowed to do on its own screen, and which chat commands it can type:
	## `sv_flashlight`, `sv_allow_thirdperson`, and the public command list the help screen
	## draws. On admit and whenever one of them changes. Appended, for the reason above.
	RULES,
	## Every map the server has, for the M screen: `[{id, name, tier, kind, rotation,
	## current}]` as JSON. Sent only to a player holding the changemap flag, on asking.
	## Appended, for the reason above.
	MAPS,
}

enum Ask {
	## I have loaded and can receive. Tell me everything.
	READY,
	## Put me on this style (index into the server's ordered table).
	STYLE,
	## Put me on this track.
	TRACK,
	## Here is my avatar.
	AVATAR,
	## Put me back at the start.
	RESTART,
	## Rock the vote.
	RTV,
	## Save a checkpoint (0), teleport to it (1), clear them (2).
	CHECKPOINT,
	## One message of dot-map's map-change protocol, peer to host: progress or ready.
	## Last, because a kind is its index on the wire.
	MAP,
	## The M screen: an empty id asks for the map list, an id asks to change to it. Both
	## are refused unless the asker holds the changemap flag. Appended.
	MAPS,
}

const NAME_BYTES := 64
const AVATAR_BYTES := 4096
const TEXT_BYTES := 256

## A map-change message from the host: an announce carries the whole [DotMapDef], meta
## and all. A few hundred bytes in practice; the cap is what a hostile or broken host
## can make a client parse.
const MAP_MESSAGE_BYTES := 4096

## A map-change message from a peer: a ready or a progress, an id, a version and a
## number. Far smaller than the host's, because it is what a CLIENT can make the server
## parse, and a peer has no reason ever to send more.
const MAP_REPLY_BYTES := 256


static func kind_name(kind: int) -> String:
	var names := Kind.keys()
	return String(names[kind]) if kind >= 0 and kind < names.size() else "?"


static func _w() -> DotNetWriter:
	return DotNetWriter.new()


# --- Movement --------------------------------------------------------------

## The G2GConfig fields the simulation reads. Everything else stays server-side.
static func write_movement(config: G2GConfig) -> PackedByteArray:
	# Snapped first, so the fingerprint is of what the receiver will read: a
	# double that does not survive float32 would otherwise fingerprint differently
	# on the two ends while every visible value agreed.
	config.snap_movement()
	var writer := _w()
	for field in G2GConfig.MOVEMENT_FIELDS:
		var value: Variant = config.get(field)
		if value is bool:
			writer.write_bool(value)
		else:
			writer.write_float32(float(value))
	writer.write_string(G2GMovement.tunables_for(config).fingerprint(), 32)
	return writer.to_bytes()


## Applies a MOVEMENT body to a config. Returns the server's fingerprint.
static func read_movement(reader: DotNetReader, config: G2GConfig) -> String:
	for field in G2GConfig.MOVEMENT_FIELDS:
		var current: Variant = config.get(field)
		if current is bool:
			config.set(field, reader.read_bool())
		else:
			config.set(field, reader.read_float32())
	return reader.read_string(32)


# --- HELLO -----------------------------------------------------------------

## [b]No map id, and there was one.[/b] HELLO carried the server's map and the client
## changed to it by id out of its own catalogue — the ad-hoc version of what dot-map's
## protocol now does, and wrong in the same two ways the MAP event was: the client never
## said whether it had the map, and a map it did not have was fetched by nothing. The
## map a joiner is on now arrives as the protocol's own announce, right behind this, and
## a field left here would be a value produced and consumed by nothing.
static func write_hello(
	tick_rate: int, player_id: int, peer_id: int, server_tick: int, config: G2GConfig
) -> PackedByteArray:
	var writer := _w()
	writer.write_uint(tick_rate, 8)
	writer.write_varint(player_id)
	writer.write_varint(peer_id)
	writer.write_uint(server_tick, 32)
	writer.write_bytes(write_movement(config))
	return writer.to_bytes()


static func read_hello(reader: DotNetReader) -> Dictionary:
	var out := {
		"tick_rate": reader.read_uint(8),
		"player_id": reader.read_varint(),
		"peer_id": reader.read_varint(),
		"server_tick": reader.read_uint(32),
		"movement": reader.read_bytes(1024),
	}
	out["ok"] = reader.ok()
	return out


# --- JOIN / LEAVE ----------------------------------------------------------

static func write_join(
	player_id: int, peer_id: int, net_id: int, display_name: String,
	avatar: DotAvatar, style_index: int, track: int
) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(player_id)
	writer.write_varint(peer_id)
	writer.write_varint(net_id)
	writer.write_string(display_name, NAME_BYTES)
	writer.write_uint(style_index, DotTimerNet.STYLE_BITS)
	writer.write_uint(track, DotTimerTrack.BITS)
	var text := JSON.stringify(avatar.to_dict()) if avatar != null else ""
	writer.write_string(text, AVATAR_BYTES)
	return writer.to_bytes()


static func read_join(reader: DotNetReader) -> Dictionary:
	var out := {
		"player_id": reader.read_varint(),
		"peer_id": reader.read_varint(),
		"net_id": reader.read_varint(),
		"name": reader.read_string(NAME_BYTES),
		"style_index": reader.read_uint(DotTimerNet.STYLE_BITS),
		"track": reader.read_uint(DotTimerTrack.BITS),
	}
	var text := reader.read_string(AVATAR_BYTES)
	out["avatar"] = null
	if text != "":
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var built := DotAvatar.from_dict(parsed)
			if built.ok:
				out["avatar"] = built.value
	out["ok"] = reader.ok()
	return out


static func write_player(player_id: int) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(player_id)
	return writer.to_bytes()


static func read_player(reader: DotNetReader) -> int:
	return reader.read_varint()


# --- MAP -------------------------------------------------------------------

## One [DotMapMessage], as JSON inside a byte cap. Empty when it would not fit.
##
## [b]JSON rather than a field-by-field encoding[/b], because dot-map owns these shapes
## and a game that re-encoded each one would have to change whenever dot-map added a
## field to [method DotMapDef.to_dictionary] — silently dropping it until then. Every
## value in them is a string, a bool or a number, and JSON's one lossy conversion, an
## int returned as a float, is one `from_dictionary` already undoes with `int()`.
##
## [b]Empty rather than truncated.[/b] [method DotNetWriter.write_string] cuts at the cap
## without a word, and half a JSON document is a parse failure on the far end that looks
## like a hostile host. The caller refuses to send an empty body and says why.
static func write_map_message(payload: Dictionary, max_bytes: int = MAP_MESSAGE_BYTES) -> PackedByteArray:
	var text := JSON.stringify(payload)
	if text.to_utf8_buffer().size() > max_bytes:
		return PackedByteArray()
	var writer := _w()
	writer.write_string(text, max_bytes)
	return writer.to_bytes()


## The dictionary back, or an empty one for anything that is not a JSON object.
##
## Empty is safe to hand straight to dot-map: [method DotMapMessage.is_map_message] says
## no to it, and both halves of the protocol return false without acting.
static func read_map_message(reader: DotNetReader, max_bytes: int = MAP_MESSAGE_BYTES) -> Dictionary:
	var text := reader.read_string(max_bytes)
	if not reader.ok() or text == "":
		return {}
	# `JSON.new().parse` rather than `JSON.parse_string`: the static one pushes an engine
	# error for bad input, and bad input here is whatever a peer chose to send.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed as Dictionary if parsed is Dictionary else {}


# --- TIMER / FINISH --------------------------------------------------------

static func write_timer(player_id: int, state: DotTimerNet.RunState) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(player_id)
	state.write(writer)
	return writer.to_bytes()


static func read_timer(reader: DotNetReader) -> Dictionary:
	var player_id := reader.read_varint()
	var state := DotTimerNet.RunState.new()
	state.read(reader)
	return {"player_id": player_id, "state": state, "ok": reader.ok()}


static func write_finish(player_id: int, finish: DotTimerNet.Finish) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(player_id)
	finish.write(writer)
	return writer.to_bytes()


static func read_finish(reader: DotNetReader) -> Dictionary:
	var player_id := reader.read_varint()
	var finish := DotTimerNet.Finish.new()
	finish.read(reader)
	return {"player_id": player_id, "finish": finish, "ok": reader.ok()}


# --- NOTICE / RECORD -------------------------------------------------------

static func write_text(player_id: int, text: String) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(player_id)
	writer.write_string(text, TEXT_BYTES)
	return writer.to_bytes()


static func read_text(reader: DotNetReader) -> Dictionary:
	return {"player_id": reader.read_varint(), "text": reader.read_string(TEXT_BYTES)}


# --- VOTE ------------------------------------------------------------------

## Bytes a cue id may occupy. An id, never a path.
const CUE_BYTES := 32

## A cue id (empty for none) and a countdown second (0 for none). What the id sounds like
## is the client's catalogue; an id it lacks is silence, which is dot-audio's rule.
static func write_vote(cue: String, seconds_left: int, runoff: bool) -> PackedByteArray:
	var writer := _w()
	writer.write_string(cue, CUE_BYTES)
	writer.write_uint(clampi(seconds_left, 0, 255), 8)
	writer.write_bool(runoff)
	return writer.to_bytes()


static func read_vote(reader: DotNetReader) -> Dictionary:
	var out := {
		"cue": reader.read_string(CUE_BYTES),
		"seconds_left": reader.read_uint(8),
		"runoff": reader.read_bool(),
	}
	out["ok"] = reader.ok()
	return out


# --- CLOCK -----------------------------------------------------------------

## The vote's clock as [method DotVoteClockView.state_of] describes it: whether there is
## one, the whole seconds left, and whether it is counting. A client counts it down
## itself between messages; the server sends another only when that count would be wrong.
## Times as whole microseconds in a varint: exact to the thousandth the boards are sorted
## by, at any length of run, where a float32 starts losing them past an hour.
static func write_standing(player_id: int, standing: Dictionary) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(player_id)
	writer.write_varint(maxi(int(round(float(standing.get("pb", 0.0)) * 1000000.0)), 0))
	writer.write_varint(maxi(int(round(float(standing.get("wr", 0.0)) * 1000000.0)), 0))
	writer.write_varint(maxi(int(standing.get("rank", 0)), 0))
	writer.write_varint(maxi(int(standing.get("total", 0)), 0))
	return writer.to_bytes()


static func read_standing(reader: DotNetReader) -> Dictionary:
	var out := {
		"player_id": reader.read_varint(),
		"pb": float(reader.read_varint()) / 1000000.0,
		"wr": float(reader.read_varint()) / 1000000.0,
		"rank": reader.read_varint(),
		"total": reader.read_varint(),
	}
	out["ok"] = reader.ok()
	return out


static func write_clock(state: Dictionary) -> PackedByteArray:
	var writer := _w()
	writer.write_bool(bool(state.get("has_clock", false)))
	writer.write_varint(maxi(int(state.get("seconds_left", 0)), 0))
	writer.write_bool(bool(state.get("running", false)))
	return writer.to_bytes()


static func read_clock(reader: DotNetReader) -> Dictionary:
	var out := {
		"has_clock": reader.read_bool(),
		"seconds_left": reader.read_varint(),
		"running": reader.read_bool(),
	}
	out["ok"] = reader.ok()
	return out


# --- Requests --------------------------------------------------------------

static func write_int(value: int) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(maxi(value, 0))
	return writer.to_bytes()


static func read_int(reader: DotNetReader) -> int:
	return reader.read_varint()


static func write_avatar(avatar: DotAvatar) -> PackedByteArray:
	var writer := _w()
	writer.write_string(JSON.stringify(avatar.to_dict()) if avatar != null else "", AVATAR_BYTES)
	return writer.to_bytes()


static func read_avatar(reader: DotNetReader) -> DotAvatar:
	var text := reader.read_string(AVATAR_BYTES)
	if text == "":
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	var built := DotAvatar.from_dict(parsed)
	return built.value if built.ok else null


# --- NPC -------------------------------------------------------------------

const NPC_ID_BYTES := 64

## Where a hunter may be when it is announced, in this game's units. A surf map is large;
## the snapshot carries the real position a tick later, this only places the body.
const NPC_EXTENT := 65536.0


static func write_npc(net_id: int, kind_id: StringName, at: Vector3) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(net_id)
	writer.write_string(String(kind_id), NPC_ID_BYTES)
	writer.write_vector3_range(at, -NPC_EXTENT, NPC_EXTENT, 28)
	return writer.to_bytes()


static func read_npc(reader: DotNetReader) -> Dictionary:
	var out := {
		"net_id": reader.read_varint(),
		"kind_id": StringName(reader.read_string(NPC_ID_BYTES)),
		"position": reader.read_vector3_range(-NPC_EXTENT, NPC_EXTENT, 28),
	}
	out["ok"] = reader.ok()
	return out


static func write_npc_gone(net_id: int) -> PackedByteArray:
	var writer := _w()
	writer.write_varint(net_id)
	return writer.to_bytes()


static func read_npc_gone(reader: DotNetReader) -> Dictionary:
	var out := {"net_id": reader.read_varint()}
	out["ok"] = reader.ok()
	return out


# --- RULES -----------------------------------------------------------------

## A RULES body is what a hostile or broken server can make a client parse. Forty-odd
## public commands with their one-line help come to about 3 KB; the cap leaves room for a
## server with twice as many and refuses anything that is not a command list.
const RULES_BYTES := 12288

## JSON rather than fields, and that is the one place in this file it is: the command
## list is a variable-length table of strings a client only DRAWS, so a typed encoding
## buys nothing a reader can check, and the two flags ride along rather than costing a
## second event kind. [code]{"flashlight": bool, "thirdperson": bool, "commands": [[name,
## help], ...]}[/code].
##
## [b]Shortened from the end of the list, never cut.[/b] `write_string` truncates at the
## cap, and a JSON document cut anywhere is one that does not parse — which would cost the
## client the two flags along with the commands it could not fit.
static func write_rules(rules: Dictionary) -> PackedByteArray:
	var body := rules.duplicate(true)
	var commands: Array = body.get("commands", [])
	var text := JSON.stringify(body)

	while text.to_utf8_buffer().size() > RULES_BYTES and not commands.is_empty():
		commands.pop_back()
		body["commands"] = commands
		text = JSON.stringify(body)

	var writer := _w()
	writer.write_string(text, RULES_BYTES)
	return writer.to_bytes()


## Never fails into a half-read: anything that does not parse to a dictionary is
## [code]{"ok": false}[/code], and the flags a server left out read as their defaults
## (everything allowed), which is what a server older than the flag meant.
static func read_rules(reader: DotNetReader) -> Dictionary:
	var text := reader.read_string(RULES_BYTES)
	# A JSON instance rather than `JSON.parse_string`, which prints an engine ERROR with a
	# backtrace for every malformed body: a server sending a bad one is the server's
	# problem, and the client's answer is a quiet refusal.
	var json := JSON.new()
	var parsed: Variant = json.data if reader.ok() and json.parse(text) == OK else null

	if not (parsed is Dictionary):
		return {"ok": false}

	var commands: Array = []

	for row in (parsed as Dictionary).get("commands", []):
		if row is Array and (row as Array).size() >= 2:
			commands.append([str(row[0]), str(row[1])])

	return {
		"ok": true,
		"flashlight": bool((parsed as Dictionary).get("flashlight", true)),
		"thirdperson": bool((parsed as Dictionary).get("thirdperson", true)),
		"commands": commands,
	}


# --- MAPS ------------------------------------------------------------------

## What the map list may occupy. 42 maps are about 4 KB; a server with three hundred
## gets the first ones that fit rather than a list cut in half.
const MAPS_BYTES := 32768


static func write_maps(rows: Array) -> PackedByteArray:
	var list := rows.duplicate()
	var text := JSON.stringify(list)
	while text.to_utf8_buffer().size() > MAPS_BYTES and not list.is_empty():
		list.pop_back()
		text = JSON.stringify(list)
	var writer := _w()
	writer.write_string(text, MAPS_BYTES)
	return writer.to_bytes()


static func read_maps(reader: DotNetReader) -> Array:
	var text := reader.read_string(MAPS_BYTES)
	var json := JSON.new()
	if not reader.ok() or json.parse(text) != OK or not (json.data is Array):
		return []
	var out: Array = []
	for row: Variant in json.data:
		if row is Dictionary and (row as Dictionary).has("id"):
			out.append(row)
	return out


## A map id asked for over the wire. Bounded by what an id is.
static func write_map_id(id: String) -> PackedByteArray:
	var writer := _w()
	writer.write_string(id, NAME_BYTES)
	return writer.to_bytes()


static func read_map_id(reader: DotNetReader) -> String:
	return reader.read_string(NAME_BYTES)

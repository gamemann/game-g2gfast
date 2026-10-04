extends Node

const G2GBspMap := preload("../game/g2g_bsp_map.gd")
const G2GConfig := preload("../game/g2g_config.gd")
const G2GGame := preload("../game/g2g_game.gd")
const G2GPlayer := preload("../game/g2g_player.gd")
const G2GUnits := preload("../game/g2g_units.gd")
const RouteBot := preload("../tools/route_bot.gd")

## Checks a map imported from a Source .bsp: it loads, it is the right size, it is
## lit, and — the only question that matters — a player put on it stays on it.
##
## [codeblock]
## godot --headless --path . res://examples/headless_imported.tscn
## [/codeblock]
##
## [b]Why collision is the check and geometry is not.[/b] Every number about an
## imported map can be right while the map is unplayable: the vertex count, the
## bounds, the material list and the manifest all pass if the triangles are wound
## inside out or the collision body was never built, and a player then falls through
## a map that renders perfectly. This file's own repeated lesson — a value produced
## correctly and consumed by nothing — reaches imported geometry through collision.
##
## Skips rather than fails when nothing has been imported: `maps/imported/` is
## optional content and a clone that has never run the importer is not broken.

## The imported maps that are deliberately NOT courses, and why each one is not.
##
## [b]This suite asserted that every imported map is runnable, and `maps/zones/README.md`
## says in so many words that three of them are not.[/b] The check and the decision
## contradicted each other for as long as both existed, and the suite was the one that was
## wrong: it had been exiting 1 on three maps that are behaving exactly as documented.
##
## - `buses_from_hell_fixed` is a vehicle map. No teleports, no destinations, eight
##   `func_rotating` and a `game_ui` — there is no route to time.
## - `bhop_eazy` and `bhop_lego2` are section-chain maps (`t11`..`t2727`, `s_1`..`s_30`)
##   whose sections are all labelled and whose END is not. Nothing in either file
##   distinguishes the last gate from the twenty-six before it, and guessing would produce a
##   leaderboard that looks right and measures a route the map does not have.
##
## [b]The exemption is checked in both directions, which is what stops it being a mute
## button.[/b] A map in here that turns out to HAVE a runnable main track fails — because
## the reason it is listed has stopped being true and the list is now the lie. That is the
## same bargain every skip in this family makes: it is allowed to skip a check, it is not
## allowed to stop asking the question.
const NOT_COURSES := ["buses_from_hell_fixed", "bhop_eazy", "bhop_lego2"]

## The imported maps with no pit, which is a different question from having no finish.
##
## [b]A separate list of one, rather than reusing [constant NOT_COURSES], and the difference
## is the whole point.[/b] A surf or bhop map's `trigger_teleport` volumes ARE its pit, and
## losing them means a player who falls off falls for ever. `bhop_eazy` and `bhop_lego2`
## have pits and are checked for them; only `buses_from_hell_fixed` has none, because a
## vehicle map has nothing to fall off. Folding the two lists together would stop asking two
## maps a question they currently answer correctly, which is how an exemption quietly grows.
const NO_PIT := ["buses_from_hell_fixed"]

## Arrivals on these maps that DO land inside a pit on their own track, by label.
##
## [b]Known, not accepted[/b] (`[arrive-1]`). Two of the three that were here are fixed:
##
## - `surf_mesa`'s door landed 237 units over the SLOPED top of a teleport brush and
##   inside its bounding box -- a zone is a box and a brush is a hull. `trim_to_hull` in
##   `tools/bsp_import.py` asks `point_in_brush` of every arrival and cuts the box back.
## - `surf_summit` stage 3 landed on the floor beam of a gate whose far side is the fail
##   plane. Its zones file gives the stage a destination on the deck past the gate.
##
## `surf_greensway` stage 2 is not a wedge: its arrival (the floor of `checkpoint_1`, a
## plane 3,328 wide and 7,168 tall) is INSIDE the hull of the mapper's own teleport, and
## so is every floor and both canyon rims within 1,700 units of the line, measured with
## `point_in_brush`. The checkpoint is a split with nowhere to stand; where `!s2` should
## put a player wants somebody to look at the map in-game.
##
## Asserted both ways, like [constant NOT_COURSES]: a map in here whose arrival stops
## landing in a pit fails, so the list cannot outlive its reason.
const ARRIVES_IN_PIT := {
	"surf_greensway": ["stage 2"],
}

## Imported bonuses with no pit of their own, by track, which `route_problems()` reports.
##
## [b]Empty since `[track-zone-2]`, and kept so the next one has somewhere to go.[/b] The
## importer used to turn every leftover `trigger_teleport` into a RESPAWN on the MAIN
## track, and the timer acts only on the run's own, so bhop_pit's bonus, surf_arcade's,
## surf_beginner2's four and surf_summit's two had no pit: a player who fell off one fell
## for ever. `pit_tracks` in `tools/bsp_import.py` gives a teleport to the track whose
## START its destination is in -- a fail teleport sends a player back to the start of the
## route they fell off -- and every one of those bonuses has pits now.
##
## Asserted both ways, like [constant NOT_COURSES]: a listed map must report exactly
## these tracks and nothing else, and an unlisted map must report nothing, so a map
## that gains a pit or loses one fails here and the list cannot outlive its reason.
const BONUSES_WITHOUT_PITS := {}

## The share of a map's triangles drawn in the texture its own pakfile carried, at least,
## for the maps where a parsing bug was measured taking it away (2026-09-27): a leading
## `/` on the material name and a `$basetexture` with a space in it. Measured after the
## fix at 99%, 97% and 100%; before it, 2%, 8% and 0%.
const OWN_TEXTURES := {
	"surf_interference": 0.9,
	"surf_aquaflow": 0.9,
	"bhop_eazy": 0.9,
}

## Maps whose terrain is mostly `WorldVertexTransition` blends with both textures in the
## pakfile, measured 2026-10-04: losing the second texture is the largest visible change
## any of them can have, and it fails nothing else.
const BLENDED := ["surf_mesa", "surf_summit", "surf_greensway", "bhop_evolve", "surf_aquaflow"]

## Checks every map gets. Tracks and stages add one each on top — see [member _expected].
const CHECKS_PER_MAP := 40

## Sections every map runs, entered against run to their last line. A runtime error inside
## a section aborts that function and nothing says so; a section that bailed out after a
## failed guard is counted as not finished on purpose, and the two that end early because
## a map legitimately has nothing to check (no course, no door) say so first.
const SECTIONS_PER_MAP := 10

## A script error inside a test aborts THAT TEST and not the run, so a suite that has
## quietly lost two checks still prints "0 failed" — which is what happened while this
## file was being written, to the zone section. The count is asserted, not trusted.
var _expected := 0
var _map_id: StringName = &""

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var game: G2GGame = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("g2gfast — imported map")
	print("")

	# Every map under maps/imported/, not one this file names. A suite with its own
	# copy of the list is the bug the discovery in G2GGame exists to avoid.
	var ids := _imported_ids()
	if ids.is_empty():
		print("nothing in maps/imported/ — nothing to check")
		print("  tools/bsp_import.py <a .bsp> maps/imported --id <name>")
		get_tree().quit(0)
		return

	for id in ids:
		_map_id = id
		_expected += CHECKS_PER_MAP
		print("=== %s" % id)
		await _test_loads("res://maps/imported/%s/%s.json" % [id, id])
		await _test_geometry()
		await _test_lighting()
		_test_zones()
		_test_runnable()
		await _test_stands_on_it()
		await _test_stands_where_it_sends_you()
		_test_arrivals_miss_the_pits()
		_test_a_door_keeps_the_run()
		await _test_runs_its_route()
		if game != null:
			game.queue_free()
			game = null
			await get_tree().process_frame

	print("")
	if _passed + _failed != _expected:
		_failed += 1
		_failures.append("the suite ran %d checks and should run %d — one aborted"
			% [_passed + _failed, _expected])
	print("%d passed, %d failed, %d of %d sections ran to their last line" % [
		_passed, _failed, _completed, _entered
	])
	for line in _failures:
		print("  FAIL  %s" % line)
	var sections := SECTIONS_PER_MAP * ids.size()
	if _entered != sections or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, sections
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS_PER_MAP].
func _done() -> void:
	_completed += 1


func _imported_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open("res://maps/imported")
	if dir == null:
		return out
	# `-- <id> [<id>...]` checks only those, for arming a check on the map it is about
	# without the other twenty-five minutes. The full suite is still the one that counts.
	var only := OS.get_cmdline_user_args()
	for id in dir.get_directories():
		if not only.is_empty() and not only.has(id):
			continue
		if FileAccess.file_exists("res://maps/imported/%s/%s.json" % [id, id]):
			out.append(StringName(id))
	out.sort()
	return out


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append("%s%s" % [what, "" if detail.is_empty() else "  (%s)" % detail])
		print("  FAIL  %s%s" % [what, "" if detail.is_empty() else "  (%s)" % detail])


func _test_loads(manifest_path: String) -> void:
	_section("loading")
	var config := G2GConfig.new()
	config.records_directory = ""
	config.map_seconds = 0.0
	config.initial_map = _map_id

	game = G2GGame.new()
	game.config = config
	add_child(game)
	for _i in range(120):
		await get_tree().process_frame
		if game.maps != null and game.maps.current != null:
			break

	_check(game.maps != null and game.maps.current != null and game.maps.current.id == _map_id,
		"the imported map is in the catalogue and loads")
	# Discovery, not a list. If this fails the map was found by something naming it.
	_check(FileAccess.file_exists(manifest_path), "its manifest is beside it")
	_done()


func _test_geometry() -> void:
	_section("geometry")
	var node := game.current_map_node()
	_check(node is G2GBspMap, "the map node is a G2GBspMap")
	var mi := node.get_node_or_null("World") as MeshInstance3D
	_check(mi != null and mi.mesh != null, "it built a mesh")
	if mi == null or mi.mesh == null:
		return
	var mesh := mi.mesh
	_check(mesh.get_surface_count() > 1, "with a surface per material",
		"%d surfaces" % mesh.get_surface_count())

	# Every surface the manifest lists is drawn, across however many instances it took.
	# A mesh holds 256 and `bhop_monster_jam` has 311: in one mesh the last 55 were
	# refused by the engine and the map was drawn with holes in it while every
	# collision and standing check passed, because collision is built from the brushes.
	var drawn := 0
	for child in node.get_children():
		if child is MeshInstance3D and (String(child.name).begins_with("World")
				or String(child.name).begins_with("Props")
				or String(child.name).begins_with("Sky")) \
				and (child as MeshInstance3D).mesh != null:
			drawn += (child as MeshInstance3D).mesh.get_surface_count()
	var listed: int = (node as G2GBspMap).manifest.get("surfaces", []).size()
	_check(drawn == listed, "and every surface the manifest lists is drawn",
		"%d of %d" % [drawn, listed])

	# [b]Static props are drawn (2026-09-27).[/b] 17 of the 26 maps place them and every
	# one was absent: surf_aquaflow's whole reef, surf_greensway's forest, surf_summit's
	# trees and arches. The count of props the importer DREW is from the models it read,
	# the count PLACED is from the lump; a map that placed props it carried and drew none
	# is an importer that stopped reading them.
	var manifest_props: Dictionary = (node as G2GBspMap).manifest.get("static_props", {})
	var carried := int(manifest_props.get("placed", 0)) - int(manifest_props.get("stock_models", 0))
	var prop_surfaces := 0
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Props") \
				and (child as MeshInstance3D).mesh != null:
			prop_surfaces += (child as MeshInstance3D).mesh.get_surface_count()
	_check(carried <= 0 or (int(manifest_props.get("drawn", 0)) > 0 and prop_surfaces > 0),
		"and the static props its pakfile carried are drawn",
		"%s; %d prop surfaces drawn" % [manifest_props, prop_surfaces])

	# [b]And a 3D skybox is a backdrop, not a miniature (2026-09-27).[/b] Ten maps have one;
	# its faces were drawn at a sixteenth of their size where they were compiled and no
	# backdrop at all. Drawn, they are their own `Sky` instances, scaled about the camera.
	var sky: Variant = (node as G2GBspMap).manifest.get("skybox", null)
	var sky_node := node.get_node_or_null("Sky") as MeshInstance3D
	# "Has one" is read from the lighting block's sky_camera, a second code path, so a
	# skybox the importer stopped handling at all is a failure and not a map without one.
	var has_camera := ((node as G2GBspMap).manifest.get("lighting", {}) as Dictionary) \
		.has("sky_camera")
	var told_off := sky is Dictionary and (not bool((sky as Dictionary).get("drawn", true))
		or int((sky as Dictionary).get("faces", 0)) == 0)
	var wants_sky := has_camera and not told_off
	_check(sky_node != null if wants_sky else sky_node == null,
		"and its 3D skybox is drawn as a backdrop exactly when it has one to draw",
		"skybox %s, Sky node %s" % [sky, sky_node != null])

	# [b]And a 3D skybox has something in it (2026-10-02).[/b] bhop_pandora2_fix and
	# bhop_supernova build theirs from `prop_dynamic`s alone, and a static-props-only
	# importer found the room and drew nothing in it: faces 0, props 0, an empty sky.
	var sky_things := 0
	if sky is Dictionary:
		sky_things = int((sky as Dictionary).get("faces", 0)) + int((sky as Dictionary).get("props", 0))
	_check(not (sky is Dictionary and bool((sky as Dictionary).get("drawn", true))) or sky_things > 0,
		"and a 3D skybox it draws has faces or props in it", str(sky))

	# [b]And it is in front of the camera's far plane (4000 m).[/b] Drawn at the sky
	# camera's own 512, pandora's nearest asteroid was 5 km out and its islands past 20 km:
	# imported and invisible. The importer measures where the nearest and farthest of the
	# sky land (`reach_units`); the nearest must be visible, and a scale it drew at may be
	# smaller than the mapper's but never larger.
	var visible := true
	var reach_detail := "no 3D skybox drawn"
	if sky is Dictionary and bool((sky as Dictionary).get("drawn", true)) and sky_things > 0:
		var reach: Array = (sky as Dictionary).get("reach_units", [])
		var drawn_scale := float((sky as Dictionary).get("drawn_scale", INF))
		visible = reach.size() == 2 and G2GUnits.to_metres(float(reach[0])) <= 4000.0 \
			and drawn_scale <= float((sky as Dictionary).get("scale", 0.0))
		reach_detail = "reach %s u at %s x (the mapper's %s)" % [
			str(reach), str(drawn_scale), str((sky as Dictionary).get("scale"))]
	_check(visible, "and its 3D skybox is drawn in front of the camera's far plane", reach_detail)

	var verts := 0
	var has_uv2 := true
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if arrays[Mesh.ARRAY_TEX_UV2] == null:
			has_uv2 = false
	_check(verts > 1000, "and real geometry", "%d verts" % verts)
	# UV2 is the whole reason this is not a glTF import. If it is gone the map is lit
	# by whatever texel the atlas happens to have at (0,0).
	_check(has_uv2, "and a second UV set on every surface, for the baked lighting")

	var aabb := mi.get_aabb()
	var units := aabb.size / G2GUnits.METRES_PER_UNIT
	# Source's own limit is +/-16384 units, so a map is at most 32768 across. Ten
	# times that means the unit ratio was applied twice or not at all -- the one
	# mistake that makes an imported map silently unplayable rather than wrong.
	# The LONGEST side, not x: bhop_grove is one corridor 704 units across and 32,192
	# long, and asking its x of the unit ratio failed a map that is exactly right.
	var longest := maxf(units.x, maxf(units.y, units.z))
	_check(longest > 1000.0 and longest < 40000.0,
		"and is the size a Source map can be", "%.0f x %.0f x %.0f units" % [units.x, units.y, units.z])
	_done()


func _test_lighting() -> void:
	_section("lighting")
	var node := game.current_map_node() as G2GBspMap
	var lm: Dictionary = node.manifest.get("lightmap", {})
	var path: String = "res://maps/imported/%s/%s" % [_map_id, lm.get("file", "")]
	_check(ResourceLoader.exists(path), "the baked lightmap atlas is an imported resource", path)

	var mi := node.get_node_or_null("World") as MeshInstance3D
	var mat := mi.get_surface_override_material(0) as ShaderMaterial if mi != null else null
	_check(mat != null, "surfaces carry a ShaderMaterial")
	if mat == null:
		return
	_check(mat.get_shader_parameter("lightmap_tex") is Texture2D,
		"and the atlas is bound to every one of them")

	# A texture the map did not carry is painted its own measured colour, not a role grey.
	# Most of a map is such surfaces, so a regression here turns every map back into the
	# four greys it looked like before -- a thing no other check in this suite can see,
	# because every greyscale surface is still a correctly configured material. Most rather
	# than all: a light panel vrad measured as black keeps its role colour on purpose.
	var prototype := 0
	var coloured := 0
	for entry: Dictionary in node.manifest.get("surfaces", []):
		if bool(entry.get("prototype", false)):
			prototype += 1
			if entry.get("colour", null) is Array:
				coloured += 1
	# A jump map's blocks are brush entities, and for as long as there were imported maps
	# only the world was drawn: every block was solid and invisible (47% of bhop_eazy).
	var ents: Dictionary = node.manifest.get("brush_entities", {})
	_check(int(ents.get("solid", 0)) == 0 or int(ents.get("faces_drawn", 0)) > 0,
		"and a map with solid brush entities draws them, not only the world",
		"%s" % ents)
	_check(prototype == 0 or coloured * 2 >= prototype,
		"and a surface whose texture did not ship is painted the map's own colour for it",
		"%d of %d prototype surfaces coloured" % [coloured, prototype])

	# [b]A texture the pakfile carried is drawn, not replaced by the prototype grid.[/b]
	# Two spellings the importer did not read: a material typed with a leading `/`
	# (`/SURFACE`, looked up as `materials//surface.vmt`) and a `$basetexture` with a
	# space in it (`"hammer textures/..."`, cut at the space). Between them they cost
	# surf_interference 97% of its own textures, surf_aquaflow a third and bhop_eazy all
	# of them, and nothing said so: a prototype surface is a correctly configured
	# material. A name with the slash still on it fails every map; the share is asserted
	# for the maps it was measured on, see [constant OWN_TEXTURES].
	var tris := 0
	var own := 0
	var slashed := PackedStringArray()
	for entry: Dictionary in node.manifest.get("surfaces", []):
		# The map's own faces: a static prop's stock texture is a different question.
		if bool(entry.get("prop", false)):
			continue
		var n := int(entry.get("index_count", 0)) / 3
		tris += n
		if entry.get("texture", null) is String and not str(entry["texture"]).is_empty():
			own += n
		if str(entry.get("material", "")).begins_with("/"):
			slashed.append(str(entry["material"]))
	var share := float(own) / float(maxi(tris, 1))
	var floor_share: float = OWN_TEXTURES.get(String(_map_id), 0.0)
	_check(slashed.is_empty() and share >= floor_share,
		"and the textures its pakfile carried are drawn",
		"%.0f%% of triangles in their own texture, %.0f%% expected; names with a leading '/': %s"
			% [share * 100.0, floor_share * 100.0, slashed])

	# [b]A blend material draws both its textures.[/b] `WorldVertexTransition` paints a
	# second texture by vertex alpha, and the importer took only the first: grey rock where
	# surf_mesa's reference footage has warm orange, on 67% of its triangles. The alpha
	# travels in its own block (`alpha_offset`) and reaches the shader as COLOR.a, so a
	# drawn blend surface has to have both the texture and a colour array that varies.
	# [constant BLENDED] names maps that must have one, which is what catches an importer
	# that stopped finding them.
	var listed := 0
	for entry: Dictionary in node.manifest.get("surfaces", []):
		if entry.has("texture2") and entry.has("alpha_offset"):
			listed += 1
	var drawn_ok := 0
	var drawn_bad := PackedStringArray()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var each := child as MeshInstance3D
		if each.mesh == null:
			continue
		for i in range(each.mesh.get_surface_count()):
			var smat := each.get_surface_override_material(i) as ShaderMaterial
			if smat == null or smat.get_shader_parameter("has_albedo2") != true:
				continue
			var colours: Variant = each.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
			var most := 0.0
			if colours is PackedColorArray:
				for c in colours:
					most = maxf(most, c.a)
			if smat.get_shader_parameter("albedo2_tex") is Texture2D and most > 0.05:
				drawn_ok += 1
			else:
				drawn_bad.append("%s#%d" % [each.name, i])
	_check(drawn_bad.is_empty() and drawn_ok >= mini(listed, 1)
			and (listed > 0 or not BLENDED.has(String(_map_id))),
		"and a material that blends two textures draws both",
		"%d listed, %d drawn with a varying alpha, broken: %s" % [listed, drawn_ok, drawn_bad])

	# [b]No sky is a blank white dome.[/b] The procedural sky's top is the map's `_ambient`,
	# and four maps never set theirs and carry the editor's default 255 255 255 (surf_beginner2,
	# bhop_aztec, bhop_mario_fxd, bhop_evolve); G2GLighting looks those up by sky name.
	# Armed by taking that out: it fires on exactly those four.
	var top := Color(0, 0, 0)
	var world := node.get_node_or_null("Lighting") as WorldEnvironment
	if world != null and world.environment != null and world.environment.sky != null:
		var sky_mat := world.environment.sky.sky_material as ProceduralSkyMaterial
		if sky_mat != null:
			top = sky_mat.sky_top_color
	_check(minf(top.r, minf(top.g, top.b)) < 0.99,
		"and its sky is not a blank white dome", "sky top %s, sky name '%s'"
			% [top, node.manifest.get("lighting", {}).get("sky_name", "")])
	_done()


func _test_zones() -> void:
	_section("zones")
	var zones := game.timers.zones
	_check(zones != null, "the map produced a zone set")
	if zones == null:
		return
	_check(zones.problems().is_empty(), "which is well formed", ", ".join(zones.problems()))
	var respawns := zones.of_kind(DotTimerZone.Kind.RESPAWN).size()
	# A surf map's trigger_teleport volumes are its pit. Losing them means a player
	# who falls off falls for ever, which is the bug dot-timer's effect_requested was.
	if NO_PIT.has(_map_id):
		_check(respawns == 0, "has no pit, and still has none",
			"listed in NO_PIT; %d respawn zones" % respawns)
	else:
		_check(respawns > 0, "with the pit volumes carried across as RESPAWN zones",
			"%d respawn zones" % respawns)

	# Source sweeps its trigger tests; dot-timer samples a point per tick. A pit drawn
	# as a 16-unit plane -- which is how every one of them is drawn, because in Source
	# that is enough -- is stepped clean over by a player falling at genre speed, and
	# they then fall for ever. 48 of surf_kitsune's 53 were that thin on import.
	var thin := zones.thin_zones(G2GUnits.to_metres(3500.0), game.tick_rate)
	_check(thin.is_empty(), "and no zone a 3500 u/s player passes through between ticks",
		"%d thin" % thin.size())

	# The two zones without which a map is scenery. Every one of these maps had them
	# in its entity lump or in maps/zones/ before it was offered as a level; a map
	# that reaches here without them is one the importer stopped reading.
	var tracks := zones.playable_tracks()

	if NOT_COURSES.has(_map_id):
		# Asserted the other way round. See [constant NOT_COURSES]: if this map has grown a
		# finish, the list is out of date and that is worth a failure, because the next
		# person to read it would believe it.
		_check(not tracks.has(DotTimerTrack.MAIN),
			"is not a course, and still is not",
			"listed in NOT_COURSES; runnable tracks: %s" % str(tracks))
	else:
		_check(tracks.has(DotTimerTrack.MAIN),
			"the main track has both a start line and a finish",
			"runnable tracks: %s" % str(tracks))

	# A track a player cannot be put on is a track nobody plays. `spawn_for` falls
	# back to `fallback_spawn_units` for a missing one, which is the main track's
	# spawn -- so a bonus with no spawn of its own silently starts at the map's start,
	# and looks like a bonus that does not work rather than like a missing zone.
	var without := PackedStringArray()
	for track in tracks:
		if zones.first_of_kind(DotTimerZone.Kind.SPAWN, track) == null:
			without.append(DotTimerTrack.name_of(track))
	_check(without.is_empty(), "and every runnable track has somewhere to spawn",
		", ".join(without))

	# `[track-zone-1]`: every route, per track — a start, a finish, a spawn and a pit of
	# its own. See [constant BONUSES_WITHOUT_PITS] for the ones known not to have one.
	var expected := PackedStringArray()
	for track: int in BONUSES_WITHOUT_PITS.get(String(_map_id), []):
		expected.append("%s has no respawn zone" % DotTimerTrack.name_of(track))
	var reported := PackedStringArray()
	for problem in zones.route_problems():
		var cut := problem.find(",")
		reported.append(problem.substr(0, cut) if cut > 0 else problem)
	_check(reported == expected,
		"every route has a start, a finish, a spawn and a pit" if expected.is_empty()
			else "its bonuses without a pit are the ones listed, and only those",
		"reported %s, listed %s" % [reported, expected])
	_done()


func _test_runnable() -> void:
	_section("runnable")
	var zones := game.timers.zones
	if zones == null:
		_check(false, "a run can be started, split and finished")
		_check(false, "and its stages come out in order")
		return

	# [b]Drive the timer over the map's own zones and see a time come out.[/b] Every
	# other check here is about a zone existing; this is the only one about the zones
	# adding up to a run. A start with no reachable finish, a stage numbered past the
	# end, a finish inside the start -- all of them pass `problems()` and none of them
	# produces a time.
	var timer := DotTimer.new()
	timer.bind(zones, game.tick_rate)
	var finished: Array[DotTimerRun] = []
	timer.run_finished.connect(func(run: DotTimerRun) -> void: finished.append(run))

	var start := zones.first_of_kind(DotTimerZone.Kind.START, DotTimerTrack.MAIN)
	var finish := zones.first_of_kind(DotTimerZone.Kind.END, DotTimerTrack.MAIN)

	if NOT_COURSES.has(_map_id):
		# Both checks still run and still count; what changes is what the right answer is.
		# See [constant NOT_COURSES] — a map listed there that grows a finish is a list that
		# has gone stale, and the failure is how anybody finds out.
		_check(start == null or finish == null,
			"has no run to time, as documented",
			"listed in NOT_COURSES")
		_check(true, "and no stages to order")
		_done()
		return

	if start == null or finish == null:
		_check(false, "a run can be started, split and finished", "no start or no end")
		_check(false, "and its stages come out in order")
		return

	# [b]A tick outside every zone, between the start and everything after it.[/b] The
	# run begins on the tick the player LEAVES the start line, and that happens after
	# the zone handling for the same tick -- so a route that steps straight from the
	# start into the first stage arrives while the run is still IDLE and the split is
	# dropped. It is an artifact of stepping a timer by hand rather than walking a
	# map, and it cost every staged map here exactly one split until the gap was put
	# back in.
	var bounds: Dictionary = (game.current_map_node() as G2GBspMap).manifest.get("bounds", {})
	var away := G2GUnits.vector_to_metres(Vector3(
		float((bounds.get("max", [0, 0, 0]) as Array)[0]),
		float((bounds.get("max", [0, 0, 0]) as Array)[1]),
		float((bounds.get("max", [0, 0, 0]) as Array)[2]))) + Vector3(0.0, 128.0, 0.0)

	# From stage 2, because stage 1 IS the start line on every map that numbers its
	# own stages -- and stepping back into the start zone mid-route makes the timer do
	# what it should: treat leaving it again as a new attempt, wiping the splits.
	var route: Array[Vector3] = [start.centre(), start.centre(), away]
	for n in range(2, zones.stage_count(DotTimerTrack.MAIN) + 1):
		var stage := zones.stage_zone(DotTimerTrack.MAIN, n)
		if stage != null:
			route.append(stage.centre())
	route.append(finish.centre())

	var sample := DotTimerSample.new()
	for point in route:
		sample.previous_position = sample.position
		sample.position = point
		sample.grounded = true
		timer.tick(sample)

	_check(finished.size() == 1, "a run can be started, split and finished",
		"%d finishes" % finished.size())
	if finished.is_empty():
		_check(false, "and its stages come out in order")
		return

	# Stage 1 is the start line, and a run begins by LEAVING it -- so its split is the
	# one that legitimately never arrives. Every stage after it must.
	var wanted := maxi(0, zones.stage_count(DotTimerTrack.MAIN) - 1)

	var got := 0
	for n in range(2, zones.stage_count(DotTimerTrack.MAIN) + 1):
		if finished[0].splits.has(n):
			got += 1
	_check(got == wanted, "and its stages come out in order",
		"%d of %d splits" % [got, wanted])
	_done()


func _test_stands_on_it() -> void:
	_section("collision")
	var node := game.current_map_node()
	# Anywhere under the map, not under the MeshInstance3D. The solid used to BE the
	# mesh -- `create_trimesh_collision()` parents a `World_col` to it -- and it is not
	# any more: it is built from the .bsp's brushes, which is a different set of
	# geometry from the drawn faces and belongs to the map rather than to the drawing of
	# it. The old shape is still what a pre-collision manifest falls back to, so this
	# has to find both.
	var body: Node = null
	for c in node.find_children("*", "StaticBody3D", true, false):
		body = c
		break
	_check(body is StaticBody3D, "the world has a static body")
	var shape_count := 0
	if body != null:
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				shape_count += 1
	_check(shape_count > 0, "with a collision shape on it", "%d shapes" % shape_count)

	var bot := game.add_player(&"bot", "Bot", true)
	_check(bot != null, "a player joins")
	if bot == null:
		return
	bot.sampler = null

	var start := node.spawn_for(0)
	await get_tree().physics_frame
	_check(bot.global_position.distance_to(start) < 2.0, "at the map's own spawn",
		"%.1f m away" % bot.global_position.distance_to(start))

	# Let it fall. On a map whose collision never got built this is the only check in
	# the file that fails, and it fails by hundreds of metres rather than marginally.
	var floor_y := start.y
	for _i in range(180):
		await get_tree().physics_frame
	var drop := floor_y - bot.global_position.y
	_check(drop < 8.0, "and is still standing on the map three seconds later",
		"fell %.1f m" % drop)

	# [b]And where it came to rest is inside the start zone (2026-09-27).[/b] The timer asks
	# the zone about the player's own position every tick; a start box that stops short of
	# the floor contains the spawn in mid-air and not the player standing under it, so the
	# run starts as they fall out of it and a player on the pad can never be "in the
	# start". surf_arcade was that: its start is a box around `s1_reset`, which stands
	# 240 units over the pad, and at +/-128 the player rested 112 units under it. Armed
	# by putting the old box back.
	var start_zone := game.timers.zones.first_of_kind(DotTimerZone.Kind.START, DotTimerTrack.MAIN) \
		if game.timers.zones != null else null
	if start_zone == null:
		_check(NOT_COURSES.has(_map_id), "and comes to rest inside the start zone",
			"no start zone on the main track")
	else:
		var at := bot.controller.state.position
		_check(start_zone.contains(at), "and comes to rest inside the start zone",
			"at %s, zone %s..%s" % [at / G2GUnits.METRES_PER_UNIT,
				start_zone.from / G2GUnits.METRES_PER_UNIT, start_zone.to / G2GUnits.METRES_PER_UNIT])

	var bounds: Dictionary = (node as G2GBspMap).manifest.get("bounds", {})
	var min_y: float = float((bounds.get("min", [0, -16384, 0]) as Array)[1]) * G2GUnits.METRES_PER_UNIT
	_check(bot.global_position.y > min_y, "and has not left the world",
		"y=%.1f, world floor %.1f" % [bot.global_position.y, min_y])
	_done()


## Every place the map can put a player: each track's spawn, and each `!s<n>`.
##
## [b]A destination is the one field nothing else checks.[/b] `DotTimerManager`
## resolves "go to stage 3" to a zone's [member DotTimerZone.destination] and hands it
## to the host, which teleports; a destination that is in the sky, inside a wall, or
## left at the origin succeeds at every step and drops the player out of the world.
## Standing on it for a second is the whole test, and it is the same test as the one
## above with somewhere else to stand.
func _test_stands_where_it_sends_you() -> void:
	_section("destinations")
	var node := game.current_map_node()
	var zones := game.timers.zones
	var spots: Array = []
	if zones != null:
		for track in zones.playable_tracks():
			var spawn := zones.first_of_kind(DotTimerZone.Kind.SPAWN, track)
			if spawn != null:
				spots.append([DotTimerTrack.short_name_of(track) + " spawn", spawn.destination])
			for n in range(1, zones.stage_count(track) + 1):
				var stage := zones.stage_zone(track, n)
				if stage != null:
					spots.append(["stage %d" % n, stage.destination])
	_expected += spots.size()

	var bot: G2GPlayer = game.players.get(&"bot")
	if bot == null:
		bot = game.add_player(&"bot", "Bot", true)
		bot.sampler = null
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		bot.teleport(at, 0.0)
		for _i in range(90):
			await get_tree().physics_frame
		var drop := at.y - bot.global_position.y
		_check(drop < 8.0, "%s is somewhere a player can stand" % spot[0],
			"fell %.1f m from %s" % [drop, str(at / G2GUnits.METRES_PER_UNIT)])
	_done()


## Every place the map puts a player -- a spawn, a stage, the far side of a door -- is
## outside every pit on that track.
##
## [b]A pit that contains its own arrival is a loop nobody can see from the zone list.[/b]
## A respawn fires on ENTRY, so a player put inside one is sent back to the start the
## first time they move -- which from the player's side is a `!s2` that does nothing and
## a stage nobody can reach. bhop_pandora2_fix spawned every player inside its first pit
## because the importer thickened a 16-unit plane 48 units under the start room into a
## 192-unit slab reaching up through the floor; `tools/bsp_import.py` `inflate_pit` is the
## fix and this is the check that fails without it. `_test_stands_where_it_sends_you`
## could not see it: it teleports a bot to each arrival and measures how far it FELL,
## and a bot the pit put back at a higher spawn has fallen a negative distance.
func _test_arrivals_miss_the_pits() -> void:
	_section("arrivals")
	var zones := game.timers.zones
	var inside := PackedStringArray()
	if zones != null:
		var pits := zones.of_kind(DotTimerZone.Kind.RESPAWN)
		for zone: DotTimerZone in zones.zones:
			var label := ""
			match zone.kind:
				DotTimerZone.Kind.SPAWN:
					label = "%s spawn" % DotTimerTrack.short_name_of(zone.track)
				DotTimerZone.Kind.STAGE:
					label = "stage %d" % int(zone.number)
				DotTimerZone.Kind.TELEPORT:
					label = "door"
				_:
					continue
			for pit: DotTimerZone in pits:
				if pit.track == zone.track and pit.contains(zone.destination):
					if not inside.has(label):
						inside.append(label)
					break
	var known: Array = ARRIVES_IN_PIT.get(String(_map_id), [])
	if known.is_empty():
		_check(inside.is_empty(), "no spawn, stage or door puts a player inside a pit",
			", ".join(inside))
	else:
		# Both ways: the listed ones still do, and nothing else does.
		var listed := PackedStringArray(known)
		_check(inside == listed,
			"lands in a pit exactly where ARRIVES_IN_PIT says it does",
			"listed %s, found %s" % [str(listed), str(inside)])
	_done()


## Walking through one of the map's doors does not end the run.
##
## [b]`doorways` in a map's zone file exists so that a door is a TELEPORT, which keeps
## the run, rather than a RESPAWN, which ends it -- and the game's handler for TELEPORT
## called `G2GPlayer.teleport`, which ends it.[/b] So every door the importer ever
## made ended the run anyway, on surf_kitsune (the map the rule was written for), on
## bhop_interloper's three parts, on bhop_badges_mini's hundred and eighty sections. The
## zone list was exactly right and the only symptom was a timer that stopped at the
## first door. Driven through the real handler: the manager's signal, which is what the
## timer emits when a player walks in.
func _test_a_door_keeps_the_run() -> void:
	_section("doors")
	var zones := game.timers.zones
	var door: DotTimerZone = null
	var start: DotTimerZone = null
	if zones != null:
		door = zones.first_of_kind(DotTimerZone.Kind.TELEPORT, DotTimerTrack.MAIN)
		start = zones.first_of_kind(DotTimerZone.Kind.START, DotTimerTrack.MAIN)
	if door == null or start == null:
		_check(true, "a door keeps the run", "no door on the main track")
		_done()
		return

	var bot: G2GPlayer = game.players.get(&"bot")
	if bot == null:
		bot = game.add_player(&"bot", "Bot", true)
		bot.sampler = null
	var timer := bot.timer
	if timer == null:
		_check(false, "a door keeps the run", "the bot has no timer")
		return
	timer.stop()

	# Leave the start line, so there is a run to lose. Synchronously, inside one frame,
	# so the game's own tick cannot feed the timer the bot's real position in between.
	var sample := DotTimerSample.new()
	sample.grounded = true
	var away := start.centre() + Vector3(0.0, start.size().y + 8.0, 0.0)
	for point in [start.centre(), start.centre(), away]:
		sample.previous_position = sample.position
		sample.position = point
		timer.tick(sample)
	var was_running := timer.run.is_running()

	game.timers.effect_requested.emit(&"bot", door)

	var moved := bot.global_position.distance_to(door.destination) < 0.01
	_check(was_running and moved and timer.run.is_running(), "a door keeps the run",
		"running before %s, moved %s, running after %s"
		% [was_running, moved, timer.run.is_running()])
	timer.stop()
	_done()


## Longest a route may take, in simulated seconds, before the bot is said not to finish.
const ROUTE_SECONDS := 300.0


## A bot runs the map from its main spawn to its finish, on the imported collision,
## following the route written down for it in `maps/routes/<id>.json` (`g2g-maps-1`).
##
## [b]Every other section here asks about a place; this one asks about the whole way.[/b]
## `_test_runnable` drives a timer over the zones, `_test_stands_where_it_sends_you` drops
## a player at each arrival, and a map can pass all of it with a block missing, a gap
## nobody can clear, or a solid that is not where it is drawn. A run that starts in the
## start zone, crosses everything in between and is timed by the finish -- the timer the
## game itself feeds, with no put-back by a pit on the way -- is the one check that a
## block moved or a brush lost fails. A map with no route file says so and passes: a
## route is data written per map (`tools/route_plan.py`), and most maps do not have one
## yet. See route_bot.gd for how the bot drives it.
func _test_runs_its_route() -> void:
	_section("route")
	var why: Array = []
	var points := RouteBot.load_points(_map_id, why)
	var zones := game.timers.zones if game != null else null
	var finish: DotTimerZone = null
	if zones != null:
		for zone: DotTimerZone in zones.of_kind(DotTimerZone.Kind.END):
			if zone.track == DotTimerTrack.MAIN:
				finish = zone
	if points.is_empty():
		_check(true, "a bot runs it start to finish on its route", why[0] if not why.is_empty() else "no route")
		_done()
		return
	if finish == null:
		_check(false, "a bot runs it start to finish on its route", "it has a route and no finish")
		_done()
		return

	var bot: G2GPlayer = game.players.get(&"bot")
	if bot == null:
		bot = game.add_player(&"bot", "Bot", true)
		bot.sampler = null
	var node := game.current_map_node()
	var router := RouteBot.new(points, finish.centre())
	var put_back: Array[String] = []
	var finished: Array[float] = []
	var on_effect := func(pid: StringName, zone: DotTimerZone) -> void:
		if pid != &"bot":
			return
		match zone.kind:
			DotTimerZone.Kind.RESPAWN, DotTimerZone.Kind.SLAY:
				if put_back.is_empty():
					put_back.append(str(G2GUnits.vector_to_units(bot.global_position).round()))
			DotTimerZone.Kind.TELEPORT:
				router.teleported.call_deferred()
	var on_finish := func(run: DotTimerRun) -> void:
		finished.append(run.time())
	game.timers.effect_requested.connect(on_effect)
	bot.timer.run_finished.connect(on_finish)
	bot.timer.stop()
	bot.teleport(node.spawn_for(DotTimerTrack.MAIN), node.spawn_yaw_for(DotTimerTrack.MAIN))
	await get_tree().physics_frame

	var delta := 1.0 / float(game.tick_rate)
	var space := node.get_world_3d().direct_space_state
	var ticks := int(ROUTE_SECONDS * float(game.tick_rate))
	var t := 0
	while t < ticks and finished.is_empty() and put_back.is_empty():
		bot.controller.apply_command(router.command(bot.controller.state, space, bot.controller.tunables, delta))
		await get_tree().physics_frame
		t += 1
	game.timers.effect_requested.disconnect(on_effect)
	bot.timer.run_finished.disconnect(on_finish)

	var at := str(G2GUnits.vector_to_units(bot.controller.state.position).round())
	if not finished.is_empty():
		print("        finished in %.2f s over %d points, %d ticks surfing" % [finished[0], points.size(), router.surfed])
	_check(not finished.is_empty() and put_back.is_empty(), "a bot runs it start to finish on its route",
		("finished in %.2f s over %d points" % [finished[0], points.size()]) if not finished.is_empty()
		else ("put back by a pit (sent to %s u), aiming at point %d of %d" % [put_back[0], router.index + 1, points.size()])
			if not put_back.is_empty()
		else ("not finished after %.0f s at %s u, aiming at point %d of %d" % [ROUTE_SECONDS, at, router.index + 1, points.size()]))
	bot.timer.stop()
	_done()

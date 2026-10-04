extends RefCounted

const G2GPaths := preload("g2g_paths.gd")

## Kenney stand-ins for the stock materials an imported map's .bsp did not carry.
##
## A .bsp packs only what its mapper added; everything from the source game's own
## archives arrives as a name and a measured colour, and was drawn in the tinted
## prototype grid -- all of bhop_aztec, 97% of surf_beginner2. Christian's rule
## (`[g2g-maps-stock-1]`): the map's own texture if it shipped, else a Kenney texture
## (CC0, `textures/stock/`), else the grid. **Never the source game's textures.**
##
## [b]Applied when a map is built, not when it is imported[/b], so a pack already on the
## CDN gets it from the game pack with no republish: its prototype surfaces already
## carry world-placed UVs and the mapper's measured colour, which is all a stand-in
## needs. The table is `textures/stock/substitutes.json`, first match wins.

const TABLE := "res://textures/stock/substitutes.json"
const STOCK_DIR := "res://textures/stock"

## How far a stand-in is pulled toward the colour the map measured for the original.
## 0 draws Kenney's own colours; 1 makes its average exactly the mapper's, which on a
## dark rock face multiplies a dark texture into black. Chosen by rendering.
const TINT_PULL := 0.6

static var _entries: Array = []
static var _loaded := false


## The entry for [param material], or an empty dictionary when nothing stands in.
## `{texture: res path, units: tile size in Source units, mean: Color, why}`.
static func for_material(material: String) -> Dictionary:
	_load()
	var name := material.to_lower()
	for entry: Dictionary in _entries:
		if not name.match(str(entry.get("match", ""))):
			continue
		if bool(entry.get("none", false)) or not entry.has("texture"):
			return {}
		return entry
	return {}


## The tint that pulls [param entry]'s texture toward [param measured], the map's own
## average colour for the original.
static func tint_for(entry: Dictionary, measured: Color) -> Color:
	var mean: Array = entry.get("mean", [1.0, 1.0, 1.0])
	var out := Color.WHITE
	for i in range(3):
		var want: float = measured[i] / maxf(float(mean[i]), 0.02)
		out[i] = clampf(lerpf(1.0, want, TINT_PULL), 0.3, 2.5)
	return out


static func texture_path(entry: Dictionary) -> String:
	return STOCK_DIR.path_join(str(entry.get("texture", "")))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(G2GPaths.rebase(TABLE))
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if parsed is Dictionary:
		_entries = (parsed as Dictionary).get("entries", [])
	else:
		DotLog.warn("g2g.bsp", "no stock substitutes table; imported maps keep the grid",
			{"path": TABLE})

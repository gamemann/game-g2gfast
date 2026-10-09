extends RefCounted

## The maps a server rotates, read from a file an operator edits: `cfg/map_rotation.yml`.
##
## [b]A rotation is not the catalogue.[/b] The catalogue is every map on the disk (or
## fetched) and the rotation is the ones a server PLAYS; an operator keeping forty maps
## installed and rotating twelve should not have to delete twenty-eight to say so. A map
## the file does not list stays installed, loadable by `map <id>` and shown in the map
## list (marked "not in rotation"); it is only left out of the rotation, the vote and
## nominations.
##
## Five spellings, because operators arrive from servers that used each:
##
## [codeblock]
## # map_rotation.yml / .yaml       # map_rotation.json
## maps:                           {"maps": ["bhop_eazy", "surf_mesa"]}
##   - bhop_eazy                   ["bhop_eazy", "surf_mesa"]
##   - surf_mesa
## # map_rotation.txt / .cfg / .ini -- one id per line, the old mapcycle shape;
## # `#`, `//` and `;` start a comment, an [ini] section header is ignored, and
## # `map = surf_mesa` or `surf_mesa = 1` read as the id.
## [/codeblock]
##
## A YAML file may also be a bare list (`- bhop_eazy`). Anything else in a YAML file
## (`mode:`, `cooldown:`) is read as a setting beside the list: see [method load_file].

const CHANNEL := "g2g.maps"

## The extensions tried, in order, when the configured path has none.
const EXTENSIONS := ["yml", "yaml", "json", "txt", "cfg", "ini"]


## Where a path given as [param stem] (no extension, or with one) actually is, or "".
##
## A relative path is looked for beside the project (where `cfg/` is when a server runs
## from its own directory), in `user://`, and beside the executable (an exported server).
static func find(stem: String) -> String:
	if stem.strip_edges().is_empty():
		return ""
	var candidates := PackedStringArray()
	var bases := PackedStringArray([""])
	if stem.is_relative_path() and not stem.begins_with("res://") and not stem.begins_with("user://"):
		bases = PackedStringArray(["res://", "user://", OS.get_executable_path().get_base_dir() + "/"])
	var names := PackedStringArray([stem]) if stem.get_extension() != "" \
		else PackedStringArray(EXTENSIONS.map(func(e: String) -> String: return "%s.%s" % [stem, e]))
	for base in bases:
		for n in names:
			candidates.append(base + n)
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


## Reads a rotation file. The value is `{"maps": PackedStringArray, "settings": Dictionary}`.
static func load_file(path: String) -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "No map rotation file at %s" % path)
	var text := FileAccess.get_file_as_string(path)
	match path.get_extension().to_lower():
		"json":
			return parse_json(text, path)
		"yml", "yaml":
			return parse_yaml(text, path)
		_:
			return parse_lines(text)


static func parse_json(text: String, path: String = "") -> DotResult:
	var parsed: Variant = JSON.parse_string(text)
	var list: Variant = parsed
	var settings := {}
	if parsed is Dictionary:
		list = (parsed as Dictionary).get("maps", null)
		for key: Variant in parsed:
			if str(key) != "maps":
				settings[str(key)] = parsed[key]
	if not (list is Array):
		return DotResult.fail(DotError.CODE_PARSE,
			"%s must be a list of map ids, or an object with a \"maps\" list" % path)
	return DotResult.success({"maps": _ids(list as Array), "settings": settings})


## The YAML a rotation needs and nothing more: a `maps:` key with a block or flow list
## under it, or a bare list, plus `key: value` scalars beside it. Not a YAML parser, and
## it says so: a line it cannot read stops the load with the line number rather than
## being guessed at.
static func parse_yaml(text: String, path: String = "") -> DotResult:
	var maps: Array = []
	var settings := {}
	var in_list := true
	var n := 0
	for raw in text.split("\n"):
		n += 1
		var line := _strip_comment(raw, "#").strip_edges(false, true)
		if line.strip_edges().is_empty() or line.strip_edges() == "---":
			continue
		var t := line.strip_edges()
		if t.begins_with("- "):
			if in_list:
				maps.append(_unquote(t.substr(2)))
			continue
		var colon := t.find(":")
		if colon < 0:
			return DotResult.fail(DotError.CODE_PARSE, "%s line %d: expected `key: value` or `- map_id`" % [path, n])
		var key := t.substr(0, colon).strip_edges()
		var value := t.substr(colon + 1).strip_edges()
		if key == "maps":
			in_list = true
			if value.begins_with("[") and value.ends_with("]"):
				for part in value.substr(1, value.length() - 2).split(","):
					if not part.strip_edges().is_empty():
						maps.append(_unquote(part.strip_edges()))
			elif not value.is_empty():
				return DotResult.fail(DotError.CODE_PARSE, "%s line %d: `maps:` takes a list" % [path, n])
			continue
		in_list = false
		settings[key] = _unquote(value)
	return DotResult.success({"maps": _ids(maps), "settings": settings})


## One id per line: mapcycle.txt, a .cfg, an .ini.
static func parse_lines(text: String) -> DotResult:
	var maps: Array = []
	for raw in text.split("\n"):
		var line := _strip_comment(_strip_comment(_strip_comment(raw, "#"), "//"), ";").strip_edges()
		if line.is_empty() or (line.begins_with("[") and line.ends_with("]")):
			continue
		var eq := line.find("=")
		if eq >= 0:
			var left := line.substr(0, eq).strip_edges()
			var right := line.substr(eq + 1).strip_edges()
			# `map = surf_mesa` names the id on the right; `surf_mesa = 1` on the left.
			line = right if left.to_lower() in ["map", "maps", "mapname"] else left
		for word in line.split(" ", false):
			maps.append(_unquote(word))
	return DotResult.success({"maps": _ids(maps), "settings": {}})


static func _ids(list: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for v: Variant in list:
		var id := str(v).strip_edges().to_lower()
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


static func _strip_comment(line: String, marker: String) -> String:
	var at := line.find(marker)
	return line if at < 0 else line.substr(0, at)


static func _unquote(s: String) -> String:
	s = s.strip_edges()
	if s.length() >= 2 and ((s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'"))):
		return s.substr(1, s.length() - 2)
	return s

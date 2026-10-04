extends SceneTree

## Publish imported maps as signed packs, each under an owner: `<owner>/<map id>`.
##
##     tools/publish_maps.sh --owner gamemann --key ../dot-server-deploy/keys/content.key
##     tools/publish_maps.sh --owner gamemann --key <pem> surf_mesa bhop_eazy
##
## Writes `<out>/<owner>/<id>/manifest.json` and `objects/` beside it -- the version-less
## layout a server's `ensure(id)` looks for and the one the content origin already serves
## the unowned map packs in -- so the output directory is uploaded to the origin's
## `content/` as it stands. A server fetches them with `sv_map_content_owner <owner>`
## (see [member G2GConfig.map_content_owner]); the map id a player types is unchanged.
##
## [b]Signed with dot-server-deploy's key, not the site's.[/b] A map is not an asset on
## the site, so the site cannot publish it, and the key every client already trusts under
## `default` is the one that signed the unowned map packs. `--key-id` defaults to that.
##
## Exit codes: 0 every map published, 1 called wrong, 2 at least one failed.

const G2GMapCatalogue := preload("../game/g2g_map_catalogue.gd")

const IMPORTED := "res://maps/imported"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var owner := ""
	var key_path := ""
	var key_id := "default"
	var out := "dist/maps"
	# Empty: each map's own `G2GMapCatalogue.pack_version`, from its files. `--version`
	# still forces one for every map named, for a release that wants a number.
	var version := ""
	var ids: PackedStringArray = []
	var i := 0
	while i < args.size():
		var a := args[i]
		var next := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--owner": owner = next; i += 1
			"--key": key_path = next; i += 1
			"--key-id": key_id = next; i += 1
			"--out": out = next; i += 1
			"--version": version = next; i += 1
			_: ids.append(a)
		i += 1

	# An owner is a path segment in every client that mounts the pack; the same rule the
	# site applies to a username, checked here so a typo fails before anything is signed.
	if owner.is_empty() or not owner.to_lower() == owner or owner.contains("/") \
			or DotPaths.slugify(owner) != owner:
		printerr("--owner must be a lowercase name the site would give a pack, e.g. gamemann")
		quit(1)
		return
	if key_path.is_empty() or not FileAccess.file_exists(key_path):
		printerr("--key names the private key PEM that signs the packs")
		quit(1)
		return

	if ids.is_empty():
		for d in DirAccess.get_directories_at(IMPORTED):
			if FileAccess.file_exists("%s/%s/%s.json" % [IMPORTED, d, d]):
				ids.append(d)

	var pem := FileAccess.get_file_as_string(key_path)
	var failed := 0

	for id in ids:
		var source := "%s/%s" % [IMPORTED, id]
		if not FileAccess.file_exists("%s/%s.json" % [source, id]):
			printerr("%s: not an imported map (no %s/%s.json)" % [id, source, id])
			failed += 1
			continue

		var pub := DotCloudPublisher.new()
		pub.content_id = "%s/%s" % [owner, id]
		pub.version = version if not version.is_empty() else G2GMapCatalogue.pack_version(source)
		pub.display_name = id
		pub.signing_key_pem = pem
		pub.signing_key_id = key_id

		var res := pub.publish(source, "%s/%s/%s" % [out, owner, id])
		if res.ok:
			print("published %s/%s@%s" % [owner, id, pub.version])
		else:
			printerr("%s: %s" % [id, res.error])
			failed += 1

	print("%d published, %d failed, into %s" % [ids.size() - failed, failed, out])
	quit(2 if failed > 0 else 0)

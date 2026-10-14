class_name ModLoadPlan
extends RefCounted
## The result of [method ModLoader.resolve]: the load order (base first) and every rejection.

var game_version: String = ""
## Applied mods in load order, base first.
var order: Array[ModManifest] = []
## First rejection reason per rejected mod id.
var rejected: Dictionary[StringName, ModIssue] = {}
var issues: Array[ModIssue] = []


## Returns the ids of [member order], base first.
func load_order_ids() -> PackedStringArray:
	var ids: Array[String] = []
	for manifest: ModManifest in order:
		ids.append(String(manifest.id))
	return PackedStringArray(ids)


## Returns the SHA-256 (lowercase hex) of the [code]"<id>@<version>"[/code] lines of the load
## order joined with [code]"\n"[/code]; base is [code]base@<game_version>[/code]. Replay headers
## store it.
func mod_set_hash() -> String:
	var lines: Array[String] = []
	for manifest: ModManifest in order:
		var version: String = manifest.version_text
		if manifest.source == ModManifest.Source.BASE:
			version = game_version
		lines.append("%s@%s" % [manifest.id, version])
	return hash_lines(PackedStringArray(lines))


## Returns the lowercase hex SHA-256 of [param lines] joined with [code]"\n"[/code] (UTF-8).
static func hash_lines(lines: PackedStringArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		push_error("cannot start SHA-256")
		return ""
	if context.update("\n".join(lines).to_utf8_buffer()) != OK:
		push_error("cannot hash the mod set")
		return ""
	return context.finish().hex_encode()

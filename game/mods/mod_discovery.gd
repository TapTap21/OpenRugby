class_name ModDiscovery
extends RefCounted
## Finds mod manifests in search roots and mounts user [code].pck[/code] mods (internal helper
## of [ModLoader]).
##
## A pack must contain its mod at [code]res://mods/<id>/[/code]; it is mounted with
## [code]ProjectSettings.load_resource_pack(path, false)[/code], which never replaces existing
## files. Godot cannot unmount a pack, so mounted packs are remembered for the whole process and a
## second discovery reuses them instead of reporting them as empty.

const PACK_MOD_ROOT: String = "res://mods"

## Mod folders each mounted pack added, keyed by pack path. Process-wide (packs stay mounted).
static var _mounted_packs: Dictionary[String, PackedStringArray] = {}

## Discovery problems that belong to no manifest ([code]manifest_missing[/code],
## [code]pck_mount_failed[/code], [code]pck_no_mod[/code]).
var issues: Array[ModIssue] = []


## Returns every manifest found under [param roots] (valid or not, base excluded), in discovery
## order, with duplicate ids flagged on the later manifests.
func discover(roots: PackedStringArray) -> Array[ModManifest]:
	issues.clear()
	var pack_manifests: Array[ModManifest] = []
	var pack_roots: Dictionary[String, bool] = {}
	for root: String in roots:
		if root.begins_with("user://") and DirAccess.dir_exists_absolute(root):
			_mount_packs(root, pack_manifests, pack_roots)
	# Folders any pack added (also in earlier discoveries) are pack mods, never builtin ones.
	for added: PackedStringArray in _mounted_packs.values():
		for mod_id: String in added:
			pack_roots[PACK_MOD_ROOT.path_join(mod_id)] = true
	var manifests: Array[ModManifest] = []
	for root: String in roots:
		_scan_root(root, pack_roots, manifests)
	manifests.append_array(pack_manifests)
	_flag_duplicates(manifests)
	return manifests


func _mount_packs(
	root: String, out: Array[ModManifest], pack_roots: Dictionary[String, bool]
) -> void:
	var files: Array[String] = []
	for file_name: String in DirAccess.get_files_at(root):
		if file_name.get_extension().to_lower() == "pck":
			files.append(file_name)
	files.sort()
	for file_name: String in files:
		var pck_path: String = root.path_join(file_name)
		var mod_ids: PackedStringArray = _mount(pck_path)
		for mod_id: String in mod_ids:
			var mod_root: String = PACK_MOD_ROOT.path_join(mod_id)
			pack_roots[mod_root] = true
			var manifest: ModManifest = ModManifest.load_file(mod_root, ModManifest.Source.USER_PCK)
			manifest.pck_path = pck_path
			out.append(manifest)


## Mounts [param pck_path] (once per process) and returns the mod folders it added.
func _mount(pck_path: String) -> PackedStringArray:
	var pack_id: StringName = StringName(pck_path.get_file().get_basename())
	if _mounted_packs.has(pck_path):
		return _mounted_packs[pck_path]
	var before: PackedStringArray = _pack_root_dirs()
	if not ProjectSettings.load_resource_pack(pck_path, false):
		issues.append(ModIssue.error(&"pck_mount_failed", pack_id, "cannot mount %s" % pck_path))
		return PackedStringArray()
	var new_dirs: Array[String] = []
	for dir_name: String in _pack_root_dirs():
		if not before.has(dir_name):
			new_dirs.append(dir_name)
	new_dirs.sort()
	var added: PackedStringArray = PackedStringArray(new_dirs)
	_mounted_packs[pck_path] = added
	if added.is_empty():
		issues.append(
			ModIssue.error(
				&"pck_no_mod",
				pack_id,
				(
					"%s adds no new folder under %s/ (duplicate id or wrong layout)"
					% [pck_path, PACK_MOD_ROOT]
				)
			)
		)
	return added


func _scan_root(
	root: String, pack_roots: Dictionary[String, bool], out: Array[ModManifest]
) -> void:
	if not DirAccess.dir_exists_absolute(root):
		return
	var source: ModManifest.Source = ModManifest.Source.USER_FOLDER
	if root.begins_with("res://"):
		source = ModManifest.Source.BUILTIN
	var dir_names: Array[String] = []
	for dir_name: String in DirAccess.get_directories_at(root):
		dir_names.append(dir_name)
	dir_names.sort()
	for dir_name: String in dir_names:
		var mod_root: String = root.path_join(dir_name)
		if pack_roots.has(mod_root):
			continue
		if FileAccess.file_exists(mod_root.path_join(ModManifest.MANIFEST_FILE)):
			out.append(ModManifest.load_file(mod_root, source))
		else:
			issues.append(
				ModIssue.warning(
					&"manifest_missing",
					StringName(dir_name),
					"%s has no %s" % [mod_root, ModManifest.MANIFEST_FILE]
				)
			)


static func _pack_root_dirs() -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(PACK_MOD_ROOT):
		return PackedStringArray()
	return DirAccess.get_directories_at(PACK_MOD_ROOT)


static func _flag_duplicates(manifests: Array[ModManifest]) -> void:
	var first_root: Dictionary[StringName, String] = {}
	for manifest: ModManifest in manifests:
		if first_root.has(manifest.id):
			manifest.issues.append(
				ModIssue.error(
					&"duplicate_id",
					manifest.id,
					(
						"'%s' at %s is already provided by %s"
						% [manifest.id, manifest.root_path, first_root[manifest.id]]
					)
				)
			)
		else:
			first_root[manifest.id] = manifest.root_path

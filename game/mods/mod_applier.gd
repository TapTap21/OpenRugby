class_name ModApplier
extends RefCounted
## Applies a [ModLoadPlan] to a new [ModRuntime] in three layers (internal helper of
## [ModLoader]): the asset map first (so resource paths in patches resolve through it), then
## data patches, then entry scripts. Ends by emitting [code]EventBus.mods_loaded[/code].

const OVERRIDES_DIR: String = "overrides"
const DATA_DIR: String = "data"
## Target classes whose patching changes gameplay rules (needs capability [code]rules[/code]).
const RULES_CLASSES: Array[StringName] = [&"RulesConfig", &"MatchFlowConfig"]


## Builds and returns the runtime for [param plan].
static func apply(plan: ModLoadPlan) -> ModRuntime:
	var runtime: ModRuntime = ModRuntime.new()
	runtime.game_version = plan.game_version
	runtime.mod_set_hash = plan.mod_set_hash()
	runtime.load_order = plan.load_order_ids()
	runtime.manifests = plan.order.duplicate()
	runtime.issues = plan.issues.duplicate()
	var mods: Array[ModManifest] = []
	for manifest: ModManifest in plan.order:
		if manifest.source != ModManifest.Source.BASE:
			mods.append(manifest)
	for manifest: ModManifest in mods:
		_map_assets(runtime, manifest)
	for manifest: ModManifest in mods:
		_apply_data(runtime, manifest)
	for manifest: ModManifest in mods:
		if manifest.is_script_mod():
			_run_entry(runtime, manifest)
	runtime.activate()
	var emit_result: Error = EventBusAccess.emit(&"mods_loaded", [runtime.mod_set_hash])
	if emit_result != OK and emit_result != ERR_UNAVAILABLE:
		push_warning("ModApplier: could not emit mods_loaded (%s)" % error_string(emit_result))
	return runtime


static func _map_assets(runtime: ModRuntime, manifest: ModManifest) -> void:
	var overrides: String = manifest.root_path.path_join(OVERRIDES_DIR)
	if not DirAccess.dir_exists_absolute(overrides):
		return
	if not manifest.has_capability(&"assets"):
		runtime.add_issue(
			ModIssue.warning(
				&"capability_missing",
				manifest.id,
				"'%s' has an overrides/ folder but no capability 'assets'; ignored" % manifest.id
			)
		)
		return
	var seen: Dictionary[String, bool] = {}
	for relative: String in _files_under(overrides, ""):
		if relative.ends_with(".uid"):
			continue
		var mapped: String = _logical_asset_path(relative)
		if seen.has(mapped):
			continue
		seen[mapped] = true
		runtime.map_asset("res://" + mapped, overrides.path_join(relative), manifest.id)


static func _logical_asset_path(relative: String) -> String:
	var logical_path: String = relative
	while logical_path.ends_with(".import") or logical_path.ends_with(".remap"):
		logical_path = logical_path.trim_suffix(".import").trim_suffix(".remap")
	return logical_path


## Returns every file below [param root] as a path relative to it, sorted, recursively.
static func _files_under(root: String, relative: String) -> Array[String]:
	var result: Array[String] = []
	var directory: String = root.path_join(relative) if not relative.is_empty() else root
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	for file_name: String in files:
		result.append(relative.path_join(file_name) if not relative.is_empty() else file_name)
	var folders: PackedStringArray = DirAccess.get_directories_at(directory)
	folders.sort()
	for folder: String in folders:
		var child: String = relative.path_join(folder) if not relative.is_empty() else folder
		result.append_array(_files_under(root, child))
	return result


static func _apply_data(runtime: ModRuntime, manifest: ModManifest) -> void:
	var data_dir: String = manifest.root_path.path_join(DATA_DIR)
	if not DirAccess.dir_exists_absolute(data_dir):
		return
	if not manifest.has_capability(&"data"):
		runtime.add_issue(
			ModIssue.warning(
				&"capability_missing",
				manifest.id,
				"'%s' has a data/ folder but no capability 'data'; ignored" % manifest.id
			)
		)
		return
	var files: Array[String] = []
	for file_name: String in DirAccess.get_files_at(data_dir):
		if file_name.get_extension().to_lower() == "json":
			files.append(file_name)
	files.sort()
	for file_name: String in files:
		_apply_patch_file(runtime, manifest, data_dir.path_join(file_name))


static func _apply_patch_file(runtime: ModRuntime, manifest: ModManifest, path: String) -> void:
	var json: JSON = JSON.new()
	var text: String = FileAccess.get_file_as_string(path)
	var problem: String = ""
	if text.is_empty() and FileAccess.get_open_error() != OK:
		problem = "cannot read the file"
	elif json.parse(text) != OK:
		problem = "line %d: %s" % [json.get_error_line(), json.get_error_message()]
	var root: Dictionary = json.data if json.data is Dictionary else {}
	if problem.is_empty() and not root.get("patches") is Array:
		problem = "the top level must be an object with a 'patches' array"
	if not problem.is_empty():
		runtime.add_issue(ModIssue.error(&"patch_parse_error", manifest.id, path + ": " + problem))
		return
	var patches: Array = root["patches"]
	for index: int in patches.size():
		_apply_patch_entry(runtime, manifest, "%s patch %d" % [path, index], patches[index])


static func _apply_patch_entry(
	runtime: ModRuntime, manifest: ModManifest, where: String, entry: Variant
) -> void:
	var patch: Dictionary = entry if entry is Dictionary else {}
	if not patch.get("target") is String or not patch.get("fields") is Dictionary:
		runtime.add_issue(
			ModIssue.error(
				&"patch_parse_error",
				manifest.id,
				where + ": each patch needs a 'target' string and a 'fields' object"
			)
		)
		return
	var target_path: String = patch["target"]
	var fields: Dictionary = patch["fields"]
	var target: Resource = runtime.load_resource(target_path)
	if target == null:
		runtime.add_issue(
			ModIssue.error(
				&"patch_target_missing", manifest.id, "%s: cannot load %s" % [where, target_path]
			)
		)
		return
	if _is_rules_resource(target) and not manifest.has_capability(&"rules"):
		runtime.add_issue(
			ModIssue.warning(
				&"capability_undeclared_rules",
				manifest.id,
				"%s: patches rules resource %s without capability 'rules'" % [where, target_path]
			)
		)
	for issue: ModIssue in runtime.patch(target, target_path, fields, manifest.id):
		runtime.add_issue(issue)


static func _is_rules_resource(target: Resource) -> bool:
	for global_name: StringName in RULES_CLASSES:
		if PatchValues.has_global_class(target, global_name):
			return true
	return false


static func _run_entry(runtime: ModRuntime, manifest: ModManifest) -> void:
	var path: String = manifest.root_path.path_join(manifest.entry_script)
	var script: GDScript = null
	if ResourceLoader.exists(path):
		script = ResourceLoader.load(path) as GDScript
	var instance: Variant = null
	if script != null and script.can_instantiate():
		instance = script.new()
	if not instance is ModEntry:
		if instance is Object and not instance is RefCounted:
			var object: Object = instance
			object.free()
		runtime.add_issue(
			ModIssue.error(
				&"entry_script_invalid",
				manifest.id,
				"%s does not load as a script extending ModEntry" % path
			)
		)
		return
	var entry: ModEntry = instance
	runtime.add_entry(manifest.id, entry)
	entry._mod_init(ModApi.new(runtime, manifest.id))

class_name ModLoader
extends RefCounted
## Discovers, resolves and applies mods (ADR-003, ADR-004 section 5).
##
## Not an autoload: [code]Main[/code] owns the loader and passes the resulting [ModRuntime] down.
## Base game data is "mod zero" and always loads first. See
## [code]docs/specs/S1-modloader.md[/code].

const DEFAULT_SEARCH_ROOTS: PackedStringArray = ["res://mods", "user://mods"]

## The game version mods are checked against.
var game_version: String = ""
var search_roots: PackedStringArray = PackedStringArray()
## Problems of the last [method discover] that belong to no manifest
## ([code]manifest_missing[/code], [code]pck_mount_failed[/code], [code]pck_no_mod[/code]).
var discovery_issues: Array[ModIssue] = []


## An empty [param p_game_version] means [code]application/config/version[/code].
func _init(
	p_game_version: String = "", p_search_roots: PackedStringArray = DEFAULT_SEARCH_ROOTS
) -> void:
	game_version = p_game_version
	if game_version.is_empty():
		game_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	search_roots = p_search_roots


## Mounts user packs and returns every manifest found in the search roots, valid or not (base
## excluded). Later manifests with an id already seen get a [code]duplicate_id[/code] error.
func discover() -> Array[ModManifest]:
	var discovery: ModDiscovery = ModDiscovery.new()
	var manifests: Array[ModManifest] = discovery.discover(search_roots)
	discovery_issues = discovery.issues
	return manifests


## Resolves [param enabled_ids] into a load order: base first, dependencies before dependents,
## ties by [code](load_priority, id)[/code]. Rejected mods are listed with their reason.
func resolve(manifests: Array[ModManifest], enabled_ids: PackedStringArray) -> ModLoadPlan:
	return ModResolver.new(game_version).resolve(manifests, enabled_ids)


## Applies [param plan]: asset map, data patches, entry scripts, then emits
## [code]EventBus.mods_loaded[/code].
func apply(plan: ModLoadPlan) -> ModRuntime:
	return ModApplier.apply(plan)


## Discovers, resolves and applies; the plan issues start with the discovery issues.
func load_mods(enabled_ids: PackedStringArray) -> ModRuntime:
	var manifests: Array[ModManifest] = discover()
	var plan: ModLoadPlan = resolve(manifests, enabled_ids)
	var all_issues: Array[ModIssue] = discovery_issues.duplicate()
	all_issues.append_array(plan.issues)
	plan.issues = all_issues
	return apply(plan)

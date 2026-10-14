class_name ModResolver
extends RefCounted
## Dependency resolution and load ordering for [ModLoader] (internal helper).
##
## Base always loads first. Enabled mods are checked (found, valid manifest, game version), then
## dependencies are checked until no new rejection appears, mods left in a dependency cycle are
## rejected, and the rest is ordered with Kahn's algorithm, picking the smallest
## [code](load_priority, id)[/code] among ready mods. The enabled list order has no effect.

const BASE_ID: StringName = &"base"

var _game_version_text: String = ""
var _game_version: ModVersion = null
var _by_id: Dictionary[StringName, ModManifest] = {}
var _enabled: Dictionary[StringName, bool] = {}
## Accepted mod ids, kept sorted so every pass is deterministic.
var _accepted: Array[StringName] = []
var _plan: ModLoadPlan = null


func _init(p_game_version: String) -> void:
	_game_version_text = p_game_version
	_game_version = ModVersion.parse(p_game_version)


## Resolves [param enabled_ids] against [param manifests] into a [ModLoadPlan].
func resolve(manifests: Array[ModManifest], enabled_ids: PackedStringArray) -> ModLoadPlan:
	_plan = ModLoadPlan.new()
	_plan.game_version = _game_version_text
	_plan.order.append(ModManifest.make_base(_game_version_text))
	for manifest: ModManifest in manifests:
		if manifest != null and not _by_id.has(manifest.id):
			_by_id[manifest.id] = manifest
	var sorted_ids: Array[StringName] = []
	for text: String in enabled_ids:
		var mod_id: StringName = StringName(text)
		if mod_id != BASE_ID and not _enabled.has(mod_id):
			_enabled[mod_id] = true
			sorted_ids.append(mod_id)
	sorted_ids.sort_custom(_id_less)
	for mod_id: StringName in sorted_ids:
		_check_enabled(mod_id)
	while true:
		_propagate_dependencies()
		var cycle: Array[StringName] = _cycle_members()
		if cycle.is_empty():
			break
		for mod_id: StringName in cycle:
			_reject(mod_id, &"dependency_cycle", "'%s' is part of a dependency cycle" % mod_id)
	_plan.order.append_array(_topological_order())
	return _plan


func _check_enabled(mod_id: StringName) -> void:
	var manifest: ModManifest = _by_id.get(mod_id)
	if manifest == null:
		_reject(mod_id, &"not_found", "enabled mod '%s' was not discovered" % mod_id)
	elif not manifest.is_valid():
		_reject(mod_id, &"invalid_manifest", "the manifest of '%s' has errors" % mod_id)
	elif not manifest.game_version.matches(_game_version):
		_reject(
			mod_id,
			&"game_version_mismatch",
			(
				"'%s' needs game version %s, the game is %s"
				% [mod_id, manifest.game_version_text, _game_version_text]
			)
		)
	else:
		_accepted.append(mod_id)


## Rejects accepted mods whose dependencies are missing or mismatched until nothing changes.
func _propagate_dependencies() -> void:
	var changed: bool = true
	while changed:
		changed = false
		for mod_id: StringName in _accepted.duplicate():
			var reason: ModIssue = _dependency_problem(_by_id[mod_id])
			if reason != null:
				_reject(mod_id, reason.code, reason.message)
				changed = true


func _dependency_problem(manifest: ModManifest) -> ModIssue:
	for dependency: ModDependency in manifest.dependencies:
		if dependency.id == BASE_ID:
			if not dependency.constraint.matches(_game_version):
				return _mismatch(manifest, dependency, _game_version_text)
			continue
		if _accepted.has(dependency.id):
			var target: ModManifest = _by_id[dependency.id]
			if not dependency.constraint.matches(target.version):
				return _mismatch(manifest, dependency, target.version_text)
			continue
		if dependency.optional:
			continue
		var state: String = "was rejected" if _enabled.has(dependency.id) else "is not enabled"
		return ModIssue.error(
			&"missing_dependency",
			manifest.id,
			"'%s' requires '%s', which %s" % [manifest.id, dependency.id, state]
		)
	return null


func _mismatch(manifest: ModManifest, dependency: ModDependency, found: String) -> ModIssue:
	return ModIssue.error(
		&"dependency_version_mismatch",
		manifest.id,
		(
			"'%s' requires '%s' %s, found %s"
			% [manifest.id, dependency.id, dependency.constraint_text, found]
		)
	)


## Returns the accepted mods that lie on a dependency cycle (sorted).
func _cycle_members() -> Array[StringName]:
	var members: Array[StringName] = []
	for mod_id: StringName in _accepted:
		if _reaches(mod_id, mod_id):
			members.append(mod_id)
	return members


## Returns true when [param target] is reachable from the dependencies of [param start].
func _reaches(start: StringName, target: StringName) -> bool:
	var visited: Dictionary[StringName, bool] = {}
	var stack: Array[StringName] = _active_dependencies(start)
	while not stack.is_empty():
		var current: StringName = stack.pop_back()
		if current == target:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		stack.append_array(_active_dependencies(current))
	return false


## Returns the accepted dependencies of [param mod_id] (required ones and accepted optional ones).
func _active_dependencies(mod_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var manifest: ModManifest = _by_id.get(mod_id)
	if manifest == null:
		return result
	for dependency: ModDependency in manifest.dependencies:
		if _accepted.has(dependency.id):
			result.append(dependency.id)
	return result


func _topological_order() -> Array[ModManifest]:
	var remaining: Dictionary[StringName, int] = {}
	for mod_id: StringName in _accepted:
		remaining[mod_id] = _active_dependencies(mod_id).size()
	var order: Array[ModManifest] = []
	while not remaining.is_empty():
		var best: ModManifest = null
		for mod_id: StringName in remaining:
			if remaining[mod_id] == 0 and (best == null or _ready_less(_by_id[mod_id], best)):
				best = _by_id[mod_id]
		if best == null:
			push_error("mod resolution left an unordered cycle")
			break
		order.append(best)
		var erased: bool = remaining.erase(best.id)
		assert(erased)
		for mod_id: StringName in remaining:
			if _active_dependencies(mod_id).has(best.id):
				remaining[mod_id] -= 1
	return order


func _reject(mod_id: StringName, code: StringName, message: String) -> void:
	_accepted.erase(mod_id)
	if _plan.rejected.has(mod_id):
		return
	var issue: ModIssue = ModIssue.error(code, mod_id, message)
	_plan.rejected[mod_id] = issue
	_plan.issues.append(issue)


static func _ready_less(left: ModManifest, right: ModManifest) -> bool:
	if left.load_priority != right.load_priority:
		return left.load_priority < right.load_priority
	return String(left.id) < String(right.id)


static func _id_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

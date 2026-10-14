class_name MatchReadinessReport
extends RefCounted
## Typed list of capabilities a composed match still needs before it can start.

enum Capability {
	MATCH_CONFIG,
	STADIUM_GEOMETRY,
	CONTACT_SOLVER,
	WIND_POLICY,
	BALL_INITIALIZATION,
	PLAYER_FATIGUE_INPUTS,
	RESTORABLE_DEPENDENCIES,
	REPLAY_SAFE_HOOKS,
	RESTORABLE_SYSTEMS,
}

var _blockers: Dictionary[Capability, PackedStringArray] = {}


## Adds a user-readable reason that [param capability] is unavailable.
func add_blocker(capability: Capability, detail: String) -> void:
	if not _blockers.has(capability):
		_blockers[capability] = PackedStringArray()
	_blockers[capability].append(detail)


## True when every required capability is available.
func is_ready() -> bool:
	return _blockers.is_empty()


## Returns unavailable capabilities in enum order.
func unavailable_capabilities() -> Array[Capability]:
	var capabilities: Array[Capability] = []
	for capability: Capability in _blockers:
		capabilities.append(capability)
	capabilities.sort()
	return capabilities


## Returns a copy of the reasons for one capability.
func details_for(capability: Capability) -> PackedStringArray:
	return _blockers.get(capability, PackedStringArray()).duplicate()


## Returns stable, user-facing readiness text.
func describe() -> PackedStringArray:
	var lines: PackedStringArray = []
	for capability: Capability in unavailable_capabilities():
		for detail: String in _blockers[capability]:
			lines.append("%s: %s" % [_capability_label(capability), detail])
	return lines


## Stable snapshot used by composition diagnostics.
func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for capability: Capability in unavailable_capabilities():
		result[capability] = Array(_blockers[capability])
	return result


func _capability_label(capability: Capability) -> String:
	var label: String = "Unknown match capability"
	match capability:
		Capability.MATCH_CONFIG:
			label = "Match setup"
		Capability.STADIUM_GEOMETRY:
			label = "Stadium contact geometry"
		Capability.CONTACT_SOLVER:
			label = "Ball contact solver"
		Capability.WIND_POLICY:
			label = "Wind policy"
		Capability.BALL_INITIALIZATION:
			label = "Ball initialization"
		Capability.PLAYER_FATIGUE_INPUTS:
			label = "Player and fatigue inputs"
		Capability.RESTORABLE_DEPENDENCIES:
			label = "Restorable simulation providers"
		Capability.REPLAY_SAFE_HOOKS:
			label = "Replay-safe extension hooks"
		Capability.RESTORABLE_SYSTEMS:
			label = "Restorable simulation systems"
	return label

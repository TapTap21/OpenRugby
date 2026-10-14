class_name BaseExtensionPoints
extends RefCounted
## The extension points the base game declares. Later slices add points here (rule hooks in S3,
## AI behaviours in S5, menu injection in S11).

## PROVIDER, args [code][config: MatchConfig][/code]; each hook returns a [code]SimSystem[/code]
## (or null). The match runner adds them after the base systems, in hook order.
const MATCH_SIM_SYSTEMS: StringName = &"match.sim_systems"
## FILTER, value [code]MatchFlowConfig[/code], args [code][config: MatchConfig][/code]; each hook
## returns the flow to use.
const MATCH_FLOW_CONFIG: StringName = &"match.flow_config"
const PHYSICS_BALL_CONTACT: StringName = &"physics.ball_contact"
const PHYSICS_KICK_LAUNCH: StringName = &"physics.kick_launch"
const PHYSICS_PASS_LAUNCH: StringName = &"physics.pass_launch"
const PHYSICS_CATCH_RESOLVE: StringName = &"physics.catch_resolve"
const PHYSICS_TACKLE_RESOLVE: StringName = &"physics.tackle_resolve"
const PHYSICS_FUMBLE_RESOLVE: StringName = &"physics.fumble_resolve"
const PHYSICS_BALL_SPILL: StringName = &"physics.ball_spill"
const PHYSICS_WIND_PROVIDER: StringName = &"physics.wind_provider"


## Declares every base point into [param points]. Points that already exist are left as they are.
static func declare_into(points: ExtensionPoints) -> void:
	_declare(
		points,
		MATCH_SIM_SYSTEMS,
		ExtensionPoints.Kind.PROVIDER,
		"Args [config: MatchConfig]; return a SimSystem (or null) to add after the base systems."
	)
	_declare(
		points,
		MATCH_FLOW_CONFIG,
		ExtensionPoints.Kind.FILTER,
		"Value MatchFlowConfig, args [config: MatchConfig]; return the flow to use."
	)
	_declare(
		points,
		PHYSICS_BALL_CONTACT,
		ExtensionPoints.Kind.FILTER,
		"Filter ContactResult response only."
	)
	_declare(
		points,
		PHYSICS_KICK_LAUNCH,
		ExtensionPoints.Kind.FILTER,
		"Filter KickLaunch after Classic draw sequence."
	)
	_declare(
		points,
		PHYSICS_PASS_LAUNCH,
		ExtensionPoints.Kind.FILTER,
		"Filter PassLaunch after caller draw sequence."
	)
	_declare(
		points,
		PHYSICS_CATCH_RESOLVE,
		ExtensionPoints.Kind.FILTER,
		"Filter CatchResult probability before roll."
	)
	_declare(
		points,
		PHYSICS_TACKLE_RESOLVE,
		ExtensionPoints.Kind.FILTER,
		"Filter TackleResult probability before roll."
	)
	_declare(
		points,
		PHYSICS_FUMBLE_RESOLVE,
		ExtensionPoints.Kind.FILTER,
		"Filter fumble probability before roll."
	)
	_declare(
		points,
		PHYSICS_BALL_SPILL,
		ExtensionPoints.Kind.FILTER,
		"Filter spill probability and velocity scale."
	)
	_declare(
		points,
		PHYSICS_WIND_PROVIDER,
		ExtensionPoints.Kind.PROVIDER,
		"Provide injected Vector3 wind in km/h."
	)


static func _declare(
	points: ExtensionPoints, point: StringName, kind: ExtensionPoints.Kind, description: String
) -> void:
	var result: Error = points.declare(point, kind, description)
	if result != OK and result != ERR_ALREADY_EXISTS:
		push_error("cannot declare extension point '%s': %s" % [point, error_string(result)])

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


static func _declare(
	points: ExtensionPoints, point: StringName, kind: ExtensionPoints.Kind, description: String
) -> void:
	var result: Error = points.declare(point, kind, description)
	if result != OK and result != ERR_ALREADY_EXISTS:
		push_error("cannot declare extension point '%s': %s" % [point, error_string(result)])

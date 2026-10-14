class_name S2PhysicsConfig
extends Resource
## Typed configuration for the same S2 systems in Classic and modded matches.

@export var ball: BallPhysicsParams
@export var locomotion: LocomotionParams
@export var tackle: TackleParams
@export var kicks: KickParams
@export var passes: PassParams
@export var catches: CatchParams
@export var surfaces: PitchSurfaceTable
## PROVISIONAL unresolved environment input; RE names/condition mapping remain unknown.
@export var pitch_condition: int = -1
@export var stadium_id: int = -1


static func create_classic() -> S2PhysicsConfig:
	var defaults: S2PhysicsConfig = (
		load("res://game/physics/resources/default_s2_physics.tres") as S2PhysicsConfig
	)
	if defaults == null:
		return S2PhysicsConfig.new()
	return defaults.duplicate(true) as S2PhysicsConfig


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if ball == null:
		errors += PackedStringArray(["S2 ball parameters are required"])
	else:
		errors.append_array(ball.validate())
	if locomotion == null:
		errors += PackedStringArray(["S2 locomotion parameters are required"])
	else:
		errors.append_array(locomotion.validate())
	if tackle == null:
		errors += PackedStringArray(["S2 tackle parameters are required"])
	else:
		errors.append_array(tackle.validate())
	if kicks == null or kicks.profiles.is_empty():
		errors += PackedStringArray(["S2 kick profiles are required"])
	else:
		errors.append_array(kicks.validate())
	if passes == null:
		errors += PackedStringArray(["S2 pass parameters are required"])
	if catches == null:
		errors += PackedStringArray(["S2 catch parameters are required"])
	if surfaces == null or surfaces.rows.size() != 6:
		errors += PackedStringArray(["S2 requires all six pitch surface rows"])
	return errors

class_name TackleResult
extends RefCounted
## Physical contact result for downstream S3; carries no legality/referee decision.

enum Outcome { NONE, TACKLE, BROKEN_TACKLE, CHARGE, HANDOFF, SIDESTEP, SPILL }
var outcome: Outcome = Outcome.NONE
var break_probability: float = NAN
var spill_probability: float = NAN
var broke_tackle: bool = false
var spilled_ball: bool = false
var ball_velocity_scale: float = 1.0
var spill_velocity_min: float = NAN
var spill_velocity_max: float = NAN
var unresolved: bool = false


func snapshot() -> Dictionary:
	return {
		"outcome": outcome,
		"break_probability": break_probability,
		"spill_probability": spill_probability,
		"broke_tackle": broke_tackle,
		"spilled_ball": spilled_ball,
		"ball_velocity_scale": ball_velocity_scale,
		"spill_velocity_min": spill_velocity_min,
		"spill_velocity_max": spill_velocity_max,
		"unresolved": unresolved
	}

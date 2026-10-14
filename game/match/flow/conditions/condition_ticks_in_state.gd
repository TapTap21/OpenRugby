class_name ConditionTicksInState
extends MatchCondition
## Met once the flow has spent at least [member ticks] ticks in the current state.

@export var ticks: int = 1


func is_met(sim: MatchSim) -> bool:
	return sim.flow.ticks_in_state >= ticks

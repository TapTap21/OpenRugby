class_name MatchStateMachine
extends RefCounted
## Runtime state of the match flow. Transition rules come from a [MatchFlowConfig].

var config: MatchFlowConfig
var current: StringName = &""
var ticks_in_state: int = 0


func _init(p_config: MatchFlowConfig) -> void:
	config = p_config
	current = p_config.initial_state


## Returns the first transition of the current state that fires, or null.
func find_transition(sim: MatchSim, triggers: Array[StringName]) -> MatchTransitionDef:
	var def: MatchStateDef = current_def()
	if def == null:
		return null
	for transition: MatchTransitionDef in def.transitions:
		if transition.trigger != &"" and not triggers.has(transition.trigger):
			continue
		if transition.condition != null and not transition.condition.is_met(sim):
			continue
		return transition
	return null


## Returns the definition of the current state.
func current_def() -> MatchStateDef:
	return config.get_state(current)

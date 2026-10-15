class_name MatchStateMachine
extends RefCounted
## Runtime state of the match flow. Transition rules come from a [MatchFlowConfig].

var config: MatchFlowConfig
var current: StringName = &""
var ticks_in_state: int = 0


func _init(p_config: MatchFlowConfig) -> void:
	config = p_config
	current = p_config.initial_state


## Returns the first eligible transition or a checked evaluation failure.
func evaluate_transition_checked(
	sim: MatchSim, triggers: Array[StringName]
) -> TransitionEvaluationResult:
	var def: MatchStateDef = current_def()
	if def == null:
		return TransitionEvaluationResult.new(false, null, ERR_INVALID_DATA)
	for transition: MatchTransitionDef in def.transitions:
		if transition == null:
			return TransitionEvaluationResult.new(false, null, ERR_INVALID_DATA)
		if transition.trigger != &"" and not triggers.has(transition.trigger):
			continue
		if transition.condition != null:
			var result: ConditionEvaluationResult = transition.condition.evaluate_checked(sim)
			if not _valid_condition_result(result):
				return TransitionEvaluationResult.new(false, null, ERR_INVALID_DATA)
			if not result.ok:
				return TransitionEvaluationResult.new(false, null, result.error)
			if not result.value:
				continue
		return TransitionEvaluationResult.new(true, transition, OK)
	return TransitionEvaluationResult.new(true, null, OK)


func _valid_condition_result(result: ConditionEvaluationResult) -> bool:
	return (
		result != null
		and (
			(result.ok and result.error == OK)
			or (not result.ok and not result.value and result.error != OK)
		)
	)


## Compatibility helper for callers that do not need checked failure details.
func find_transition(sim: MatchSim, triggers: Array[StringName]) -> MatchTransitionDef:
	var result: TransitionEvaluationResult = evaluate_transition_checked(sim, triggers)
	return result.transition if result.ok else null


## Returns the definition of the current state.
func current_def() -> MatchStateDef:
	return config.get_state(current)

class_name MatchFlowConfig
extends Resource
## Data description of the match flow state machine.

@export var initial_state: StringName = &"pre_match"
@export var states: Array[MatchStateDef] = []


## Returns the state with [param id], or null when absent.
func get_state(id: StringName) -> MatchStateDef:
	for state: MatchStateDef in states:
		if state != null and state.id == id:
			return state
	return null


## Returns one message per problem; empty when the flow is valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	var has_terminal: bool = false
	for state: MatchStateDef in states:
		if state == null:
			errors += PackedStringArray(["flow has a null state"])
			continue
		if state.id == &"":
			errors += PackedStringArray(["flow has a state with an empty id"])
		elif seen.has(state.id):
			errors += PackedStringArray(["flow has a duplicate state id '%s'" % state.id])
		seen[state.id] = true
		if state.terminal:
			has_terminal = true
	if get_state(initial_state) == null:
		errors += PackedStringArray(["initial state '%s' not found" % initial_state])
	for state: MatchStateDef in states:
		if state == null:
			continue
		for transition: MatchTransitionDef in state.transitions:
			if transition == null:
				errors += PackedStringArray(["state '%s' has a null transition" % state.id])
				continue
			if get_state(transition.to) == null:
				errors += PackedStringArray(
					["state '%s' transitions to unknown state '%s'" % [state.id, transition.to]]
				)
			if transition.trigger == &"" and transition.condition == null:
				errors += PackedStringArray(
					["state '%s' has a transition with no trigger and no condition" % state.id]
				)
	if not has_terminal:
		errors += PackedStringArray(["flow has no terminal state"])
	return errors

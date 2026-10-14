class_name TestMatchFlowConfig
extends GdUnitTestSuite
## Tests for the default match flow resource and MatchFlowConfig.validate (S1-core 2.6 to 2.8,
## criteria C-10 and C-11).

const DEFAULT_FLOW_PATH: String = "res://game/match/flow/default_match_flow.tres"


func _default_flow() -> MatchFlowConfig:
	var res: Resource = ResourceLoader.load(DEFAULT_FLOW_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as MatchFlowConfig


## Minimal valid flow: start --go--> finish, where finish is terminal.
func _valid_flow() -> MatchFlowConfig:
	var flow: MatchFlowConfig = MatchFlowConfig.new()
	flow.initial_state = &"start"
	var start_state: MatchStateDef = MatchStateDef.new()
	start_state.id = &"start"
	var transition: MatchTransitionDef = MatchTransitionDef.new()
	transition.to = &"finish"
	transition.trigger = &"go"
	@warning_ignore("return_value_discarded")
	start_state.transitions.append(transition)
	var finish_state: MatchStateDef = MatchStateDef.new()
	finish_state.id = &"finish"
	finish_state.terminal = true
	@warning_ignore("return_value_discarded")
	flow.states.append(start_state)
	@warning_ignore("return_value_discarded")
	flow.states.append(finish_state)
	return flow


## C-10: default_match_flow.tres loads, validates, and has the six states with the 2.8 flags.
func test_c10_default_flow_loads_and_matches_table() -> void:
	var flow: MatchFlowConfig = _default_flow()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(flow != null).is_true()
	if flow == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(flow.validate().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(String(flow.initial_state)).is_equal("pre_match")
	# id: [clock_runs, ends_period, terminal, transition count]
	var table: Dictionary = {
		"pre_match": [false, false, false, 1],
		"kick_off": [false, false, false, 2],
		"in_play": [true, false, false, 3],
		"stoppage": [true, false, false, 4],
		"half_time": [false, true, false, 1],
		"full_time": [false, true, true, 0],
	}
	var mismatches: Array[String] = []
	for id_text: String in table.keys():
		var state: MatchStateDef = flow.get_state(StringName(id_text))
		if state == null:
			@warning_ignore("return_value_discarded")
			mismatches.append("missing %s" % id_text)
			continue
		var row: Array = table[id_text]
		var clock_expected: bool = row[0]
		var ends_expected: bool = row[1]
		var terminal_expected: bool = row[2]
		var transitions_expected: int = row[3]
		if state.clock_runs != clock_expected or state.ends_period != ends_expected:
			@warning_ignore("return_value_discarded")
			mismatches.append("flags %s" % id_text)
		if state.terminal != terminal_expected:
			@warning_ignore("return_value_discarded")
			mismatches.append("terminal %s" % id_text)
		if state.transitions.size() != transitions_expected:
			@warning_ignore("return_value_discarded")
			mismatches.append("transitions %s" % id_text)
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(mismatches).is_empty()


## A valid hand-built flow has no validation errors (baseline for the C-11 cases).
func test_c11_baseline_valid_flow_has_no_errors() -> void:
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(_valid_flow().validate().size()).is_equal(0)


## C-11: an unknown transition target is reported.
func test_c11_unknown_transition_target_reported() -> void:
	var flow: MatchFlowConfig = _valid_flow()
	flow.states[0].transitions[0].to = &"nowhere"
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(flow.validate().size() > 0).is_true()


## C-11: a duplicate state id is reported.
func test_c11_duplicate_state_id_reported() -> void:
	var flow: MatchFlowConfig = _valid_flow()
	flow.states[1].id = &"start"
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(flow.validate().size() > 0).is_true()


## C-11: a missing initial state is reported.
func test_c11_missing_initial_state_reported() -> void:
	var flow: MatchFlowConfig = _valid_flow()
	flow.initial_state = &"missing"
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(flow.validate().size() > 0).is_true()


## C-11: a transition with neither trigger nor condition is reported.
func test_c11_transition_without_trigger_or_condition_reported() -> void:
	var flow: MatchFlowConfig = _valid_flow()
	flow.states[0].transitions[0].trigger = &""
	flow.states[0].transitions[0].condition = null
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(flow.validate().size() > 0).is_true()


## C-11: a flow with no terminal state is reported.
func test_c11_flow_without_terminal_state_reported() -> void:
	var flow: MatchFlowConfig = _valid_flow()
	flow.states[1].terminal = false
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(flow.validate().size() > 0).is_true()

class_name TestTickOutputs
extends GdUnitTestSuite
## Focused output value-container tests from the approved S1 public contract.


class _OutputRecord:
	extends RefCounted
	var id: StringName:
		get:
			return _id
	var payload: Dictionary:
		get:
			return _payload.duplicate(true)
	var _id: StringName
	var _payload: Dictionary

	func _init(p_id: StringName, p_payload: Dictionary = {}) -> void:
		_id = p_id
		_payload = p_payload.duplicate(true)

	func detached_copy() -> RefCounted:
		return _OutputRecord.new(_id, _payload)


class _OutputSystem:
	extends SimSystem
	var participant_id: String
	var produced: Array[RefCounted]
	var should_fail: bool = false

	func _init(
		p_participant_id: String, p_produced: Array[RefCounted], p_should_fail: bool = false
	) -> void:
		participant_id = p_participant_id
		produced = p_produced
		should_fail = p_should_fail

	func setup(_sim: MatchSim) -> SetupResult:
		var claim: ParticipantClaim = ParticipantClaim.new(
			participant_id, "1", "output-test", "initial"
		)
		return SetupResult.new(true, OK, TransactionCapability.EXPLICITLY_STATELESS, claim, [])

	func tick_checked(_sim: MatchSim, _context: SimTickContext) -> SystemTickResult:
		if should_fail:
			var no_outputs: Array[RefCounted] = []
			return SystemTickResult.new(false, ERR_INVALID_DATA, no_outputs)
		return SystemTickResult.new(true, OK, produced)


func _frame() -> InputFrame:
	return InputFrame.new(1, 2)


func _assert_bool(condition: bool) -> void:
	@warning_ignore("unused_variable")
	var assertion: GdUnitBoolAssert = assert_bool(condition).is_true()


func _assert_int_equal(actual: int, expected: int) -> void:
	@warning_ignore("unused_variable")
	var assertion: GdUnitIntAssert = assert_int(actual).is_equal(expected)


func _assert_str_equal(actual: String, expected: String) -> void:
	@warning_ignore("unused_variable")
	var assertion: GdUnitStringAssert = assert_str(actual).is_equal(expected)


func _assert_dict_equal(actual: Dictionary, expected: Dictionary) -> void:
	@warning_ignore("unused_variable")
	var assertion: GdUnitDictionaryAssert = assert_dict(actual).is_equal(expected)


func _assert_record_value(record_ref: RefCounted, expected_id: StringName) -> void:
	if not (record_ref is _OutputRecord):
		_assert_bool(false)
		return
	var record: _OutputRecord = record_ref as _OutputRecord
	_assert_str_equal(String(record.id), String(expected_id))
	_assert_dict_equal(
		record.payload, {"value": String(expected_id), "nested": [String(expected_id)]}
	)


## SystemTickResult owns a typed, detached array and returns a detached array on every read.
func test_system_tick_result_detaches_typed_output_container() -> void:
	var first: RefCounted = _OutputRecord.new(&"first", {"value": "first", "nested": ["first"]})
	var second: RefCounted = _OutputRecord.new(&"second", {"value": "second", "nested": ["second"]})
	var source: Array[RefCounted] = [first, second]
	var result: SystemTickResult = SystemTickResult.new(true, OK, source)

	source.clear()
	var first_read: Array[RefCounted] = result.outputs
	_assert_int_equal(first_read.size(), 2)
	_assert_bool(first_read[0] != first)
	_assert_bool(first_read[1] != second)
	_assert_record_value(first_read[0], &"first")
	_assert_record_value(first_read[1], &"second")
	var first_output: RefCounted = first_read[0]
	if not (first_output is _OutputRecord):
		_assert_bool(false)
		return
	var first_record: _OutputRecord = first_output as _OutputRecord
	var detached_payload: Dictionary = first_record.payload
	var nested_value: Variant = detached_payload.get("nested")
	_assert_bool(nested_value is Array)
	if nested_value is Array:
		var detached_nested: Array = nested_value
		detached_nested.append("mutated")
	_assert_record_value(first_read[0], &"first")
	first_read.clear()
	var second_read: Array[RefCounted] = result.outputs
	_assert_int_equal(second_read.size(), 2)
	_assert_record_value(second_read[0], &"first")
	_assert_record_value(second_read[1], &"second")


## Successful producer outputs preserve registration order and each producer's local order.
func test_tick_result_aggregates_ordered_outputs_and_detaches_getter() -> void:
	var sim: MatchSim = MatchSim.new(MatchConfig.create_default())
	var a1: RefCounted = _OutputRecord.new(&"a1", {"value": "a1", "nested": ["a1"]})
	var a2: RefCounted = _OutputRecord.new(&"a2", {"value": "a2", "nested": ["a2"]})
	var b1: RefCounted = _OutputRecord.new(&"b1", {"value": "b1", "nested": ["b1"]})
	var first_outputs: Array[RefCounted] = [a1, a2]
	var second_outputs: Array[RefCounted] = [b1]
	var add_first: Error = sim.add_system(_OutputSystem.new("output-a", first_outputs))
	var add_second: Error = sim.add_system(_OutputSystem.new("output-b", second_outputs))
	_assert_int_equal(add_first, OK)
	_assert_int_equal(add_second, OK)

	var prepared: TickResult = sim.tick_checked(_frame(), DetachedCommandBundleBuilder.new().seal())
	_assert_int_equal(prepared.status, TickResult.Status.PREPARED)
	var prepared_outputs: Array[RefCounted] = prepared.outputs
	_assert_int_equal(prepared_outputs.size(), 3)
	_assert_bool(prepared_outputs[0] != a1)
	_assert_bool(prepared_outputs[1] != a2)
	_assert_bool(prepared_outputs[2] != b1)
	_assert_record_value(prepared_outputs[0], &"a1")
	_assert_record_value(prepared_outputs[1], &"a2")
	_assert_record_value(prepared_outputs[2], &"b1")
	_assert_int_equal(sim.finalize_standalone_tick(prepared.prepared_tick), OK)

	var result: TickResult = sim.tick(_frame())
	_assert_int_equal(result.status, TickResult.Status.COMMITTED)
	var first_read: Array[RefCounted] = result.outputs
	_assert_int_equal(first_read.size(), 3)
	_assert_bool(first_read[0] != a1)
	_assert_bool(first_read[1] != a2)
	_assert_bool(first_read[2] != b1)
	_assert_record_value(first_read[0], &"a1")
	_assert_record_value(first_read[1], &"a2")
	_assert_record_value(first_read[2], &"b1")
	first_read.clear()
	var second_read: Array[RefCounted] = result.outputs
	_assert_int_equal(second_read.size(), 3)
	_assert_record_value(second_read[0], &"a1")
	_assert_record_value(second_read[1], &"a2")
	_assert_record_value(second_read[2], &"b1")


## Failure outputs are discarded, and the failed tick publishes an empty output array.
func test_failed_system_and_failed_tick_expose_empty_outputs() -> void:
	var sim: MatchSim = MatchSim.new(MatchConfig.create_default())
	var earlier_output: RefCounted = _OutputRecord.new(
		&"earlier", {"value": "earlier", "nested": ["earlier"]}
	)
	var earlier: Array[RefCounted] = [earlier_output]
	var failing_outputs: Array[RefCounted] = []
	var add_earlier: Error = sim.add_system(_OutputSystem.new("output-earlier", earlier))
	var add_failing: Error = sim.add_system(
		_OutputSystem.new("output-failing", failing_outputs, true)
	)
	_assert_int_equal(add_earlier, OK)
	_assert_int_equal(add_failing, OK)

	var result: TickResult = sim.tick_checked(_frame(), DetachedCommandBundleBuilder.new().seal())
	_assert_int_equal(result.status, TickResult.Status.FAILED_RETRYABLE)
	_assert_bool(result.outputs.is_empty())

	var empty_failure_outputs: Array[RefCounted] = []
	var failure: SystemTickResult = SystemTickResult.new(
		false, ERR_INVALID_DATA, empty_failure_outputs
	)
	_assert_bool(failure.outputs.is_empty())
	_assert_bool(result.prepared_tick == null)

	var invalid_config: MatchConfig = MatchConfig.create_default()
	invalid_config.period_real_seconds = 0
	var invalid_sim: MatchSim = MatchSim.new(invalid_config)
	var no_op: TickResult = invalid_sim.tick(_frame())
	_assert_int_equal(no_op.status, TickResult.Status.NO_OP_INVALID)
	_assert_bool(no_op.outputs.is_empty())

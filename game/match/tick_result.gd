class_name TickResult
extends RefCounted
## Immutable public status and detached values from one checked tick attempt.

enum Status {
	PREPARED,
	COMMITTED,
	NO_OP_INVALID,
	NO_OP_FINISHED,
	NO_OP_STOPPED,
	FAILED_RETRYABLE,
	FATAL_ROLLBACK
}

var status: Status:
	get:
		return _status
var error: Error:
	get:
		return _error
var outcome: SimTickOutcome:
	get:
		return _outcome
var outputs: Array:
	get:
		return SystemTickResult._copy_records(_outputs)
var signal_batch: SignalBatch:
	get:
		return _signal_batch
var prepared_tick: PreparedTick:
	get:
		return _prepared_tick

var _status: Status
var _error: Error
var _outcome: SimTickOutcome
var _outputs: Array
var _signal_batch: SignalBatch
var _prepared_tick: PreparedTick


func _init(
	p_status: Status,
	p_error: Error,
	p_outcome: SimTickOutcome = null,
	p_outputs: Array = [],
	p_signal_batch: SignalBatch = null,
	p_prepared_tick: PreparedTick = null
) -> void:
	_status = p_status
	_error = p_error
	_outcome = p_outcome
	var typed_outputs: Array[RefCounted] = []
	for output: Variant in p_outputs:
		if not output is RefCounted:
			typed_outputs.clear()
			break
		typed_outputs.append(output as RefCounted)
	_outputs = SystemTickResult._copy_records(typed_outputs)
	_signal_batch = p_signal_batch if p_signal_batch != null else SignalBatch.new()
	_prepared_tick = p_prepared_tick

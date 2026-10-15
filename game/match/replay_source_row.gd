class_name ReplaySourceRow
extends RefCounted
## Detached, log-issued row snapshot; public construction produces an inert row.

var frame: InputFrame:
	get:
		return SimTickContext._copy_frame(_frame)
var command_records: Array[Dictionary]:
	get:
		return _copy_records(_command_records)
var output_records: Array[Dictionary]:
	get:
		return _copy_records(_output_records)

var _frame: InputFrame
var _command_records: Array[Dictionary] = []
var _output_records: Array[Dictionary] = []
var _issuer: InputLog
var _index: int = -1
var _generation: int = 0
var _identity: ReplayRowIdentity


func _init() -> void:
	pass


func _issue(
	issuer: InputLog,
	index: int,
	p_frame: InputFrame,
	commands: Array[Dictionary],
	outputs: Array[Dictionary],
	generation: int,
	identity: ReplayRowIdentity
) -> void:
	_issuer = issuer
	_index = index
	_frame = SimTickContext._copy_frame(p_frame)
	_command_records = _copy_records(commands)
	_output_records = _copy_records(outputs)
	_generation = generation
	_identity = identity


func _is_issued_by(issuer: InputLog, index: int, generation: int) -> bool:
	return (
		_issuer == issuer
		and _index == index
		and _generation == generation
		and issuer._is_row_current(
			index, generation, self, _identity, _frame, _command_records, _output_records
		)
	)


static func _copy_records(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		var copy: Variant = InputLog._copy_supported_value(record)
		if typeof(copy) != TYPE_DICTIONARY:
			return []
		result.append(copy)
	return result

class_name InputLog
extends RefCounted
## Recorded input frames plus a [ReplayHeader]; the tick of a frame is its index.

const FORMAT_VERSION: int = 1
const _MAGIC: PackedByteArray = [0x4F, 0x52, 0x4C, 0x47]

var header: ReplayHeader

var _buttons: PackedInt64Array = PackedInt64Array()
var _axes: PackedInt32Array = PackedInt32Array()
var _frame_count: int = 0
var _runtime_rows: Array[Dictionary] = []
var _reservation: Dictionary = {}
var _row_generations: Array[int] = []
var _next_generation: int = 1
var _issued_replay_rows: Array[Dictionary] = []


func _init(p_header: ReplayHeader) -> void:
	header = p_header


## Parses a log from [param bytes]; null when invalid or from a newer format.
static func from_bytes(bytes: PackedByteArray) -> InputLog:
	if bytes.size() <= _MAGIC.size() or bytes.slice(0, _MAGIC.size()) != _MAGIC:
		return null
	var raw: Variant = bytes_to_var(bytes.slice(_MAGIC.size()))
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if not d.has("header") or typeof(d["header"]) != TYPE_DICTIONARY:
		return null
	if not d.has("buttons") or typeof(d["buttons"]) != TYPE_PACKED_INT64_ARRAY:
		return null
	if not d.has("axes") or typeof(d["axes"]) != TYPE_PACKED_INT32_ARRAY:
		return null
	var header_dict: Dictionary = d["header"]
	var header: ReplayHeader = ReplayHeader.from_dict(header_dict)
	if header == null:
		return null
	if header.format_version < 1 or header.format_version > FORMAT_VERSION:
		return null
	if header.slot_count < 1 or header.axes_per_slot < 0:
		return null
	var buttons: PackedInt64Array = d["buttons"]
	var axes: PackedInt32Array = d["axes"]
	@warning_ignore("integer_division")
	var frames: int = buttons.size() / header.slot_count
	if buttons.size() != frames * header.slot_count:
		return null
	if axes.size() != frames * header.slot_count * header.axes_per_slot:
		return null
	var log: InputLog = InputLog.new(header)
	log._buttons = buttons
	log._axes = axes
	log._frame_count = frames
	var runtime_rows: Variant = d.get("runtime", [])
	if not runtime_rows is Array:
		return null
	var runtime_array: Array = runtime_rows
	if not runtime_array.is_empty() and runtime_array.size() != frames:
		return null
	for index: int in range(frames):
		var runtime_row: Dictionary = {
			"commands": [], "outputs": [], "_identity": ReplayRowIdentity.new()
		}
		if not runtime_array.is_empty():
			var raw_row_value: Variant = runtime_array[index]
			if not raw_row_value is Dictionary:
				return null
			var raw_row: Dictionary = raw_row_value
			var raw_commands: Variant = raw_row.get("commands", [])
			var raw_outputs: Variant = raw_row.get("outputs", [])
			if (
				not raw_commands is Array
				or not raw_outputs is Array
				or not _valid_record_array(raw_commands)
				or not _valid_record_array(raw_outputs)
			):
				return null
			var command_values: Array = raw_commands
			var output_values: Array = raw_outputs
			runtime_row = {
				"commands": _copy_untyped_records(command_values),
				"outputs": _copy_untyped_records(output_values),
				"_identity": ReplayRowIdentity.new()
			}
		log._runtime_rows.append(runtime_row)
		log._row_generations.append(log._next_generation)
		log._next_generation += 1
	return log


## Loads a log from [param path]; null on any failure.
static func load_file(path: String) -> InputLog:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return from_bytes(file.get_buffer(file.get_length()))


## Appends a fixture/import row. This never participates in a simulation transaction.
func append_fixture_row(
	frame: InputFrame,
	command_records: Array[Dictionary] = [],
	output_records: Array[Dictionary] = []
) -> Error:
	if _reservation.size() > 0 or not _valid_frame(frame):
		return ERR_INVALID_PARAMETER
	var commands: Array[Dictionary] = _copy_records(command_records)
	var outputs: Array[Dictionary] = _copy_records(output_records)
	if commands.size() != command_records.size() or outputs.size() != output_records.size():
		return ERR_INVALID_DATA
	_buttons.append_array(frame.buttons)
	_axes.append_array(frame.axes)
	_frame_count += 1
	_runtime_rows.append({"commands": commands, "outputs": outputs})
	_runtime_rows[_runtime_rows.size() - 1]["_identity"] = ReplayRowIdentity.new()
	_row_generations.append(_next_generation)
	_next_generation += 1
	return OK


## Reserves an empty command/output row for one exact commandless prepared live tick.
## This narrow S1 path does not encode typed command or output records.
func prepare_empty_live_append(prepared_tick: PreparedTick) -> AppendPrepareResult:
	if (
		prepared_tick == null
		or not prepared_tick._sim is MatchSim
		or not prepared_tick._sim._runner_owned
		or not prepared_tick._sim._is_active_handle(prepared_tick)
		or prepared_tick._outcome == null
		or prepared_tick._commands == null
		or not prepared_tick._commands.is_valid()
		or prepared_tick._commands.size() != 0
		or not prepared_tick._outputs.is_empty()
		or _reservation.size() > 0
		or header == null
		or not _valid_frame(prepared_tick._candidate_frame)
		or prepared_tick._outcome.candidate_tick != _frame_count + 1
		or prepared_tick._candidate_frame.tick != _frame_count
		or _buttons.size() != _frame_count * header.slot_count
		or _axes.size() != _frame_count * header.slot_count * header.axes_per_slot
		or _runtime_rows.size() != _frame_count
		or _row_generations.size() != _frame_count
	):
		return AppendPrepareResult.failed(ERR_INVALID_PARAMETER)
	var frame: InputFrame = SimTickContext._copy_frame(prepared_tick._candidate_frame)
	var storage_identity: ReplayRowIdentity = ReplayRowIdentity.new()
	var row: Dictionary = {"commands": [], "outputs": [], "_identity": storage_identity}
	var row_snapshot: Dictionary = {"commands": [], "outputs": []}
	var token: PreparedAppendToken = PreparedAppendToken.new()
	var index: int = _frame_count
	var generation: int = _next_generation
	var button_size_before: int = _buttons.size()
	var axis_size_before: int = _axes.size()
	var before: Dictionary = {
		"frame_count": _frame_count,
		"button_size": button_size_before,
		"axis_size": axis_size_before,
		"row_size": _runtime_rows.size(),
		"generation_size": _row_generations.size(),
	}
	# Prepare all replacement storage first; the existing log stays untouched on allocation failure.
	var next_buttons: PackedInt64Array = _buttons.duplicate()
	var button_resize_error: Error = next_buttons.resize(next_buttons.size() + header.slot_count)
	if button_resize_error != OK:
		return AppendPrepareResult.failed(button_resize_error)
	var next_axes: PackedInt32Array = _axes.duplicate()
	var axis_resize_error: Error = next_axes.resize(
		next_axes.size() + header.slot_count * header.axes_per_slot
	)
	if axis_resize_error != OK:
		return AppendPrepareResult.failed(axis_resize_error)
	for slot: int in range(header.slot_count):
		next_buttons[index * header.slot_count + slot] = frame.buttons[slot]
	for axis_index: int in range(header.slot_count * header.axes_per_slot):
		next_axes[index * header.slot_count * header.axes_per_slot + axis_index] = (
			frame.axes[axis_index]
		)
	var next_rows: Array[Dictionary] = _runtime_rows.duplicate()
	var next_generations: Array[int] = _row_generations.duplicate()
	next_rows.append(row)
	next_generations.append(generation)
	_buttons = next_buttons
	_axes = next_axes
	_runtime_rows = next_rows
	_row_generations = next_generations
	_next_generation += 1
	_reservation = {
		"token": token,
		"sim": prepared_tick._sim,
		"prepared_tick": prepared_tick,
		"source_bundle": prepared_tick._commands,
		"output_identity": prepared_tick._outputs,
		"index": index,
		"generation": generation,
		"row": row,
		"row_snapshot": row_snapshot,
		"frame": frame,
		"storage_identity": storage_identity,
		"before": before,
		"active": true,
		"sealed": false,
		"finalized_by": null,
	}
	return AppendPrepareResult.prepared(token)


## Publishes the already sealed row after exact sim finalization.
func commit_append(token: PreparedAppendToken) -> Error:
	if (
		token == null
		or _reservation.is_empty()
		or token != _reservation.token
		or not _reservation.active
		or not _reservation.sealed
		or _reservation.finalized_by != _reservation.sim
	):
		return ERR_INVALID_PARAMETER
	# Row construction, copying, traversal and validation all happened before finalization.
	_frame_count = _reservation.index + 1
	_reservation.active = false
	_reservation.clear()
	return OK


## Releases an uncommitted reservation. It cannot cancel a finalized row.
func cancel_append(token: PreparedAppendToken) -> Error:
	if token == null or _reservation.is_empty() or token != _reservation.token:
		return ERR_INVALID_PARAMETER
	if _reservation.finalized_by != null:
		return ERR_ALREADY_IN_USE
	var before: Dictionary = _reservation.before
	var button_size_value: Variant = before.get("button_size")
	var axis_size_value: Variant = before.get("axis_size")
	var row_size_value: Variant = before.get("row_size")
	var generation_size_value: Variant = before.get("generation_size")
	var frame_count_value: Variant = before.get("frame_count")
	if (
		not button_size_value is int
		or not axis_size_value is int
		or not row_size_value is int
		or not generation_size_value is int
		or not frame_count_value is int
	):
		return ERR_INVALID_DATA
	var button_size: int = button_size_value
	var axis_size: int = axis_size_value
	var row_size: int = row_size_value
	var generation_size: int = generation_size_value
	var frame_count_before: int = frame_count_value
	if (
		button_size < 0
		or button_size > _buttons.size()
		or axis_size < 0
		or axis_size > _axes.size()
		or row_size < 0
		or row_size > _runtime_rows.size()
		or generation_size < 0
		or generation_size > _row_generations.size()
		or frame_count_before < 0
		or frame_count_before > _frame_count
	):
		return ERR_INVALID_DATA
	var button_resize_error: Error = _buttons.resize(button_size)
	if button_resize_error == OK:
		button_resize_error = _axes.resize(axis_size)
	if button_resize_error == OK:
		button_resize_error = _runtime_rows.resize(row_size)
	if button_resize_error == OK:
		button_resize_error = _row_generations.resize(generation_size)
	if button_resize_error != OK:
		return button_resize_error
	_frame_count = frame_count_before
	_reservation.active = false
	_reservation.clear()
	return OK


## Number of stored frames.
func frame_count() -> int:
	return _frame_count


## Copies frame [param index] into [param into]; false when out of range.
func read_frame(index: int, into: InputFrame) -> bool:
	if _reservation.size() > 0:
		return false
	if index < 0 or index >= _frame_count:
		return false
	var slots: int = header.slot_count
	var axis_count: int = slots * header.axes_per_slot
	for i: int in slots:
		into.buttons[i] = _buttons[index * slots + i]
	for i: int in axis_count:
		into.axes[i] = _axes[index * axis_count + i]
	into.tick = index
	return true


## Returns detached command records for a current published row, or an empty array when invalid.
func frame_commands(index: int) -> Array[Dictionary]:
	var row: Dictionary = _published_row(index)
	if row.is_empty():
		return []
	var command_values: Variant = row.get("commands", [])
	if not command_values is Array or not _valid_record_array(command_values):
		return []
	var commands: Array = command_values
	return _copy_untyped_records(commands)


## Returns detached output records for a current published row, or an empty array when invalid.
func frame_outputs(index: int) -> Array[Dictionary]:
	var row: Dictionary = _published_row(index)
	if row.is_empty():
		return []
	var output_values: Variant = row.get("outputs", [])
	if not output_values is Array or not _valid_record_array(output_values):
		return []
	var outputs: Array = output_values
	return _copy_untyped_records(outputs)


## Returns an immutable detached row snapshot with this log's row identity.
func read_replay_row(index: int) -> ReplaySourceRowResult:
	if _reservation.size() > 0:
		return ReplaySourceRowResult.new(false, null, ERR_BUSY)
	if index < 0 or index >= _frame_count:
		return ReplaySourceRowResult.new(false, null, ERR_INVALID_PARAMETER)
	var frame: InputFrame = InputFrame.new(header.slot_count, header.axes_per_slot)
	if not read_frame(index, frame):
		return ReplaySourceRowResult.new(false, null, ERR_INVALID_DATA)
	var row: ReplaySourceRow = ReplaySourceRow.new()
	var runtime_row: Dictionary = _runtime_rows[index]
	var command_values: Variant = runtime_row.get("commands", [])
	var output_values: Variant = runtime_row.get("outputs", [])
	var identity_value: Variant = runtime_row.get("_identity")
	if (
		not command_values is Array
		or not output_values is Array
		or not _valid_record_array(command_values)
		or not _valid_record_array(output_values)
		or not identity_value is ReplayRowIdentity
	):
		return ReplaySourceRowResult.new(false, null, ERR_INVALID_DATA)
	var command_values_array: Array = command_values
	var output_values_array: Array = output_values
	var commands: Array[Dictionary] = _copy_untyped_records(command_values_array)
	var outputs: Array[Dictionary] = _copy_untyped_records(output_values_array)
	var identity: ReplayRowIdentity = identity_value
	row._issue(self, index, frame, commands, outputs, _row_generations[index], identity)
	_issued_replay_rows.append(
		{"row": row, "index": index, "generation": _row_generations[index], "identity": identity}
	)
	return ReplaySourceRowResult.new(true, row, OK)


## Serialises the log.
func to_bytes() -> PackedByteArray:
	if _reservation.size() > 0:
		return PackedByteArray()
	var d: Dictionary = {
		"header": header.to_dict(),
		"buttons": _buttons.slice(0, _frame_count * header.slot_count),
		"axes": _axes.slice(0, _frame_count * header.slot_count * header.axes_per_slot),
		"runtime": _copy_runtime_rows(_runtime_rows.slice(0, _frame_count)),
	}
	var out: PackedByteArray = _MAGIC.duplicate()
	out.append_array(var_to_bytes(d))
	return out


## Writes the log to [param path].
func save(path: String) -> Error:
	if _reservation.size() > 0:
		return ERR_BUSY
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var ok: bool = file.store_buffer(to_bytes())
	file.close()
	return OK if ok else ERR_FILE_CANT_WRITE


func _copy_records(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		if not _supports_row_value(record):
			return []
		result.append(record.duplicate(true))
	return result


static func _copy_untyped_records(records: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Variant in records:
		if not record is Dictionary or not _supports_row_value(record):
			return []
		var record_dictionary: Dictionary = record
		result.append(record_dictionary.duplicate(true))
	return result


func _valid_frame(frame: InputFrame) -> bool:
	return (
		frame != null
		and frame.slot_count == header.slot_count
		and frame.axes_per_slot == header.axes_per_slot
	)


func _is_row_current(
	index: int,
	generation: int,
	row_snapshot: ReplaySourceRow,
	identity: ReplayRowIdentity,
	frame: InputFrame,
	commands: Array[Dictionary],
	outputs: Array[Dictionary]
) -> bool:
	if (
		_reservation.size() > 0
		or index < 0
		or index >= _frame_count
		or index >= _row_generations.size()
		or _row_generations[index] != generation
	):
		return false
	var issued: bool = false
	for registration: Dictionary in _issued_replay_rows:
		if (
			registration.row == row_snapshot
			and registration.index == index
			and registration.generation == generation
			and registration.identity == identity
		):
			issued = true
			break
	if not issued:
		return false
	var stored_frame: InputFrame = InputFrame.new(header.slot_count, header.axes_per_slot)
	if not read_frame(index, stored_frame):
		return false
	var row: Dictionary = _runtime_rows[index]
	return (
		row._identity == identity
		and stored_frame.buttons == frame.buttons
		and stored_frame.axes == frame.axes
		and _exact_value_equal(row.get("commands", []), commands)
		and _exact_value_equal(row.get("outputs", []), outputs)
	)


func _registered_entry(token: PreparedAppendToken) -> Dictionary:
	if token == null or _reservation.is_empty() or token != _reservation.token:
		return {}
	return _reservation


func _finalize_registered_append(
	token: PreparedAppendToken, sim: MatchSim, tick: PreparedTick
) -> bool:
	var entry: Dictionary = _registered_entry(token)
	if (
		entry.is_empty()
		or entry.sim != sim
		or entry.prepared_tick != tick
		or tick._sim != sim
		or not tick._active
		or not _reserved_empty_tick_is_intact(entry)
		or not entry.sealed
	):
		return false
	entry.finalized_by = sim
	return true


func _invalidate_registered_append(token: PreparedAppendToken, tick: PreparedTick) -> void:
	var entry: Dictionary = _registered_entry(token)
	if not entry.is_empty() and entry.prepared_tick == tick and entry.finalized_by == null:
		var cancel_error: Error = cancel_append(token)
		if cancel_error != OK:
			push_error(
				"InputLog: failed to cancel registered append: %s" % error_string(cancel_error)
			)


func _invalidate_for_tick(tick: PreparedTick) -> void:
	if _reservation.size() > 0 and _reservation.prepared_tick == tick:
		if _reservation.finalized_by == null:
			var token_value: Variant = _reservation.get("token")
			if token_value is PreparedAppendToken:
				var token: PreparedAppendToken = token_value
				var cancel_error: Error = cancel_append(token)
				if cancel_error != OK:
					push_error(
						(
							"InputLog: failed to invalidate append reservation: %s"
							% error_string(cancel_error)
						)
					)


func _reservation_row_is_intact(entry: Dictionary) -> bool:
	var index_value: Variant = entry.get("index")
	var before_value: Variant = entry.get("before")
	var generation_value: Variant = entry.get("generation")
	var row_value: Variant = entry.get("row")
	var row_snapshot_value: Variant = entry.get("row_snapshot")
	var frame_value: Variant = entry.get("frame")
	var storage_identity_value: Variant = entry.get("storage_identity")
	if (
		not index_value is int
		or not before_value is Dictionary
		or not generation_value is int
		or not row_value is Dictionary
		or not row_snapshot_value is Dictionary
		or not frame_value is InputFrame
		or not storage_identity_value is ReplayRowIdentity
	):
		return false
	var index: int = index_value
	var before: Dictionary = before_value
	var generation: int = generation_value
	var row: Dictionary = row_value
	var row_snapshot: Dictionary = row_snapshot_value
	var frame: InputFrame = frame_value
	var storage_identity: ReplayRowIdentity = storage_identity_value
	var frame_count_value: Variant = before.get("frame_count")
	var button_size_value: Variant = before.get("button_size")
	var axis_size_value: Variant = before.get("axis_size")
	if not frame_count_value is int or not button_size_value is int or not axis_size_value is int:
		return false
	var frame_count_before: int = frame_count_value
	var button_size_before: int = button_size_value
	var axis_size_before: int = axis_size_value
	if index < 0 or index >= _row_generations.size() or index >= _runtime_rows.size():
		return false
	var runtime_row: Dictionary = _runtime_rows[index]
	var runtime_identity: Variant = runtime_row.get("_identity")
	return (
		index == frame_count_before
		and _buttons.size() == button_size_before + header.slot_count
		and _axes.size() == axis_size_before + header.slot_count * header.axes_per_slot
		and generation == _row_generations[index]
		and _exact_value_equal(_copy_row(row), row_snapshot)
		and _exact_value_equal(_copy_row(runtime_row), row_snapshot)
		and storage_identity == runtime_identity
		and frame.buttons == _buttons.slice(index * header.slot_count, _buttons.size())
		and (
			frame.axes
			== _axes.slice(index * header.slot_count * header.axes_per_slot, _axes.size())
		)
	)


func _published_row(index: int) -> Dictionary:
	if (
		_reservation.size() > 0
		or index < 0
		or index >= _frame_count
		or index >= _runtime_rows.size()
		or index >= _row_generations.size()
		or _row_generations[index] <= 0
	):
		return {}
	var row: Dictionary = _runtime_rows[index]
	if not (row.get("_identity") is ReplayRowIdentity):
		return {}
	return row


## Deep row proof is run while cancellation and sim rollback are still available.
func _seal_registered_append(token: PreparedAppendToken) -> bool:
	var entry: Dictionary = _registered_entry(token)
	if entry.is_empty() or not entry.active or entry.finalized_by != null:
		return false
	if not _reserved_empty_tick_is_intact(entry) or not _reservation_row_is_intact(entry):
		return false
	entry.sealed = true
	return true


func _reserved_empty_tick_is_intact(entry: Dictionary) -> bool:
	var sim_value: Variant = entry.get("sim")
	var tick_value: Variant = entry.get("prepared_tick")
	var frame_value: Variant = entry.get("frame")
	var source_bundle_value: Variant = entry.get("source_bundle")
	var output_identity_value: Variant = entry.get("output_identity")
	var index_value: Variant = entry.get("index")
	if (
		not sim_value is MatchSim
		or not tick_value is PreparedTick
		or not frame_value is InputFrame
		or not source_bundle_value is DetachedCommandBundle
		or not output_identity_value is Array
		or not index_value is int
	):
		return false
	var sim: MatchSim = sim_value
	var tick: PreparedTick = tick_value
	var frame: InputFrame = frame_value
	var source_bundle: DetachedCommandBundle = source_bundle_value
	var output_identity: Array = output_identity_value
	var index: int = index_value
	if not tick._candidate_frame is InputFrame or not tick._outcome is SimTickOutcome:
		return false
	return (
		sim._runner_owned
		and sim._is_active_handle(tick)
		and is_same(source_bundle, tick._commands)
		and source_bundle.is_valid()
		and source_bundle.size() == 0
		and is_same(output_identity, tick._outputs)
		and tick._outputs.is_empty()
		and tick._outcome.candidate_tick == index + 1
		and tick._candidate_frame.equals(frame)
		and tick._candidate_frame.tick == index
	)


static func _exact_value_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is float:
		var left_float: float = left
		var right_float: float = right
		return (is_nan(left_float) and is_nan(right_float)) or left_float == right_float
	if left is Vector2 or left is Vector2i:
		return _exact_value_equal(left.x, right.x) and _exact_value_equal(left.y, right.y)
	if left is Vector3 or left is Vector3i:
		return (
			_exact_value_equal(left.x, right.x)
			and _exact_value_equal(left.y, right.y)
			and _exact_value_equal(left.z, right.z)
		)
	if left is Vector4 or left is Vector4i:
		return (
			_exact_value_equal(left.x, right.x)
			and _exact_value_equal(left.y, right.y)
			and _exact_value_equal(left.z, right.z)
			and _exact_value_equal(left.w, right.w)
		)
	if left is Rect2 or left is Rect2i:
		return (
			_exact_value_equal(left.position, right.position)
			and _exact_value_equal(left.size, right.size)
		)
	if left is Transform2D:
		return (
			_exact_value_equal(left.x, right.x)
			and _exact_value_equal(left.y, right.y)
			and _exact_value_equal(left.origin, right.origin)
		)
	if left is Plane:
		return _exact_value_equal(left.normal, right.normal) and _exact_value_equal(left.d, right.d)
	if left is Quaternion:
		return (
			_exact_value_equal(left.x, right.x)
			and _exact_value_equal(left.y, right.y)
			and _exact_value_equal(left.z, right.z)
			and _exact_value_equal(left.w, right.w)
		)
	if left is AABB:
		return (
			_exact_value_equal(left.position, right.position)
			and _exact_value_equal(left.size, right.size)
		)
	if left is Basis:
		return (
			_exact_value_equal(left.x, right.x)
			and _exact_value_equal(left.y, right.y)
			and _exact_value_equal(left.z, right.z)
		)
	if left is Transform3D:
		return (
			_exact_value_equal(left.basis, right.basis)
			and _exact_value_equal(left.origin, right.origin)
		)
	if left is Projection:
		return (
			_exact_value_equal(left.x, right.x)
			and _exact_value_equal(left.y, right.y)
			and _exact_value_equal(left.z, right.z)
			and _exact_value_equal(left.w, right.w)
		)
	if left is Color:
		return (
			_exact_value_equal(left.r, right.r)
			and _exact_value_equal(left.g, right.g)
			and _exact_value_equal(left.b, right.b)
			and _exact_value_equal(left.a, right.a)
		)
	if left is Dictionary:
		if not right is Dictionary:
			return false
		var left_dictionary: Dictionary = left
		var right_dictionary: Dictionary = right
		if left_dictionary.size() != right_dictionary.size():
			return false
		var left_keys: Array = left_dictionary.keys()
		var left_values: Array = left_dictionary.values()
		var right_keys: Array = right_dictionary.keys()
		var right_values: Array = right_dictionary.values()
		var matched: PackedByteArray = PackedByteArray()
		var matched_resize_error: Error = matched.resize(right_keys.size())
		if matched_resize_error != OK:
			return false
		for entry_index: int in range(left_keys.size()):
			var key: Variant = left_keys[entry_index]
			var paired_index: int = -1
			for index: int in range(right_keys.size()):
				if matched[index] == 0 and _exact_value_equal(key, right_keys[index]):
					paired_index = index
					break
			if (
				paired_index < 0
				or not _exact_value_equal(left_values[entry_index], right_values[paired_index])
			):
				return false
			matched[paired_index] = 1
		return true
	if left is Array:
		if not right is Array:
			return false
		var left_array: Array = left
		var right_array: Array = right
		if left_array.size() != right_array.size():
			return false
		for index: int in range(left_array.size()):
			if not _exact_value_equal(left_array[index], right_array[index]):
				return false
		return true
	if left is PackedFloat32Array:
		if not right is PackedFloat32Array:
			return false
		var left_values: PackedFloat32Array = left
		var right_values: PackedFloat32Array = right
		if left_values.size() != right_values.size():
			return false
		for index: int in range(left_values.size()):
			if not _exact_value_equal(left_values[index], right_values[index]):
				return false
		return true
	if left is PackedFloat64Array:
		if not right is PackedFloat64Array:
			return false
		var left_values: PackedFloat64Array = left
		var right_values: PackedFloat64Array = right
		if left_values.size() != right_values.size():
			return false
		for index: int in range(left_values.size()):
			if not _exact_value_equal(left_values[index], right_values[index]):
				return false
		return true
	if left is PackedVector2Array:
		if not right is PackedVector2Array:
			return false
		var left_values: PackedVector2Array = left
		var right_values: PackedVector2Array = right
		if left_values.size() != right_values.size():
			return false
		for index: int in range(left_values.size()):
			if not _exact_value_equal(left_values[index], right_values[index]):
				return false
		return true
	if left is PackedVector3Array:
		if not right is PackedVector3Array:
			return false
		var left_values: PackedVector3Array = left
		var right_values: PackedVector3Array = right
		if left_values.size() != right_values.size():
			return false
		for index: int in range(left_values.size()):
			if not _exact_value_equal(left_values[index], right_values[index]):
				return false
		return true
	if left is PackedVector4Array:
		if not right is PackedVector4Array:
			return false
		var left_values: PackedVector4Array = left
		var right_values: PackedVector4Array = right
		if left_values.size() != right_values.size():
			return false
		for index: int in range(left_values.size()):
			if not _exact_value_equal(left_values[index], right_values[index]):
				return false
		return true
	if left is PackedColorArray:
		if not right is PackedColorArray:
			return false
		var left_values: PackedColorArray = left
		var right_values: PackedColorArray = right
		if left_values.size() != right_values.size():
			return false
		for index: int in range(left_values.size()):
			if not _exact_value_equal(left_values[index], right_values[index]):
				return false
		return true
	return left == right


static func _contains_nan(value: Variant) -> bool:
	if value is float:
		var scalar: float = value
		return is_nan(scalar)
	if value is Vector2:
		var vector2_x: float = value.x
		var vector2_y: float = value.y
		return is_nan(vector2_x) or is_nan(vector2_y)
	if value is Vector3:
		var vector3_x: float = value.x
		var vector3_y: float = value.y
		var vector3_z: float = value.z
		return is_nan(vector3_x) or is_nan(vector3_y) or is_nan(vector3_z)
	if value is Vector4 or value is Quaternion:
		var vector4_x: float = value.x
		var vector4_y: float = value.y
		var vector4_z: float = value.z
		var vector4_w: float = value.w
		return is_nan(vector4_x) or is_nan(vector4_y) or is_nan(vector4_z) or is_nan(vector4_w)
	if value is Rect2:
		return _contains_nan(value.position) or _contains_nan(value.size)
	if value is Transform2D:
		return _contains_nan(value.x) or _contains_nan(value.y) or _contains_nan(value.origin)
	if value is Plane:
		var plane_d: float = value.d
		return _contains_nan(value.normal) or is_nan(plane_d)
	if value is AABB:
		return _contains_nan(value.position) or _contains_nan(value.size)
	if value is Basis:
		return _contains_nan(value.x) or _contains_nan(value.y) or _contains_nan(value.z)
	if value is Transform3D:
		return _contains_nan(value.basis) or _contains_nan(value.origin)
	if value is Projection:
		return (
			_contains_nan(value.x)
			or _contains_nan(value.y)
			or _contains_nan(value.z)
			or _contains_nan(value.w)
		)
	if value is Color:
		var color_r: float = value.r
		var color_g: float = value.g
		var color_b: float = value.b
		var color_a: float = value.a
		return is_nan(color_r) or is_nan(color_g) or is_nan(color_b) or is_nan(color_a)
	if value is PackedFloat32Array or value is PackedFloat64Array:
		for item: float in value:
			if is_nan(item):
				return true
	if value is PackedVector2Array or value is PackedVector3Array:
		for item: Variant in value:
			if _contains_nan(item):
				return true
	if value is PackedVector4Array or value is PackedColorArray:
		for item: Variant in value:
			if _contains_nan(item):
				return true
	if value is Array:
		for item: Variant in value:
			if _contains_nan(item):
				return true
	if value is Dictionary:
		for key: Variant in value:
			if _contains_nan(key) or _contains_nan(value[key]):
				return true
	return false


func _copy_row(row: Dictionary) -> Dictionary:
	var command_values: Variant = row.get("commands", [])
	var output_values: Variant = row.get("outputs", [])
	if (
		not command_values is Array
		or not output_values is Array
		or not _valid_record_array(command_values)
		or not _valid_record_array(output_values)
	):
		return {}
	var command_array: Array = command_values
	var output_array: Array = output_values
	return {
		"commands": _copy_untyped_records(command_array),
		"outputs": _copy_untyped_records(output_array)
	}


func _copy_runtime_rows(rows: Array) -> Array:
	var result: Array = []
	for row: Dictionary in rows:
		var command_values: Variant = row.get("commands", [])
		var output_values: Variant = row.get("outputs", [])
		if (
			not command_values is Array
			or not output_values is Array
			or not _valid_record_array(command_values)
			or not _valid_record_array(output_values)
		):
			return []
		var command_array: Array = command_values
		var output_array: Array = output_values
		var commands: Array[Dictionary] = _copy_untyped_records(command_array)
		var outputs: Array[Dictionary] = _copy_untyped_records(output_array)
		result.append({"commands": commands, "outputs": outputs})
	return result


static func _copy_supported_value(value: Variant) -> Variant:
	if not _supports_row_value(value):
		return null
	if value is Dictionary or value is Array or OwnerCapture._is_packed_array(value):
		return OwnerCapture._copy_contract_value(value)
	return value


static func _supports_row_value(value: Variant) -> bool:
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if (
				not _supports_row_value(key)
				or _contains_nan(key)
				or not _supports_row_value(value[key])
			):
				return false
	elif value is Array:
		for item: Variant in value:
			if not _supports_row_value(item):
				return false
	return true


static func _valid_record_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for record: Variant in value:
		if typeof(record) != TYPE_DICTIONARY or not _supports_row_value(record):
			return false
	return true

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
	if typeof(runtime_rows) != TYPE_ARRAY:
		return null
	if not runtime_rows.is_empty() and runtime_rows.size() != frames:
		return null
	for index: int in range(frames):
		var runtime_row: Dictionary = {
			"commands": [], "outputs": [], "_identity": ReplayRowIdentity.new()
		}
		if not runtime_rows.is_empty():
			var raw_row: Variant = runtime_rows[index]
			if typeof(raw_row) != TYPE_DICTIONARY:
				return null
			var raw_commands: Variant = raw_row.get("commands", [])
			var raw_outputs: Variant = raw_row.get("outputs", [])
			if not _valid_record_array(raw_commands) or not _valid_record_array(raw_outputs):
				return null
			runtime_row = {
				"commands": _copy_untyped_records(raw_commands),
				"outputs": _copy_untyped_records(raw_outputs),
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
	_buttons.resize(before.button_size)
	_axes.resize(before.axis_size)
	_runtime_rows.resize(before.row_size)
	_row_generations.resize(before.generation_size)
	_frame_count = before.frame_count
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
	return _copy_records(row.get("commands", []))


## Returns detached output records for a current published row, or an empty array when invalid.
func frame_outputs(index: int) -> Array[Dictionary]:
	var row: Dictionary = _published_row(index)
	if row.is_empty():
		return []
	return _copy_records(row.get("outputs", []))


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
	row._issue(
		self,
		index,
		frame,
		runtime_row.get("commands", []),
		runtime_row.get("outputs", []),
		_row_generations[index],
		runtime_row._identity
	)
	_issued_replay_rows.append(
		{
			"row": row,
			"index": index,
			"generation": _row_generations[index],
			"identity": runtime_row._identity
		}
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
		if not _supports_row_value(record):
			return []
		result.append((record as Dictionary).duplicate(true))
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
		or entry.source_bundle != tick._commands
		or entry.output_identity != tick._outputs
		or not entry.sealed
	):
		return false
	entry.finalized_by = sim
	return true


func _invalidate_registered_append(token: PreparedAppendToken, tick: PreparedTick) -> void:
	var entry: Dictionary = _registered_entry(token)
	if not entry.is_empty() and entry.prepared_tick == tick and entry.finalized_by == null:
		cancel_append(token)


func _invalidate_for_tick(tick: PreparedTick) -> void:
	if _reservation.size() > 0 and _reservation.prepared_tick == tick:
		if _reservation.finalized_by == null:
			cancel_append(_reservation.token)


func _reservation_row_is_intact(entry: Dictionary) -> bool:
	return (
		entry.index == entry.before.frame_count
		and entry.index < _row_generations.size()
		and entry.index < _runtime_rows.size()
		and _buttons.size() == entry.before.button_size + header.slot_count
		and _axes.size() == entry.before.axis_size + header.slot_count * header.axes_per_slot
		and entry.generation == _row_generations[entry.index]
		and _exact_value_equal(_copy_row(entry.row), entry.row_snapshot)
		and _exact_value_equal(_copy_row(_runtime_rows[entry.index]), entry.row_snapshot)
		and entry.storage_identity == _runtime_rows[entry.index]._identity
		and entry.frame.buttons == _buttons.slice(entry.index * header.slot_count, _buttons.size())
		and (
			entry.frame.axes
			== _axes.slice(entry.index * header.slot_count * header.axes_per_slot, _axes.size())
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
	if not _reservation_row_is_intact(entry):
		return false
	entry.sealed = true
	return true


static func _exact_value_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is float:
		return (is_nan(left) and is_nan(right)) or left == right
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
		if left.size() != right.size():
			return false
		var left_keys: Array = left.keys()
		var left_values: Array = left.values()
		var right_keys: Array = right.keys()
		var right_values: Array = right.values()
		var matched: PackedByteArray = PackedByteArray()
		matched.resize(right_keys.size())
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
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _exact_value_equal(left[index], right[index]):
				return false
		return true
	if left is PackedFloat32Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _exact_value_equal(left[index], right[index]):
				return false
		return true
	if left is PackedFloat64Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _exact_value_equal(left[index], right[index]):
				return false
		return true
	if left is PackedVector2Array or left is PackedVector3Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _exact_value_equal(left[index], right[index]):
				return false
		return true
	if left is PackedVector4Array or left is PackedColorArray:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _exact_value_equal(left[index], right[index]):
				return false
		return true
	return left == right


static func _contains_nan(value: Variant) -> bool:
	if value is float:
		return is_nan(value)
	if value is Vector2:
		return is_nan(value.x) or is_nan(value.y)
	if value is Vector3:
		return is_nan(value.x) or is_nan(value.y) or is_nan(value.z)
	if value is Vector4 or value is Quaternion:
		return is_nan(value.x) or is_nan(value.y) or is_nan(value.z) or is_nan(value.w)
	if value is Rect2:
		return _contains_nan(value.position) or _contains_nan(value.size)
	if value is Transform2D:
		return _contains_nan(value.x) or _contains_nan(value.y) or _contains_nan(value.origin)
	if value is Plane:
		return _contains_nan(value.normal) or is_nan(value.d)
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
		return is_nan(value.r) or is_nan(value.g) or is_nan(value.b) or is_nan(value.a)
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
	return {
		"commands": _copy_records(row.get("commands", [])),
		"outputs": _copy_records(row.get("outputs", []))
	}


func _copy_runtime_rows(rows: Array) -> Array:
	var result: Array = []
	for row: Dictionary in rows:
		var commands: Array[Dictionary] = _copy_untyped_records(row.get("commands", []))
		var outputs: Array[Dictionary] = _copy_untyped_records(row.get("outputs", []))
		result.append({"commands": commands, "outputs": outputs})
	return result


static func _copy_supported_value(value: Variant) -> Variant:
	if not _supports_row_value(value):
		return null
	if value is Dictionary or value is Array or OwnerCapture._is_packed_array(value):
		return value.duplicate(true)
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

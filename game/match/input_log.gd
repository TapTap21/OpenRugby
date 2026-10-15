class_name InputLog
extends RefCounted
## Recorded input frames plus a [ReplayHeader]; the tick of a frame is its index.

const FORMAT_VERSION: int = ReplayHeader.CURRENT_FORMAT_VERSION
const _MAGIC: PackedByteArray = [0x4F, 0x52, 0x4C, 0x47]

var header: ReplayHeader

var _buttons: PackedInt64Array = PackedInt64Array()
var _axes: PackedInt32Array = PackedInt32Array()
var _runtime_frames: Array[Dictionary] = []
var _frame_count: int = 0


func _init(p_header: ReplayHeader) -> void:
	header = p_header


## Parses a log from [param bytes]; null when invalid or from a newer format.
static func from_bytes(bytes: PackedByteArray) -> InputLog:
	if bytes.size() <= _MAGIC.size() or bytes.slice(0, _MAGIC.size()) != _MAGIC:
		return null
	var raw: Variant = bytes_to_var(bytes.slice(_MAGIC.size()))
	if not (raw is Dictionary):
		return null
	# var_to_bytes is canonical for the parsed Variant; equality proves the parser consumed all
	# bytes rather than accepting a valid prefix followed by unrelated or truncated data.
	if var_to_bytes(raw) != bytes.slice(_MAGIC.size()):
		return null
	var d: Dictionary = raw
	var raw_header_value: Variant = d.get("header")
	if not d.has("header") or not (raw_header_value is Dictionary):
		return null
	var raw_header: Dictionary = raw_header_value
	if not raw_header.has("format_version") or typeof(raw_header["format_version"]) != TYPE_INT:
		return null
	var expected_keys: int = 4 if raw_header["format_version"] >= 2 else 3
	if d.size() != expected_keys:
		return null
	var raw_buttons: Variant = d.get("buttons")
	if not d.has("buttons") or not (raw_buttons is PackedInt64Array):
		return null
	var raw_axes: Variant = d.get("axes")
	if not d.has("axes") or not (raw_axes is PackedInt32Array):
		return null
	var buttons: PackedInt64Array = raw_buttons
	var axes: PackedInt32Array = raw_axes
	var header: ReplayHeader = ReplayHeader.from_dict(raw_header)
	if header == null:
		return null
	if header.format_version < 1 or header.format_version > FORMAT_VERSION:
		return null
	if header.slot_count < 1 or header.axes_per_slot < 0:
		return null
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
	if header.format_version >= 2:
		var raw_runtime: Variant = d.get("runtime")
		if not d.has("runtime") or not (raw_runtime is Array):
			return null
		var runtime: Array = raw_runtime
		if runtime.size() != frames:
			return null
		for runtime_frame: Variant in runtime:
			if not (runtime_frame is Dictionary):
				return null
			var frame_record: Dictionary = runtime_frame
			var raw_commands: Variant = frame_record.get("commands")
			var raw_outputs: Variant = frame_record.get("outputs")
			if (
				frame_record.size() != 2
				or not frame_record.has("commands")
				or not (raw_commands is Array)
				or not frame_record.has("outputs")
				or not (raw_outputs is Array)
			):
				return null
			var commands: Array[Dictionary] = []
			var outputs: Array[Dictionary] = []
			var command_values: Array = raw_commands
			var output_values: Array = raw_outputs
			for command: Variant in command_values:
				if not (command is Dictionary):
					return null
				var command_record: Dictionary = command
				commands.append(command_record)
			for output: Variant in output_values:
				if not (output is Dictionary):
					return null
				var output_record: Dictionary = output
				outputs.append(output_record)
			# Keep the sibling loops above separate and add exactly one record per frame.
			log._runtime_frames.append({"commands": commands, "outputs": outputs})
	else:
		for _frame: int in frames:
			log._runtime_frames.append({"commands": [], "outputs": []})
	return log


## Loads a log from [param path]; null on any failure.
static func load_file(path: String) -> InputLog:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return from_bytes(file.get_buffer(file.get_length()))


## Appends [param frame]; ignored (with an error) when its shape does not match the header.
func append(
	frame: InputFrame, commands: Array[Dictionary] = [], outputs: Array[Dictionary] = []
) -> void:
	if frame.slot_count != header.slot_count or frame.axes_per_slot != header.axes_per_slot:
		push_error("InputLog.append: frame shape does not match the header")
		return
	_buttons.append_array(frame.buttons)
	_axes.append_array(frame.axes)
	_runtime_frames.append({"commands": _copy_records(commands), "outputs": _copy_records(outputs)})
	_frame_count += 1


## Number of stored frames.
func frame_count() -> int:
	return _frame_count


## Copies frame [param index] into [param into]; false when out of range.
func read_frame(index: int, into: InputFrame) -> bool:
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


## Recorded typed commands for frame [param index], preserving the original sequence values.
func frame_commands(index: int) -> Array[Dictionary]:
	if index < 0 or index >= _runtime_frames.size():
		return []
	var frame_record: Dictionary = _runtime_frames[index]
	var raw_commands: Variant = frame_record.get("commands")
	var result: Array[Dictionary] = []
	if not (raw_commands is Array):
		return result
	for command: Variant in raw_commands:
		if command is Dictionary:
			var command_record: Dictionary = command
			var duplicate_value: Variant = command_record.duplicate(true)
			if duplicate_value is Dictionary:
				var duplicate_record: Dictionary = duplicate_value
				result.append(duplicate_record)
	return result


## Recorded typed outputs for frame [param index].
func frame_outputs(index: int) -> Array[Dictionary]:
	if index < 0 or index >= _runtime_frames.size():
		return []
	var frame_record: Dictionary = _runtime_frames[index]
	var raw_outputs: Variant = frame_record.get("outputs")
	var result: Array[Dictionary] = []
	if not (raw_outputs is Array):
		return result
	for output: Variant in raw_outputs:
		if output is Dictionary:
			var output_record: Dictionary = output
			var duplicate_value: Variant = output_record.duplicate(true)
			if duplicate_value is Dictionary:
				var duplicate_record: Dictionary = duplicate_value
				result.append(duplicate_record)
	return result


## Serialises the log.
func to_bytes() -> PackedByteArray:
	var d: Dictionary = {
		"header": header.to_dict(),
		"buttons": _buttons,
		"axes": _axes,
	}
	if header.format_version >= 2:
		d["runtime"] = _runtime_frames
	var out: PackedByteArray = PackedByteArray()
	out.append_array(_MAGIC)
	out.append_array(var_to_bytes(d))
	return out


## Writes the log to [param path].
func save(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var ok: bool = file.store_buffer(to_bytes())
	file.close()
	return OK if ok else ERR_FILE_CANT_WRITE


func _copy_records(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		var duplicate_value: Variant = record.duplicate(true)
		if duplicate_value is Dictionary:
			var duplicate_record: Dictionary = duplicate_value
			result.append(duplicate_record)
	return result

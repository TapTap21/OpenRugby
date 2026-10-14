class_name InputLog
extends RefCounted
## Recorded input frames plus a [ReplayHeader]; the tick of a frame is its index.

const FORMAT_VERSION: int = 1
const _MAGIC: PackedByteArray = [0x4F, 0x52, 0x4C, 0x47]

var header: ReplayHeader

var _buttons: PackedInt64Array = PackedInt64Array()
var _axes: PackedInt32Array = PackedInt32Array()
var _frame_count: int = 0


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
	return log


## Loads a log from [param path]; null on any failure.
static func load_file(path: String) -> InputLog:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return from_bytes(file.get_buffer(file.get_length()))


## Appends [param frame]; ignored (with an error) when its shape does not match the header.
func append(frame: InputFrame) -> void:
	if frame.slot_count != header.slot_count or frame.axes_per_slot != header.axes_per_slot:
		push_error("InputLog.append: frame shape does not match the header")
		return
	_buttons.append_array(frame.buttons)
	_axes.append_array(frame.axes)
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


## Serialises the log.
func to_bytes() -> PackedByteArray:
	var d: Dictionary = {
		"header": header.to_dict(),
		"buttons": _buttons,
		"axes": _axes,
	}
	var out: PackedByteArray = _MAGIC.duplicate()
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

class_name ReplayInputSource
extends InputSource
## Plays back the frames of an [InputLog].

var _log: InputLog


func _init(p_log: InputLog) -> void:
	_log = p_log


func fill_frame(tick: int, frame: InputFrame) -> bool:
	return _log.read_frame(tick, frame)


func layout_hash() -> String:
	return _log.header.action_layout_hash

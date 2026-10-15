class_name InputSource
extends RefCounted
## Supplies one [InputFrame] per tick: live devices, a replay log or a script.
##
## The base class yields empty frames forever.


## Fills [param frame] for tick [param _tick]. Returns false when no more input exists.
func fill_frame(_tick: int, frame: InputFrame, _commands: DetachedCommandBundleBuilder) -> bool:
	frame.clear()
	return true


## Identifies the action layout the frames were produced for.
func layout_hash() -> String:
	return ""

class_name InputSampler
extends InputSource
## Samples the live [Input] state into [InputFrame]s, laid out by an [InputActionSet].
##
## This is the only class under game/platform/input that reads [Input]; the simulation reads
## frames only. Action ids are cached at construction so [method fill_frame] does not allocate.

var _action_set: InputActionSet
var _slot_count: int
var _button_actions: Array[StringName] = []
var _axes: Array[InputAxisDef] = []


func _init(p_action_set: InputActionSet, p_slot_count: int = 1) -> void:
	_action_set = p_action_set
	_slot_count = p_slot_count
	_button_actions = p_action_set.button_actions()
	for axis: InputAxisDef in p_action_set.axes:
		if axis != null:
			_axes.append(axis)


## Fills [param frame] for [param tick] from slot 0 (all devices). Always returns true.
func fill_frame(
	tick: int, frame: InputFrame, _commands: DetachedCommandBundleBuilder = null
) -> bool:
	assert(frame.slot_count == _slot_count)
	frame.tick = tick
	frame.clear()
	for bit: int in _button_actions.size():
		if Input.is_action_pressed(_button_actions[bit]):
			frame.set_held(0, bit, true)
	for position: int in _axes.size():
		var axis: InputAxisDef = _axes[position]
		var vector: Vector2 = Input.get_vector(
			axis.negative_x, axis.positive_x, axis.negative_y, axis.positive_y
		)
		frame.set_axis(0, 2 * position, roundi(vector.x * InputFrame.AXIS_MAX))
		frame.set_axis(0, 2 * position + 1, roundi(vector.y * InputFrame.AXIS_MAX))
	return true


## Returns the layout hash of the action set used for sampling.
func layout_hash() -> String:
	return _action_set.layout_hash()

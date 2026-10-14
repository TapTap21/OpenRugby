class_name InputActionSet
extends Resource
## A named collection of actions and axes. It is the single source of the simulation input layout.
##
## Bit i of an input frame slot is [code]button_actions()[i][/code]. Axis j occupies frame axes
## [code]2 * j[/code] (x) and [code]2 * j + 1[/code] (y).

## Largest number of button actions an [InputFrame] slot can hold.
const MAX_BUTTON_ACTIONS: int = 63

## Identifier of the set, stored with saved bindings.
@export var id: StringName = &"default"

## Every action, in layout order.
@export var actions: Array[InputActionDef] = []

## Every axis, in layout order.
@export var axes: Array[InputAxisDef] = []


## Returns the action with [param action_id], or null when absent.
func get_action(action_id: StringName) -> InputActionDef:
	for action: InputActionDef in actions:
		if action != null and action.id == action_id:
			return action
	return null


## Returns the MATCH actions that are not axis components, in array order.
func button_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for action: InputActionDef in actions:
		if action == null or action.context != InputActionDef.Context.MATCH:
			continue
		if not _is_axis_component(action.id):
			result.append(action.id)
	return result


## Returns the bit of button action [param action_id], or -1 when it is not a button action.
func bit_of(action_id: StringName) -> int:
	return button_actions().find(action_id)


## Returns the number of frame axes per slot.
func axes_per_slot() -> int:
	return 2 * axes.size()


## Returns the frame axis index of [param component] (0 = x, 1 = y) of [param axis_id], or -1.
func axis_index(axis_id: StringName, component: int) -> int:
	if component < 0 or component > 1:
		return -1
	for position: int in axes.size():
		var axis: InputAxisDef = axes[position]
		if axis != null and axis.id == axis_id:
			return 2 * position + component
	return -1


## Returns the lowercase hex SHA-256 of the layout text (button lines in bit order, then axes).
func layout_hash() -> String:
	var lines: Array[String] = []
	for action_id: StringName in button_actions():
		lines.append("button:%s" % action_id)
	for axis: InputAxisDef in axes:
		if axis == null:
			continue
		lines.append(
			(
				"axis:%s:%s,%s,%s,%s"
				% [axis.id, axis.negative_x, axis.positive_x, axis.negative_y, axis.positive_y]
			)
		)
	var context: HashingContext = HashingContext.new()
	var err: Error = context.start(HashingContext.HASH_SHA256)
	assert(err == OK)
	err = context.update("\n".join(PackedStringArray(lines)).to_utf8_buffer())
	assert(err == OK)
	return context.finish().hex_encode()


## Returns a zeroed [InputFrame] shaped for this set with [param slot_count] slots.
func make_frame(slot_count: int = 1) -> InputFrame:
	return InputFrame.new(slot_count, axes_per_slot())


## Returns one message per problem found, or an empty array when the set is valid.
func validate() -> PackedStringArray:
	var errors: Array[String] = []
	var seen_actions: Dictionary = {}
	for action: InputActionDef in actions:
		if action == null:
			errors.append("null action entry")
			continue
		if action.id.is_empty():
			errors.append("action with empty id")
		elif seen_actions.has(action.id):
			errors.append("duplicate action id: %s" % action.id)
		seen_actions[action.id] = true
	var seen_axes: Dictionary = {}
	for axis: InputAxisDef in axes:
		if axis == null:
			errors.append("null axis entry")
			continue
		if axis.id.is_empty() or seen_axes.has(axis.id):
			errors.append("axis id empty or duplicate: %s" % axis.id)
		seen_axes[axis.id] = true
		var references: Array[StringName] = [
			axis.negative_x, axis.positive_x, axis.negative_y, axis.positive_y
		]
		for reference: StringName in references:
			var target: InputActionDef = get_action(reference)
			if target == null:
				errors.append("axis %s references unknown action %s" % [axis.id, reference])
			elif target.context != InputActionDef.Context.MATCH:
				errors.append("axis %s references non-MATCH action %s" % [axis.id, reference])
	if button_actions().size() > MAX_BUTTON_ACTIONS:
		errors.append("more than %d button actions" % MAX_BUTTON_ACTIONS)
	return PackedStringArray(errors)


func _is_axis_component(action_id: StringName) -> bool:
	for axis: InputAxisDef in axes:
		if axis == null:
			continue
		var components: Array[StringName] = [
			axis.negative_x, axis.positive_x, axis.negative_y, axis.positive_y
		]
		if components.has(action_id):
			return true
	return false

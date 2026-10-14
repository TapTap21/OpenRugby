class_name InputFrame
extends RefCounted
## One tick of input for every controller slot: held-button bitmasks and quantised axes.
##
## This is the only input the simulation sees. Bit and axis meaning comes from the input action
## set; the core never names actions.

const AXIS_MAX: int = 127

## 0-based index of the tick this frame belongs to.
var tick: int = 0

## Number of controller slots.
var slot_count: int:
	get:
		return _slot_count

## Number of axes per slot.
var axes_per_slot: int:
	get:
		return _axes_per_slot

## Bit b of buttons[s] is set while button action b is held on slot s.
var buttons: PackedInt64Array = PackedInt64Array()

## Quantised axes in [-127, 127], slot-major.
var axes: PackedInt32Array = PackedInt32Array()

var _slot_count: int = 1
var _axes_per_slot: int = 2


func _init(p_slot_count: int = 1, p_axes_per_slot: int = 2) -> void:
	_slot_count = p_slot_count
	_axes_per_slot = p_axes_per_slot
	var err: int = buttons.resize(p_slot_count)
	assert(err == OK)
	err = axes.resize(p_slot_count * p_axes_per_slot)
	assert(err == OK)


## Returns true when button [param bit] (0..62) is held on [param slot].
func is_held(slot: int, bit: int) -> bool:
	return (buttons[slot] >> bit) & 1 == 1


## Sets or clears button [param bit] (0..62) on [param slot].
func set_held(slot: int, bit: int, held: bool) -> void:
	if held:
		buttons[slot] |= 1 << bit
	else:
		buttons[slot] &= ~(1 << bit)


## Returns the quantised axis value for [param slot] and [param axis].
func get_axis(slot: int, axis: int) -> int:
	return axes[slot * _axes_per_slot + axis]


## Stores an axis value, clamped to [-127, 127].
func set_axis(slot: int, axis: int, value: int) -> void:
	axes[slot * _axes_per_slot + axis] = clampi(value, -AXIS_MAX, AXIS_MAX)


## Zeroes all buttons and axes. The tick index is unchanged.
func clear() -> void:
	buttons.fill(0)
	axes.fill(0)


## Copies tick, buttons and axes from [param other]; both frames must have the same shape.
func copy_from(other: InputFrame) -> void:
	if other._slot_count != _slot_count or other._axes_per_slot != _axes_per_slot:
		push_error("InputFrame.copy_from: shape mismatch")
		return
	tick = other.tick
	for i: int in _slot_count:
		buttons[i] = other.buttons[i]
	for i: int in axes.size():
		axes[i] = other.axes[i]


## Returns true when shape, tick, buttons and axes are all equal.
func equals(other: InputFrame) -> bool:
	return (
		other._slot_count == _slot_count
		and other._axes_per_slot == _axes_per_slot
		and other.tick == tick
		and other.buttons == buttons
		and other.axes == axes
	)

class_name PlayerAttributeSchema
extends Resource
## Defines the player attribute ids, position ids and the allowed value range.

## PROVISIONAL list of attribute ids.
@export var attribute_ids: Array[StringName] = []
## PROVISIONAL list of position ids.
@export var position_ids: Array[StringName] = []
@export var min_value: int = 0
@export var max_value: int = 100
@export var default_value: int = 50


## True when [param id] is a known attribute id.
func has_attribute(id: StringName) -> bool:
	return attribute_ids.has(id)


## Clamps [param value] into the allowed range.
func clamp_value(value: int) -> int:
	return clampi(value, min_value, max_value)


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if min_value >= max_value:
		errors += PackedStringArray(["min_value must be less than max_value"])
	if default_value < min_value or default_value > max_value:
		errors += PackedStringArray(["default_value must be inside the range"])
	var seen: Dictionary[StringName, bool] = {}
	for id: StringName in attribute_ids:
		if seen.has(id):
			errors += PackedStringArray(["duplicate attribute id '%s'" % id])
		seen[id] = true
	var seen_positions: Dictionary[StringName, bool] = {}
	for id: StringName in position_ids:
		if seen_positions.has(id):
			errors += PackedStringArray(["duplicate position id '%s'" % id])
		seen_positions[id] = true
	return errors

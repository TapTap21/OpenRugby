class_name Stadium
extends Resource
## A stadium: its pitch and presentation asset paths.

@export var id: StringName
@export var name: String
@export var city: String
@export var country: StringName
@export var capacity: int = 0
@export var pitch: PitchGeometry
@export var scene_path: String = ""
@export var crowd_ambience_path: String = ""
## PROVISIONAL.
@export var has_roof: bool = false


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors += PackedStringArray(["stadium id is empty"])
	if capacity < 0:
		errors += PackedStringArray(["stadium '%s' capacity must not be negative" % id])
	if pitch == null:
		errors += PackedStringArray(["stadium '%s' pitch is null" % id])
	else:
		errors.append_array(pitch.validate())
	return errors

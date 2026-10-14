class_name Kit
extends Resource
## Team kit colours and texture reference.

@export var id: StringName
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.BLACK
@export var shorts_color: Color = Color.WHITE
@export var socks_color: Color = Color.WHITE
@export var number_color: Color = Color.BLACK
## PROVISIONAL pattern id.
@export var pattern: StringName = &"plain"
## Asset path, resolved through the mod runtime.
@export var jersey_texture_path: String = ""


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors += PackedStringArray(["kit id is empty"])
	return errors

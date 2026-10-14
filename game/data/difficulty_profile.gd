class_name DifficultyProfile
extends Resource
## A named difficulty level with a tuning table.

@export var id: StringName
@export var display_name_key: String
@export var level: int = 0
## PROVISIONAL keys until the AI analysis reports.
@export var tuning: Dictionary[StringName, float] = {}


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors += PackedStringArray(["difficulty id is empty"])
	return errors

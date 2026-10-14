class_name PlayerProfile
extends Resource
## One player record from the game database.

enum Foot { RIGHT, LEFT }

@export var id: StringName
@export var first_name: String
@export var last_name: String
@export var known_as: String = ""
@export var nationality: StringName
@export var birth_year: int = 1980
@export var height_cm: int = 185
@export var weight_kg: int = 100
@export var preferred_foot: Foot = Foot.RIGHT
@export var primary_position: StringName
@export var secondary_positions: Array[StringName] = []
## PROVISIONAL keys from the attribute schema.
@export var attributes: Dictionary[StringName, int] = {}


## Name to show: [member known_as] when set, else first and last name.
func display_name() -> String:
	if known_as != "":
		return known_as
	return (first_name + " " + last_name).strip_edges()


## Returns the attribute value, or the schema default when absent.
func get_attribute(attribute_id: StringName, schema: PlayerAttributeSchema) -> int:
	if attributes.has(attribute_id):
		return attributes[attribute_id]
	return schema.default_value


## Returns one message per problem; empty when valid.
func validate(schema: PlayerAttributeSchema = null) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors += PackedStringArray(["player id is empty"])
	if height_cm <= 0:
		errors += PackedStringArray(["player '%s' height_cm must be positive" % id])
	if weight_kg <= 0:
		errors += PackedStringArray(["player '%s' weight_kg must be positive" % id])
	if schema != null:
		for key: StringName in attributes:
			if not schema.has_attribute(key):
				errors += PackedStringArray(["player '%s' has unknown attribute '%s'" % [id, key]])
			elif attributes[key] < schema.min_value or attributes[key] > schema.max_value:
				errors += PackedStringArray(
					["player '%s' attribute '%s' is out of range" % [id, key]]
				)
	return errors

class_name GameSettingsImpl
extends Node
## Global settings autoload. Holds user-facing settings persisted under user://.
## Persistence and the settings schema arrive with the save slice.

## Version of the persisted settings schema.
const SCHEMA_VERSION: int = 1

## Default action set: the single definition of every input action.
const INPUT_ACTION_SET_PATH: String = "res://game/platform/input/default_action_set.tres"

## Live input bindings, applied to [InputMap] when the autoload starts.
var input_bindings: InputBindings


func _ready() -> void:
	var action_set: InputActionSet = load(INPUT_ACTION_SET_PATH) as InputActionSet
	assert(action_set != null, "default input action set failed to load")
	input_bindings = InputBindings.new(action_set)
	input_bindings.apply_defaults()
	var err: Error = input_bindings.load_from()
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("GameSettings: saved input bindings ignored (%s)" % error_string(err))

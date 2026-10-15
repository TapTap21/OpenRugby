class_name Main
extends Node
## Entry scene of OpenRugby with a clearly labeled prototype sandbox route.

const PROTOTYPE_SCENE_PATH: String = "res://game/prototype/prototype_sandbox.tscn"

var _mod_loader: ModLoader
var _mod_runtime: ModRuntime
var _match_runner: MatchRunner

@onready var _title: Label = %Title
@onready var _prototype_button: Button = %PrototypeButton


func _ready() -> void:
	_title.text = tr("GAME_TITLE")
	_prototype_button.text = tr("PROTOTYPE_STATUS_TITLE")
	_prototype_button.tooltip_text = tr("PROTOTYPE_STATUS_DETAIL")
	var connect_error: Error = _prototype_button.pressed.connect(_on_prototype_button_pressed)
	if connect_error != OK:
		push_error("Could not connect the prototype sandbox button.")
	_mod_loader = ModLoader.new()
	_mod_runtime = _mod_loader.load_mods(GameSettings.enabled_mods)


## Starts a match through a runner using this Main instance's applied mod runtime.
func start_match(config: MatchConfig, source: InputSource, systems: Array[SimSystem] = []) -> Error:
	if _mod_runtime == null:
		return ERR_UNCONFIGURED
	if _match_runner == null:
		_match_runner = MatchRunner.new()
		add_child(_match_runner)
	return _match_runner.start(
		config, source, systems, _mod_runtime.mod_set_hash, _mod_runtime.extension_points
	)


func _on_prototype_button_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(PROTOTYPE_SCENE_PATH)
	if error != OK:
		push_error("Could not open the prototype training sandbox.")

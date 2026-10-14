class_name Main
extends Node
## Entry scene of OpenRugby. Will become the scene router; for now it only shows a title label.

var _mod_loader: ModLoader
var _mod_runtime: ModRuntime
var _match_runner: MatchRunner

@onready var _title: Label = %Title


func _ready() -> void:
	_title.text = tr("GAME_TITLE")
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

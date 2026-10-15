class_name Main
extends Node
## Entry scene of OpenRugby with a clearly labeled prototype sandbox route.

const PROTOTYPE_SCENE_PATH: String = "res://game/prototype/prototype_sandbox.tscn"

signal match_start_blocked(report: MatchReadinessReport)

var last_match_build: MatchBuildResult

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
func start_match(
	config: MatchConfig,
	source: InputSource,
	systems: Array[SimSystem] = [],
	s2_port: S2RuntimePort = null
) -> Error:
	if _mod_runtime == null:
		last_match_build = MatchBuildResult.new()
		last_match_build.readiness.add_blocker(
			MatchReadinessReport.Capability.MATCH_CONFIG, "mod runtime is not initialized"
		)
		match_start_blocked.emit(last_match_build.readiness)
		return ERR_UNCONFIGURED
	if _match_runner == null:
		_match_runner = MatchRunner.new()
		add_child(_match_runner)
	var error: Error = _match_runner.start(
		config,
		source,
		systems,
		_mod_runtime.mod_set_hash,
		_mod_runtime.extension_points,
		null,
		null,
		s2_port
	)
	last_match_build = _match_runner.last_build_result
	if error != OK and last_match_build != null:
		match_start_blocked.emit(last_match_build.readiness)
	return error


## Typed readiness report for the most recent match start attempt.
func match_readiness_report() -> MatchReadinessReport:
	if last_match_build == null:
		return MatchReadinessReport.new()
	return last_match_build.readiness


## Caller-owned S2 setup/action port, available even when start reports blockers.
func s2_runtime_port() -> S2RuntimePort:
	return _match_runner.runtime_port if _match_runner != null else null


func _on_prototype_button_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(PROTOTYPE_SCENE_PATH)
	if error != OK:
		push_error("Could not open the prototype training sandbox.")

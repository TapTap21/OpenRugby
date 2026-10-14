class_name Main
extends Node
## Entry scene of OpenRugby. Will become the scene router; for now it only shows a title label.

var _mod_loader: ModLoader
var _mod_runtime: ModRuntime

@onready var _title: Label = %Title


func _ready() -> void:
	_title.text = tr("GAME_TITLE")
	_mod_loader = ModLoader.new()
	_mod_runtime = _mod_loader.load_mods(GameSettings.enabled_mods)

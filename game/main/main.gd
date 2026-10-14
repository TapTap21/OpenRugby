class_name Main
extends Node
## Entry scene of OpenRugby. Will become the scene router; for now it only shows a title label.

@onready var _title: Label = %Title


func _ready() -> void:
	_title.text = tr("OpenRugby")

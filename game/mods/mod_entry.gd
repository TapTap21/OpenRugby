class_name ModEntry
extends RefCounted
## Base class for mod entry scripts (layer 3).
##
## A mod with capability [code]scripts[/code] names an entry script in [code]mod.json[/code]; that
## script extends [ModEntry] and should not declare [code]class_name[/code]. Script mods run
## arbitrary GDScript; there is no sandbox.


## Called once after the mod's data and asset layers are applied. Register hooks and connect
## events through [param _api] here.
func _mod_init(_api: ModApi) -> void:
	pass


## Called when the runtime is reverted, in reverse load order.
func _mod_shutdown() -> void:
	pass

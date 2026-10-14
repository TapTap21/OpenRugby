extends RefCounted
## Fixture entry script that does not extend ModEntry, so the loader must reject it.


func _mod_init(_api: Variant) -> void:
	pass

extends ModEntry
## Fixture script mod: registers a hook on a point that is not declared.


func _mod_init(api: ModApi) -> void:
	var err: Error = api.register_hook(&"test.not_declared", _on_never, 0)
	Engine.set_meta("fx_undeclared_error", int(err))


func _on_never(value: Variant) -> Variant:
	return value

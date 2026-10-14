extends ModEntry
## Fixture script mod: FILTER hook on match.flow_config at priority -5 (runs first).

const HOOK_PRIORITY: int = -5


func _mod_init(api: ModApi) -> void:
	if api.register_hook(&"match.flow_config", _on_flow_config, HOOK_PRIORITY) != OK:
		push_error("fx-delta: register_hook failed")


func _on_flow_config(flow: Resource, _config: Resource) -> Resource:
	var trace: String = str(flow.get_meta("trace", ""))
	flow.set_meta("trace", trace + "delta,")
	return flow

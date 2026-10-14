extends ModEntry
## Fixture script mod: FILTER hook on match.flow_config (priority 0) and a match_finished listener.


func _mod_init(api: ModApi) -> void:
	var init_count: int = Engine.get_meta("fx_gamma_init_count", 0)
	Engine.set_meta("fx_gamma_init_count", init_count + 1)
	if api.register_hook(&"match.flow_config", _on_flow_config, 0) != OK:
		push_error("fx-gamma: register_hook failed")
	if api.connect_event(&"match_finished", _on_match_finished) != OK:
		push_error("fx-gamma: connect_event failed")


func _mod_shutdown() -> void:
	var shutdown_count: int = Engine.get_meta("fx_gamma_shutdown_count", 0)
	Engine.set_meta("fx_gamma_shutdown_count", shutdown_count + 1)


func _on_flow_config(flow: Resource, _config: Resource) -> Resource:
	var trace: String = str(flow.get_meta("trace", ""))
	flow.set_meta("trace", trace + "gamma,")
	return flow


func _on_match_finished(_final_tick: int) -> void:
	var finished: int = Engine.get_meta("fx_gamma_finished_count", 0)
	Engine.set_meta("fx_gamma_finished_count", finished + 1)

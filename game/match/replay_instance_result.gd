class_name ReplayInstanceResult
extends RefCounted
## Result of constructing an independent participant for replay.

var ok: bool:
	get:
		return _ok
var instance: SimSystem:
	get:
		return _instance
var error: Error:
	get:
		return _error
var owned_provider_claims: Array[ProviderClaim]:
	get:
		return _owned_provider_claims.duplicate()

var _ok: bool
var _instance: SimSystem
var _error: Error
var _owned_provider_claims: Array[ProviderClaim]


func _init(
	p_ok: bool, p_instance: SimSystem, p_error: Error, p_owned_provider_claims: Array[ProviderClaim]
) -> void:
	_ok = p_ok
	_instance = p_instance
	_error = p_error
	_owned_provider_claims = p_owned_provider_claims.duplicate()

class_name ReplayValidationAuthority
extends RefCounted
## Private replay-build registry boundary shared by its sim and replay codec.

var _registered_tokens_by_nonce: Dictionary[int, ReplayValidationToken] = {}


## Creates an empty authority for one replay build.
func _init() -> void:
	pass

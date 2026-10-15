class_name ProviderClaim
extends RefCounted
## Stable identity and exact object ownership claim for one injected provider.

var provider: RefCounted:
	get:
		return _provider
var stable_provider_id: String:
	get:
		return _stable_provider_id
var provider_version: String:
	get:
		return _provider_version
var transaction_capability: int:
	get:
		return _transaction_capability
var configuration_fingerprint: String:
	get:
		return _configuration_fingerprint
var deterministic_initial_state_fingerprint: String:
	get:
		return _deterministic_initial_state_fingerprint

var _provider: RefCounted
var _stable_provider_id: String
var _provider_version: String
var _transaction_capability: int
var _configuration_fingerprint: String
var _deterministic_initial_state_fingerprint: String


func _init(
	p_provider: RefCounted,
	p_stable_provider_id: String,
	p_provider_version: String,
	p_transaction_capability: int,
	p_configuration_fingerprint: String,
	p_deterministic_initial_state_fingerprint: String
) -> void:
	_provider = p_provider
	_stable_provider_id = p_stable_provider_id
	_provider_version = p_provider_version
	_transaction_capability = p_transaction_capability
	_configuration_fingerprint = p_configuration_fingerprint
	_deterministic_initial_state_fingerprint = p_deterministic_initial_state_fingerprint


## True when the provider and every stable identity field are present.
func is_valid() -> bool:
	return (
		provider != null
		and not stable_provider_id.is_empty()
		and not provider_version.is_empty()
		and (
			transaction_capability
			in [
				TransactionCapability.COMPLETE_TRANSACTIONAL,
				TransactionCapability.EXPLICITLY_STATELESS
			]
		)
		and not configuration_fingerprint.is_empty()
		and not deterministic_initial_state_fingerprint.is_empty()
	)

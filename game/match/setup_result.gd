class_name SetupResult
extends RefCounted
## Immutable setup status and participant/provider identity claims.

var ok: bool:
	get:
		return _ok
var error: Error:
	get:
		return _error
var capability: int:
	get:
		return _capability
var participant_claim: ParticipantClaim:
	get:
		return _participant_claim
var owned_provider_claims: Array[ProviderClaim]:
	get:
		return _owned_provider_claims.duplicate()

var _ok: bool
var _error: Error
var _capability: int
var _participant_claim: ParticipantClaim
var _owned_provider_claims: Array[ProviderClaim]


func _init(
	p_ok: bool,
	p_error: Error,
	p_capability: int,
	p_participant_claim: ParticipantClaim,
	p_owned_provider_claims: Array[ProviderClaim]
) -> void:
	_ok = p_ok
	_error = p_error
	_capability = p_capability
	_participant_claim = p_participant_claim
	_owned_provider_claims = p_owned_provider_claims.duplicate()


## True when the result shape matches its declared success/failure state.
func is_well_formed() -> bool:
	if ok:
		if error != OK or participant_claim == null or not participant_claim.is_valid():
			return false
		if capability == TransactionCapability.UNSUPPORTED:
			return false
		for claim: ProviderClaim in _owned_provider_claims:
			if claim == null or not claim.is_valid():
				return false
		return true
	return (
		error != OK
		and capability == TransactionCapability.UNSUPPORTED
		and participant_claim == null
		and _owned_provider_claims.is_empty()
	)

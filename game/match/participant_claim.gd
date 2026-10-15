class_name ParticipantClaim
extends RefCounted
## Stable participant identity used when validating and fingerprinting a simulation setup.

var stable_participant_id: String:
	get:
		return _stable_participant_id
var participant_version: String:
	get:
		return _participant_version
var configuration_fingerprint: String:
	get:
		return _configuration_fingerprint
var deterministic_initial_state_fingerprint: String:
	get:
		return _deterministic_initial_state_fingerprint

var _stable_participant_id: String
var _participant_version: String
var _configuration_fingerprint: String
var _deterministic_initial_state_fingerprint: String


func _init(
	p_stable_participant_id: String,
	p_participant_version: String,
	p_configuration_fingerprint: String,
	p_deterministic_initial_state_fingerprint: String
) -> void:
	_stable_participant_id = p_stable_participant_id
	_participant_version = p_participant_version
	_configuration_fingerprint = p_configuration_fingerprint
	_deterministic_initial_state_fingerprint = p_deterministic_initial_state_fingerprint


## True when every identity field is present.
func is_valid() -> bool:
	return (
		not stable_participant_id.is_empty()
		and not participant_version.is_empty()
		and not configuration_fingerprint.is_empty()
		and not deterministic_initial_state_fingerprint.is_empty()
	)

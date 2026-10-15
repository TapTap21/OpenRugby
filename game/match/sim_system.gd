class_name SimSystem
extends RefCounted
## Base class for ordered simulation participants.


## Stable diagnostic identifier used in snapshots.
func system_id() -> StringName:
	return &"system"


## Optional stable participant identity known before setup; empty when setup must supply it.
func participant_id_hint() -> String:
	return ""


## Declares transaction capability and stable setup identity.
func setup(_sim: MatchSim) -> SetupResult:
	return SetupResult.new(false, ERR_UNCONFIGURED, TransactionCapability.UNSUPPORTED, null, [])


## Legacy successful tick hook retained for existing subclasses.
func tick(_sim: MatchSim) -> void:
	pass


## Checked tick entry point; by default it calls the legacy [method tick] hook.
func tick_checked(sim: MatchSim, _context: SimTickContext) -> SystemTickResult:
	tick(sim)
	return SystemTickResult.new(true, OK)


## Captures all state that can affect a future deterministic tick.
func checkpoint() -> CheckpointResult:
	return CheckpointResult.new(true, {}, OK)


## Restores the value previously returned by [method checkpoint].
func restore(_checkpoint_value: Variant) -> Error:
	return ERR_UNCONFIGURED


## Creates an independent initial participant for replay.
func create_replay_instance() -> ReplayInstanceResult:
	return ReplayInstanceResult.new(false, null, ERR_UNCONFIGURED, [])


## Returns this participant's deterministic state for snapshots and hashing.
func snapshot() -> Dictionary:
	return {}

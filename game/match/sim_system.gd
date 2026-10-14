class_name SimSystem
extends RefCounted
## Base class for simulation subsystems (ball, players, rules, AI) registered on a [MatchSim].
##
## Systems tick in registration order, which is part of the determinism contract.


## Stable identifier used in snapshots.
func system_id() -> StringName:
	return &"system"


## Called once when the system is added to [param _sim].
func setup(_sim: MatchSim) -> void:
	pass


## Called once per simulation tick, after the input frame has been applied.
func tick(_sim: MatchSim) -> void:
	pass


## Returns this system's state for hashing and snapshots.
func snapshot() -> Dictionary:
	return {}


## True only when this system has no mutable state a failed S2 tick could affect.
func is_transaction_stateless() -> bool:
	return false


## True only when [method snapshot] contains all state that can affect a future tick.
func snapshot_is_complete() -> bool:
	return false


## Captures state before a composed S2 tick; stateful systems must override this method.
func transaction_checkpoint() -> SimDependencyCheckpoint:
	return SimDependencyCheckpoint.stateless() if is_transaction_stateless() else null


## Restores a checkpoint; stateful systems must override this method.
func restore_transaction_checkpoint(checkpoint: SimDependencyCheckpoint) -> bool:
	return is_transaction_stateless() and checkpoint != null and checkpoint.complete

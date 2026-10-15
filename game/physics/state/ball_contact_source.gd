class_name BallContactSource
extends RefCounted
## Deterministic, scene-free mesh contact source injected by stadium integration.


## Returns stable-id contacts for the supplied body pose in deterministic detector order.
func detect_contacts(_position_m: Vector3, _orientation: Quaternion) -> Array[BallContact]:
	return []


## True when this source owns the y = 0 plane contacts for its configured geometry.
func provides_ground_plane_contacts() -> bool:
	return false


## True when this source can supply the contact subset described by its identity and snapshot.
func is_available() -> bool:
	return false


## Stable geometry identity included in the owner system snapshot.
func snapshot() -> Dictionary:
	return {}


## True only when contact detection has no state outside its deterministic arguments.
func is_transaction_stateless() -> bool:
	return false


## True only when [method snapshot] includes every future-affecting source state value.
func snapshot_is_complete() -> bool:
	return is_transaction_stateless()


## Captures injected source state before a transactional operation.
func transaction_checkpoint() -> SimDependencyCheckpoint:
	return SimDependencyCheckpoint.stateless() if is_transaction_stateless() else null


## Restores a checkpoint; stateful providers must override this method.
func restore_transaction_checkpoint(checkpoint: SimDependencyCheckpoint) -> bool:
	return is_transaction_stateless() and checkpoint != null and checkpoint.complete

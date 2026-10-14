class_name BallContactSolver
extends RefCounted
## Injected contact solver contract; Classic LCP response is unavailable until implemented.


## Solves ordered rows. On false, it must leave state and its own future-affecting state unchanged.
func solve_contacts(
	_state: BallState, _contacts: Array[BallContact], _responses: Array[ContactResult], _dt: float
) -> bool:
	return false


## True only when an owner has supplied a deterministic, contract-complete contact solver.
func is_available() -> bool:
	return false


## Includes solver tuning and state in deterministic snapshots.
func snapshot() -> Dictionary:
	return {}


## True only when contact solving has no state outside its deterministic arguments.
func is_transaction_stateless() -> bool:
	return false


## True only when [method snapshot] includes every future-affecting solver state value.
func snapshot_is_complete() -> bool:
	return is_transaction_stateless()


## Captures injected solver state before a transactional operation.
func transaction_checkpoint() -> SimDependencyCheckpoint:
	return SimDependencyCheckpoint.stateless() if is_transaction_stateless() else null


## Restores a checkpoint; stateful solvers must override this method.
func restore_transaction_checkpoint(checkpoint: SimDependencyCheckpoint) -> bool:
	return is_transaction_stateless() and checkpoint != null and checkpoint.complete

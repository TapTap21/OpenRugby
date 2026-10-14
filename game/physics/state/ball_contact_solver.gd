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

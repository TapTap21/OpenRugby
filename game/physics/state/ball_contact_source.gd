class_name BallContactSource
extends RefCounted
## Deterministic, scene-free mesh contact source injected by stadium integration.


## Returns stable-id contacts for the supplied body pose in deterministic detector order.
func detect_contacts(_position_m: Vector3, _orientation: Quaternion) -> Array[BallContact]:
	return []


## Stable geometry identity included in the owner system snapshot.
func snapshot() -> Dictionary:
	return {}

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

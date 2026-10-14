class_name SimRng
extends RefCounted
## Deterministic random number source owned by one match simulation.
##
## Wraps a single PCG32 generator seeded from the match config. All simulation randomness must
## come from an instance of this class so that a seed and an input log reproduce a match exactly.

## The seed this generator was constructed with.
var seed: int:
	get:
		return _seed

var _seed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_seed: int = 0) -> void:
	_seed = p_seed
	_rng.seed = p_seed


## Returns the next unsigned 32-bit integer.
func next_int() -> int:
	return _rng.randi()


## Returns an integer in [from, to], both inclusive.
func range_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Returns a float in [0, 1).
func next_float() -> float:
	return _rng.randf()


## Returns a float in [from, to].
func range_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## Returns true when the next float draw is below [param probability].
func chance(probability: float) -> bool:
	return next_float() < probability


## Returns the internal generator state so it can be restored later.
func get_state() -> int:
	return _rng.state


## Restores a state previously returned by [method get_state].
func set_state(state: int) -> void:
	_rng.state = state

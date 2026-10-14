class_name SimDependencyCheckpoint
extends RefCounted
## Typed transaction token for a stateful deterministic provider or system.

var state: Dictionary = {}
var complete: bool = false


## Builds a complete empty token for a dependency explicitly declared stateless.
static func stateless() -> SimDependencyCheckpoint:
	var checkpoint: SimDependencyCheckpoint = SimDependencyCheckpoint.new()
	checkpoint.complete = true
	return checkpoint

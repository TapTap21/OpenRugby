class_name PickupResult
extends RefCounted
## Typed physical pickup decision; legality and knock-on remain outside S2.

enum Outcome { UNRESOLVED, REJECTED_HELD, REJECTED_HEIGHT, REJECTED_CAPSULE, ACCEPTED }
var outcome: Outcome = Outcome.UNRESOLVED
var accepted: bool = false


func snapshot() -> Dictionary:
	return {"outcome": outcome, "accepted": accepted}

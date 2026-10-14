class_name CatchResult
extends RefCounted
## Typed physical catch/fumble result. Candidate choice remains an injected unresolved policy.

enum Outcome { UNRESOLVED, CAUGHT, DROPPED, FUMBLED }
var outcome: Outcome = Outcome.UNRESOLVED
var probability: float = NAN
var resolved: bool = false


func snapshot() -> Dictionary:
	return {"outcome": outcome, "probability": probability, "resolved": resolved}

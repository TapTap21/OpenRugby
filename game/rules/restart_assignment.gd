class_name RestartAssignment
extends RefCounted
## Typed restart requested by the score/referee bridge.

enum Kind { KICK_OFF = 1, CONVERSION = 10 }

var kind: Kind = Kind.KICK_OFF
var team_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var has_position: bool = false
var cause: RefereeReport.Decision = RefereeReport.Decision.KICK_OFF


## Validates an assignment without assuming a kickoff spot.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if kind != Kind.KICK_OFF and kind != Kind.CONVERSION:
		errors += PackedStringArray(["unsupported restart kind"])
	if team_id == &"":
		errors += PackedStringArray(["team_id is required"])
	if has_position and not position.is_finite():
		errors += PackedStringArray(["position must be finite"])
	return errors

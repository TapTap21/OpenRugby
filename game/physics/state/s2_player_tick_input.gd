class_name S2PlayerTickInput
extends RefCounted
## Owner-resolved per-tick locomotion and fatigue inputs for one player.

var player_id: StringName = &""
var sprint_request: int = -1
var urgency: float = NAN
var fatigue_snapshot: PlayerFatigueSnapshot


## True when all caller-owned values for the next locomotion tick are resolved.
func is_valid() -> bool:
	return (
		player_id != &""
		and sprint_request >= 0
		and sprint_request <= 1
		and is_finite(urgency)
		and urgency >= 0.0
		and urgency <= 1.0
		and fatigue_snapshot != null
		and fatigue_snapshot.is_valid()
		and fatigue_snapshot.player_id == player_id
	)


## Stable command and replay representation.
func snapshot() -> Dictionary:
	return {
		"player_id": player_id,
		"sprint_request": sprint_request,
		"urgency": urgency,
		"fatigue": fatigue_snapshot.snapshot() if fatigue_snapshot != null else {},
	}

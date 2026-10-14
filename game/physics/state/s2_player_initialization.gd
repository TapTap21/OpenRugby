class_name S2PlayerInitialization
extends RefCounted
## Owner-supplied initial locomotion state and pre-advance fatigue snapshot.

var player: PlayerMotionState


## Validates the complete initial input before a player joins the S2 system.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if player == null:
		return PackedStringArray(["player motion state is missing"])
	if player.player_id == &"" or player.team_id == &"" or player.shirt_number < 0:
		errors.append("player identity must include team, shirt and stable id")
	if not player.initialized or player.sprint_request < 0 or player.sprint_request > 1:
		errors.append("player motion and initial sprint request are unresolved")
	if (
		player.on_pitch
		and (
			player.fatigue_snapshot == null
			or not player.fatigue_snapshot.is_valid()
			or player.fatigue_snapshot.team_id != player.team_id
			or player.fatigue_snapshot.player_id != player.player_id
			or player.fatigue_snapshot.shirt_number != player.shirt_number
		)
	):
		errors.append("player requires a matching valid pre-advance fatigue snapshot")
	if (
		not player.position_m.is_finite()
		or not is_finite(player.heading_turns)
		or not is_finite(player.desired_heading_turns)
		or not is_finite(player.speed_m_s)
		or player.speed_m_s < 0.0
		or not is_finite(player.speed_stat)
		or not is_finite(player.acceleration_stat)
		or not is_finite(player.urgency)
		or player.speed_stat < 0.0
		or player.speed_stat > 100.0
		or player.acceleration_stat < 0.0
		or player.acceleration_stat > 100.0
		or player.urgency < 0.0
		or player.urgency > 1.0
		or (
			player.sprint_energy_initialized
			and (
				(player.on_pitch and player.fatigue_snapshot == null)
				or not is_finite(player.sprint_energy)
				or player.sprint_energy < -1.0
				or (
					player.fatigue_snapshot != null
					and player.sprint_energy > player.fatigue_snapshot.energy_cap
				)
			)
		)
	):
		errors.append(
			"player initial motion values and locomotion inputs must be finite and bounded"
		)
	return errors


## Returns a detached sim-owned copy so callers never retain mutable S2 state.
func copy_player() -> PlayerMotionState:
	if player == null:
		return null
	return player.duplicate_state()


## Snapshot of the injected immutable setup values.
func snapshot() -> Dictionary:
	return player.snapshot() if player != null else {}

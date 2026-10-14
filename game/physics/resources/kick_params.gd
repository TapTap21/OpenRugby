class_name KickParams
extends Resource
## Patchable kick tables and launch modifiers from RE 06 §2.6.

@export var profiles: Array[KickProfile] = []
@export var aim_error_scale_degrees: float = 8.294
@export
var drop_kick_difficulty_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 1.5, 2.0, 3.0])
@export var grubber_elevation_jitter_degrees: float = 5.0
@export var random_spin_limit_rad_s: float = 15.0
@export var fixed_spin_rad_s: float = 1.5
@export var grubber_spin_rad_s: float = -0.5
@export var quick_tap_spin_rad_s: float = 5.0
@export var place_speed_min_m_s: float = 10.0
@export var place_speed_max_m_s: float = 33.0
@export var place_needle_error_full_factor: float = 1.0
@export var place_needle_floor: float = 0.75
@export var ai_place_spread: float = 0.05


static func create_classic() -> KickParams:
	var result: KickParams = KickParams.new()
	var rows: Array[Array] = [
		[1, 16.081, 22.304, 42.316, 42.5, true],
		[2, 14.5, 22.175, 68.478, 76.064, true],
		[3, 9.79, 16.0, 2.019, 10.8, false],
		[4, 10.0, 33.0, 30.0, 60.0, true],
		[5, 10.0, 33.0, 30.0, 60.0, true],
		[6, 12.2, 12.2, 10.0, 10.0, false],
		[7, 10.0, 20.0, 40.0, 80.0, false],
		[8, 12.998, 21.0, 45.0, 50.87, true],
		[9, 13.0, 20.1, 50.416, 50.489, true],
		[10, 10.0, 20.0, 40.0, 80.0, false],
		[11, 10.0, 20.0, 40.0, 80.0, false],
		[12, 10.0, 20.0, 40.0, 80.0, false],
	]
	for row: Array in rows:
		var profile: KickProfile = KickProfile.new()
		profile.type_id = row[0]
		profile.speed_low_m_s = row[1]
		profile.speed_high_m_s = row[2]
		profile.elevation_low_degrees = row[3]
		profile.elevation_high_degrees = row[4]
		profile.power_rating_applies = row[5]
		result.profiles += [profile]
	return result


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if drop_kick_difficulty_multipliers.size() < 4:
		errors += PackedStringArray(["drop kick difficulty table must contain four entries"])
	for profile: KickProfile in profiles:
		if (
			profile.type_id < 0
			or profile.speed_low_m_s > profile.speed_high_m_s
			or profile.elevation_low_degrees > profile.elevation_high_degrees
		):
			errors += PackedStringArray(["kick profile has invalid ranges"])
	return errors


func get_profile(type_id: int) -> KickProfile:
	for profile: KickProfile in profiles:
		if profile.type_id == type_id:
			return profile
	return null

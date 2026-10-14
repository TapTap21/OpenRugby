class_name BallPhysicsParams
extends Resource
## Mod-patchable ball constants from RE 06 §2.3. Unresolved policies stay explicit.

@export var mass_kg: float = 0.435
@export var semi_axes_m: Vector3 = Vector3(0.095, 0.145, 0.095)
@export var inertia_kg_m2: float = 0.006097
@export var gravity_m_s2: Vector3 = Vector3(0.0, -9.8, 0.0)
@export var solver_step_numerator: int = 1
@export var solver_step_denominator: int = 200
@export var air_density_kg_m3: float = 1.29
@export var reference_area_slow_m2: float = 0.045
@export var wind_km_h_to_m_s: float = 1.0 / 3.6
@export var max_contacts_per_step: int = 16
@export var goal_post_center_x_m: float = 2.845
## RE 06 §2.1 observed post spacing, metres.
@export var goal_width_m: float = 5.6
@export var goal_line_z_m: float = 50.0
@export var post_hit_band_m: float = 0.3
## RE 06 §2.4 observed event envelope around the goal line and centre, metres.
@export var post_monitor_range_m: float = 5.0
@export var post_low_zone_height_m: float = 2.26
@export var crossbar_height_m: float = 3.0
@export var drag_speed_low_m_s: float = 15.0
@export var drag_speed_high_m_s: float = 20.5
@export var drag_coefficient_low: float = 0.5
@export var drag_coefficient_high: float = 0.2
@export var initial_spin_jitter_rad_s: float = 0.05
@export var predictor_rest_height_m: float = 0.1
@export var predictor_roll_hop_time_s: float = 0.01
@export var drag_reference_speed_threshold_m_s: float = 0.01
@export var predictor_roll_acceleration: float = 0.8
@export var predictor_roll_restitution: float = 0.55
@export var predictor_roll_horizontal_retention: float = 0.885


## Returns validation errors. These are safety checks, not a substitute for injected unknown policy.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if mass_kg <= 0.0:
		errors += PackedStringArray(["mass_kg must be positive"])
	if inertia_kg_m2 <= 0.0:
		errors += PackedStringArray(["inertia_kg_m2 must be positive"])
	if solver_step_numerator <= 0 or solver_step_denominator <= 0:
		errors += PackedStringArray(["solver step must be positive"])
	if max_contacts_per_step <= 0:
		errors += PackedStringArray(["max_contacts_per_step must be positive"])
	if not gravity_m_s2.is_finite():
		errors += PackedStringArray(["gravity_m_s2 must be finite"])
	if (
		not semi_axes_m.is_finite()
		or semi_axes_m.x <= 0.0
		or semi_axes_m.y <= 0.0
		or semi_axes_m.z <= 0.0
	):
		errors += PackedStringArray(["semi_axes_m must be finite and positive"])
	return errors

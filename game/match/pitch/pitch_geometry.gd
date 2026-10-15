class_name PitchGeometry
extends Resource
## Match pitch dimensions in metres and helpers to classify points.
##
## Origin is the centre spot, +Y is up, X runs across the pitch, and +Z runs toward end 1.

## Try line to try line. RE 06 §2.1: z = ±50 m.
@export var field_length: float = 100.0
## Touchline to touchline. RE 06 §2.1 derives ±33.7 m from the observed pitch-line model.
@export var field_width: float = 67.4
## Try line to dead-ball line. RE 06 §2.1: 14.1 m.
@export var in_goal_depth: float = 14.1
## Distance from each try line to its 22 m line. RE 06 §2.1: line at z = ±28 m.
@export var line_22_from_try: float = 22.0
@export var line_10_from_halfway: float = 10.0
@export var line_5_from_try: float = 5.0
@export var line_15_from_touch: float = 15.0
@export var line_5_from_touch: float = 5.0
## Gap between the inside faces of the goal uprights. RE 06 §2.1: 5.6 m.
@export var goal_post_gap: float = 5.6
## Top of the crossbar. RE 06 §2.1: 3.0 m.
@export var crossbar_height: float = 3.0
## Upright radius from the stadium collision mesh. RE 06 §2.1: about 0.045 m.
@export var goal_post_radius: float = 0.045
## Upright bottom and top from the stadium collision mesh; venue-specific evidence.
@export var goal_post_bottom: float = 2.0
@export var goal_post_top: float = 13.41
## Side length and height of the post pad boxes in the observed stadium mesh.
@export var goal_pad_size: float = 0.49
@export var goal_pad_height: float = 2.0


## Half of the field length.
func half_length() -> float:
	return field_length / 2.0


## Half of the field width.
func half_width() -> float:
	return field_width / 2.0


## Z coordinate of the try line at [param end] (1 or -1).
func try_line_z(end: int) -> float:
	return end * half_length()


## Z coordinate of the dead-ball line at [param end].
func dead_ball_line_z(end: int) -> float:
	return end * (half_length() + in_goal_depth)


## Z coordinate of the 22 metre line at [param end].
func line_22_z(end: int) -> float:
	return end * (half_length() - line_22_from_try)


## True when [param p] is inside the field of play (try line and touchlines are outside).
func is_in_field_of_play(p: Vector3) -> bool:
	return absf(p.z) < half_length() and absf(p.x) < half_width()


## True when [param p] is in the in-goal area at [param end] (the try line belongs to in-goal).
func is_in_goal(p: Vector3, end: int) -> bool:
	var depth: float = end * p.z
	return (
		depth >= half_length()
		and depth < half_length() + in_goal_depth
		and absf(p.x) < half_width()
	)


## True when [param p] is in touch (the touchline belongs to touch).
func is_in_touch(p: Vector3) -> bool:
	return absf(p.x) >= half_width() and absf(p.z) < half_length()


## True when [param p] is at or beyond the dead-ball line of either end.
func is_beyond_dead_ball_line(p: Vector3) -> bool:
	return absf(p.z) >= half_length() + in_goal_depth


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var positive: Dictionary[String, float] = {
		"field_length": field_length,
		"field_width": field_width,
		"in_goal_depth": in_goal_depth,
		"goal_post_gap": goal_post_gap,
		"crossbar_height": crossbar_height,
		"goal_post_radius": goal_post_radius,
		"goal_post_top": goal_post_top,
		"goal_pad_size": goal_pad_size,
		"goal_pad_height": goal_pad_height,
	}
	for key: String in positive:
		if positive[key] <= 0.0:
			errors += PackedStringArray(["%s must be positive" % key])
	if goal_post_bottom < 0.0:
		errors += PackedStringArray(["goal_post_bottom must not be negative"])
	if goal_post_bottom >= goal_post_top:
		errors += PackedStringArray(["goal_post_bottom must be below goal_post_top"])
	if line_22_from_try >= half_length():
		errors += PackedStringArray(["line_22_from_try must be less than half the field length"])
	if 2.0 * line_15_from_touch >= field_width:
		errors += PackedStringArray(["line_15_from_touch must be less than half the field width"])
	return errors

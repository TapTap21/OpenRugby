class_name PitchGeometry
extends Resource
## Pitch dimensions in metres and helpers to classify points.
##
## Origin is the centre of the halfway line, +Y is up, X runs along the length (try lines at
## x = +/- length / 2; end is 1 for +X and -1 for -X) and Z runs across (touchlines at
## z = +/- width / 2).

## Try line to try line (TBC-RE).
@export var field_length: float = 100.0
## Touchline to touchline (TBC-RE).
@export var field_width: float = 70.0
## Try line to dead-ball line (law range 6..22, TBC-RE).
@export var in_goal_depth: float = 10.0
@export var line_22_from_try: float = 22.0
@export var line_10_from_halfway: float = 10.0
@export var line_5_from_try: float = 5.0
@export var line_15_from_touch: float = 15.0
@export var line_5_from_touch: float = 5.0
## Gap between the inside edges of the posts (TBC-RE).
@export var goal_post_gap: float = 5.6
@export var crossbar_height: float = 3.0
## PROVISIONAL, visual only.
@export var goal_post_height: float = 16.0


## Half of the field length.
func half_length() -> float:
	return field_length / 2.0


## Half of the field width.
func half_width() -> float:
	return field_width / 2.0


## X coordinate of the try line at [param end] (1 or -1).
func try_line_x(end: int) -> float:
	return end * half_length()


## X coordinate of the dead-ball line at [param end].
func dead_ball_line_x(end: int) -> float:
	return end * (half_length() + in_goal_depth)


## X coordinate of the 22 metre line at [param end].
func line_22_x(end: int) -> float:
	return end * (half_length() - line_22_from_try)


## True when [param p] is inside the field of play (try line and touchlines are outside).
func is_in_field_of_play(p: Vector3) -> bool:
	return absf(p.x) < half_length() and absf(p.z) < half_width()


## True when [param p] is in the in-goal area at [param end] (the try line belongs to in-goal).
func is_in_goal(p: Vector3, end: int) -> bool:
	var depth: float = end * p.x
	return (
		depth >= half_length()
		and depth < half_length() + in_goal_depth
		and absf(p.z) < half_width()
	)


## True when [param p] is in touch (the touchline belongs to touch).
func is_in_touch(p: Vector3) -> bool:
	return absf(p.z) >= half_width() and absf(p.x) < half_length()


## True when [param p] is at or beyond the dead-ball line of either end.
func is_beyond_dead_ball_line(p: Vector3) -> bool:
	return absf(p.x) >= half_length() + in_goal_depth


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var positive: Dictionary[String, float] = {
		"field_length": field_length,
		"field_width": field_width,
		"in_goal_depth": in_goal_depth,
		"goal_post_gap": goal_post_gap,
		"crossbar_height": crossbar_height,
		"goal_post_height": goal_post_height,
	}
	for key: String in positive:
		if positive[key] <= 0.0:
			errors += PackedStringArray(["%s must be positive" % key])
	if line_22_from_try >= half_length():
		errors += PackedStringArray(["line_22_from_try must be less than half the field length"])
	if 2.0 * line_15_from_touch >= field_width:
		errors += PackedStringArray(["line_15_from_touch must be less than half the field width"])
	return errors

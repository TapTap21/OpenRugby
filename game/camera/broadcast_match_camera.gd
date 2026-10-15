class_name BroadcastMatchCamera
extends Camera3D
## Tunable sideline camera for an active match.

enum Preset { TRUCK, SIDE, BROADCAST, CHASE, END_ON, HOVER }
enum Zoom { STANDARD, WIDE, SUPER_WIDE, NEAR, SUPER_NEAR }

@export var preset: Preset = Preset.BROADCAST
@export var zoom: Zoom = Zoom.STANDARD
@export var follow_offset: Vector3 = Vector3(0.0, 28.0, 58.0)
@export var look_ahead: float = 8.0
@export_range(0.1, 20.0) var follow_smoothing: float = 5.0
@export_range(30.0, 90.0) var base_fov: float = 48.0

var _follow_target: Node3D


func _ready() -> void:
	current = true
	_update_lens()
	if _follow_target != null:
		_update_follow(1.0)


func _process(delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	_update_follow(1.0 - exp(-delta * follow_smoothing))


## Selects the actor that drives the broadcast frame.
func set_follow_target(target: Node3D) -> void:
	_follow_target = target
	if is_inside_tree() and _follow_target != null:
		_update_follow(1.0)


## Applies one of the observed camera presets and zoom modes.
func set_camera_options(camera_preset: Preset, camera_zoom: Zoom) -> void:
	preset = camera_preset
	zoom = camera_zoom
	_update_lens()


func _update_follow(weight: float) -> void:
	var target_position: Vector3 = _follow_target.global_position
	var desired_position: Vector3 = target_position + _effective_offset()
	global_position = global_position.lerp(desired_position, weight)
	var look_target: Vector3 = target_position + Vector3(look_ahead, 0.0, 0.0)
	look_at(look_target, Vector3.UP)


func _effective_offset() -> Vector3:
	var offset: Vector3 = follow_offset
	if preset == Preset.CHASE:
		offset = Vector3(0.0, 6.0, -14.0)
	elif preset == Preset.END_ON:
		offset = Vector3(45.0, 24.0, 0.0)
	elif preset == Preset.HOVER:
		offset = Vector3(0.0, 110.0, 0.0)
	offset.z += _zoom_offset()
	return offset


func _zoom_offset() -> float:
	var offsets: Array[float] = []
	match preset:
		Preset.TRUCK, Preset.SIDE, Preset.BROADCAST:
			offsets = [12.0, 16.0, 20.0, 8.0, 4.0]
		Preset.CHASE:
			offsets = [-3.0, 0.0, 5.0, -5.0, -8.0]
		Preset.END_ON:
			offsets = [4.0, 8.0, 14.0, 0.0, -4.0]
		Preset.HOVER:
			offsets = [-6.0, -2.0, 4.0, -10.0, -14.0]
	return offsets[zoom]


func _update_lens() -> void:
	fov = base_fov
	if preset == Preset.HOVER:
		fov = 62.0
	elif preset == Preset.CHASE:
		fov = 58.0

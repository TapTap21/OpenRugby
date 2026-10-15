extends Node3D
## A disposable generated-primitive sandbox for placeholder movement and ball behavior.

signal try_scored

const PITCH_SCENE: PackedScene = preload("res://game/prototype/prototype_pitch.tscn")
const PrototypePitchVisual = preload("res://game/prototype/prototype_pitch_visual.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/prototype/athlete_red.tscn")
const OPPONENT_SCENE: PackedScene = preload("res://game/prototype/athlete_blue.tscn")
const BALL_SCENE: PackedScene = preload("res://game/prototype/rugby_ball.tscn")

@export var tuning: PrototypeTuning

var _player: CharacterBody3D
var _opponent: CharacterBody3D
var _ball: MeshInstance3D
var _ball_velocity: Vector3 = Vector3.ZERO
var _ball_carrier: CharacterBody3D
var _former_carrier: CharacterBody3D
var _pickup_grace_remaining: float = 0.0
var _drop_recovery_delay_frames: int = 0
var _tackle_contact_armed: bool = true
var _camera: Camera3D
var _status_label: Label
var _score_label: Label
var _player_score: int = 0


func _ready() -> void:
	if tuning == null:
		tuning = PrototypeTuning.new()
	_build_world()
	_reset_play()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"kick"):
		_kick_ball()
	_move_player()
	_move_opponent()
	_update_ball(delta)
	_follow_camera()
	_check_try_line()


func _build_world() -> void:
	var field_length: float = tuning.field_half_length * 2.0
	var field_width: float = tuning.field_half_width * 2.0
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Ground"
	add_child(floor_body)
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(field_length, 0.3, field_width)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.15
	floor_body.add_child(floor_shape)
	var pitch: PrototypePitchVisual = PITCH_SCENE.instantiate() as PrototypePitchVisual
	add_child(pitch)
	pitch.configure(tuning.field_half_length, tuning.field_half_width, tuning.try_line_x)

	_player = _make_actor("Player", PLAYER_SCENE)
	_opponent = _make_actor("Opponent", OPPONENT_SCENE)
	_ball = BALL_SCENE.instantiate() as MeshInstance3D
	add_child(_ball)

	_camera = Camera3D.new()
	_camera.name = "SandboxCamera"
	_camera.current = true
	add_child(_camera)
	_build_hud()


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "SandboxHud"
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.02
	panel.anchor_top = 0.03
	panel.anchor_right = 0.48
	panel.anchor_bottom = 0.2
	layer.add_child(panel)
	var layout: VBoxContainer = VBoxContainer.new()
	panel.add_child(layout)
	var title: Label = Label.new()
	title.text = tr("PROTOTYPE_STATUS_TITLE")
	layout.add_child(title)
	_status_label = Label.new()
	_status_label.text = tr("PROTOTYPE_STATUS_DETAIL")
	layout.add_child(_status_label)
	var controls: Label = Label.new()
	controls.text = tr("PROTOTYPE_CONTROLS")
	layout.add_child(controls)
	_score_label = Label.new()
	_score_label.text = tr("PROTOTYPE_SCORE").format({"score": _player_score})
	layout.add_child(_score_label)


func _move_player() -> void:
	var direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var speed: float = tuning.player_speed
	if Input.is_action_pressed(&"sprint"):
		speed *= tuning.sprint_multiplier
	_player.velocity = Vector3(direction.x, 0.0, direction.y) * speed
	var _player_collision: bool = _player.move_and_slide()  # gdlint: ignore=function-variable-name
	_clamp_actor(_player)


func _move_opponent() -> void:
	var target: Vector3 = _player.global_position
	if _ball_carrier == null:
		target = _ball.global_position
	else:
		target = _ball_carrier.global_position
	var pursuit: Vector3 = target - _opponent.global_position
	pursuit.y = 0.0
	if pursuit.length_squared() > 0.01:
		_opponent.velocity = pursuit.normalized() * tuning.opponent_speed
	else:
		_opponent.velocity = Vector3.ZERO
	var _opponent_collision: bool = _opponent.move_and_slide()  # gdlint: ignore=function-variable-name
	_clamp_actor(_opponent)
	var contact_distance: float = _opponent.global_position.distance_to(_player.global_position)
	if contact_distance > tuning.carrier_drop_distance + tuning.tackle_rearm_margin:
		_tackle_contact_armed = true
	if not _tackle_contact_armed:
		return
	if _ball_carrier == _player and contact_distance <= tuning.carrier_drop_distance:
		_drop_ball(_player, _opponent)
	elif _ball_carrier == _opponent and contact_distance <= tuning.carrier_drop_distance:
		_drop_ball(_opponent, _player)


func _update_ball(delta: float) -> void:
	if _pickup_grace_remaining > 0.0:
		_pickup_grace_remaining = maxf(0.0, _pickup_grace_remaining - delta)
		if _pickup_grace_remaining == 0.0:
			_former_carrier = null
	if _ball_carrier != null:
		_ball.global_position = _ball_carrier.global_position + Vector3(0.85, 0.6, 0.0)
		_ball_velocity = Vector3.ZERO
		return
	_ball.position += _ball_velocity * delta
	_ball_velocity *= pow(tuning.ball_friction, delta * 60.0)
	_ball.position.x = clampf(_ball.position.x, -tuning.field_half_length, tuning.field_half_length)
	_ball.position.z = clampf(_ball.position.z, -tuning.field_half_width, tuning.field_half_width)
	_ball.position.y = 0.45 + minf(_ball_velocity.length() * 0.025, 0.35)
	if _drop_recovery_delay_frames > 0:
		_drop_recovery_delay_frames -= 1
		return
	if (
		_player != _former_carrier
		and (
			_ball.global_position.distance_to(_player.global_position + Vector3(0.0, 0.5, 0.0))
			<= tuning.ball_recovery_distance
		)
	):
		_set_carrier(_player)
	elif (
		_opponent != _former_carrier
		and (
			_ball.global_position.distance_to(_opponent.global_position + Vector3(0.0, 0.5, 0.0))
			<= tuning.ball_recovery_distance
		)
	):
		_set_carrier(_opponent)


func _kick_ball() -> void:
	if _ball_carrier != _player:
		return
	var direction: Vector3 = -_player.global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3.RIGHT
	direction = direction.normalized()
	var release_position: Vector3 = (
		_player.global_position + direction * 1.2 + Vector3(0.0, 0.45, 0.0)
	)
	var velocity: Vector3 = direction * tuning.kick_speed + Vector3.UP * 2.0
	_release_ball(_player, release_position, velocity)


func _check_try_line() -> void:
	if _ball_carrier != _player or _player.global_position.x < tuning.try_line_x:
		return
	_player_score += 1
	try_scored.emit()
	_score_label.text = tr("PROTOTYPE_SCORE").format({"score": _player_score})
	_reset_play()
	_status_label.text = tr("PROTOTYPE_TRY_SCORED")


func _reset_play() -> void:
	_former_carrier = null
	_pickup_grace_remaining = 0.0
	_drop_recovery_delay_frames = 0
	_tackle_contact_armed = true
	_player.position = Vector3(-2.0, 0.0, 0.0)
	_opponent.position = Vector3(7.0, 0.0, 3.0)
	_ball.position = Vector3.ZERO
	_ball_velocity = Vector3.ZERO
	_set_carrier(_player)
	if _status_label != null:
		_status_label.text = tr("PROTOTYPE_BALL_CARRIED")


func _set_carrier(carrier: CharacterBody3D) -> void:
	_ball_carrier = carrier
	_former_carrier = null
	_pickup_grace_remaining = 0.0
	_ball_velocity = Vector3.ZERO
	_status_label.text = (
		tr("PROTOTYPE_BALL_CARRIED") if carrier == _player else tr("PROTOTYPE_OPPONENT_CARRIES")
	)


func _drop_ball(former_carrier: CharacterBody3D, tackler: CharacterBody3D) -> void:
	var release_position: Vector3 = _tackle_drop_position(former_carrier, tackler)
	var midpoint: Vector3 = (former_carrier.global_position + tackler.global_position) * 0.5
	var direction: Vector3 = release_position - midpoint
	direction.y = 0.0
	direction = direction.normalized()
	var velocity: Vector3 = direction * tuning.kick_speed * 0.35 + Vector3.UP * 1.5
	_release_ball(former_carrier, release_position, velocity)
	_drop_recovery_delay_frames = 1
	_tackle_contact_armed = false


func _tackle_drop_position(former_carrier: CharacterBody3D, tackler: CharacterBody3D) -> Vector3:
	var midpoint: Vector3 = (former_carrier.global_position + tackler.global_position) * 0.5
	var separation: Vector3 = tackler.global_position - former_carrier.global_position
	separation.y = 0.0
	var side_direction: Vector3 = Vector3(-separation.z, 0.0, separation.x)
	if side_direction.length_squared() < 0.01:
		side_direction = Vector3(0.0, 0.0, 1.0)
	side_direction = side_direction.normalized()
	# This margin handles the reviewed default-size boundary case; arbitrarily narrow fields or
	# a recovery radius too large for the pitch cannot have an in-bounds safe release.
	var drop_offset: float = maxf(
		tuning.tackle_drop_clearance_distance, 1.75 * tuning.ball_recovery_distance + 0.05
	)
	var positive_position: Vector3 = _clamp_drop_position(
		midpoint + side_direction * drop_offset + Vector3(0.0, 0.45, 0.0)
	)
	var negative_position: Vector3 = _clamp_drop_position(
		midpoint - side_direction * drop_offset + Vector3(0.0, 0.45, 0.0)
	)
	var positive_clearance: float = minf(
		positive_position.distance_to(_recovery_point(former_carrier)),
		positive_position.distance_to(_recovery_point(tackler))
	)
	var negative_clearance: float = minf(
		negative_position.distance_to(_recovery_point(former_carrier)),
		negative_position.distance_to(_recovery_point(tackler))
	)
	var selected_position: Vector3 = (
		positive_position if positive_clearance >= negative_clearance else negative_position
	)
	return selected_position


func _recovery_point(actor: CharacterBody3D) -> Vector3:
	return actor.global_position + Vector3(0.0, 0.5, 0.0)


func _clamp_drop_position(position: Vector3) -> Vector3:
	position.x = clampf(position.x, -tuning.field_half_length, tuning.field_half_length)
	position.z = clampf(position.z, -tuning.field_half_width, tuning.field_half_width)
	return position


func _release_ball(
	former_carrier: CharacterBody3D, release_position: Vector3, velocity: Vector3
) -> void:
	_ball_carrier = null
	_pickup_grace_remaining = maxf(0.0, tuning.former_carrier_grace_seconds)
	_former_carrier = former_carrier if _pickup_grace_remaining > 0.0 else null
	_ball.global_position = release_position
	_ball_velocity = velocity
	_status_label.text = tr("PROTOTYPE_BALL_LOOSE")


func _follow_camera() -> void:
	_camera.position = _player.position + Vector3(0.0, 25.0, 34.0)
	_camera.look_at(_player.position + Vector3(0.0, 0.0, -4.0))


func _make_actor(actor_name: String, appearance: PackedScene) -> CharacterBody3D:
	var actor: CharacterBody3D = CharacterBody3D.new()
	actor.name = actor_name
	add_child(actor)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
	capsule_shape.radius = 0.55
	capsule_shape.height = 1.9
	collision.shape = capsule_shape
	collision.position.y = 0.95
	actor.add_child(collision)
	actor.add_child(appearance.instantiate())
	return actor


func _clamp_actor(actor: CharacterBody3D) -> void:
	actor.position.x = clampf(actor.position.x, -tuning.field_half_length, tuning.field_half_length)
	actor.position.z = clampf(actor.position.z, -tuning.field_half_width, tuning.field_half_width)

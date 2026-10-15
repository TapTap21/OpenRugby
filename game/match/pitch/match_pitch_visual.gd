class_name MatchPitchVisual
extends Node3D
## Builds an editable broadcast-ready pitch and stadium from a match's pitch geometry.

const TURF_GREEN: Color = Color("286b38")
const MOWED_GREEN: Color = Color("307642")
const PAINT_WHITE: Color = Color("f5f2df")
const STAND_DARK: Color = Color("202c38")
const STAND_LIGHT: Color = Color("3b4855")
const CROWD_PALETTE: Array[Color] = [
	Color("ddd5c3"), Color("ba332d"), Color("315d8b"), Color("d0a54d"), Color("526655")
]
const LINE_WIDTH: float = 0.16
const MOW_BAND_COUNT: int = 20


## Rebuilds the field, rugby markings, goalposts, and generated stadium for [param pitch].
func configure(pitch: PitchGeometry) -> void:
	for child: Node in get_children():
		child.queue_free()
	_add_sunlight()
	_add_field(pitch)
	_add_markings(pitch)
	_add_goal_posts(pitch, -1)
	_add_goal_posts(pitch, 1)
	_add_stands(pitch)


func _add_field(pitch: PitchGeometry) -> void:
	var total_length: float = pitch.field_length + 2.0 * pitch.in_goal_depth
	var half_width: float = pitch.half_width()
	_add_plane("Turf", Vector2(pitch.field_width, total_length), Vector3.ZERO, TURF_GREEN)
	var band_width: float = pitch.field_width / float(MOW_BAND_COUNT)
	for band_index: int in range(MOW_BAND_COUNT):
		if band_index % 2 == 0:
			var band_x: float = -half_width + (float(band_index) + 0.5) * band_width
			_add_plane(
				"MowBand%d" % band_index,
				Vector2(band_width, total_length),
				Vector3(band_x, 0.003, 0.0),
				MOWED_GREEN
			)


func _add_markings(pitch: PitchGeometry) -> void:
	var half_length: float = pitch.half_length()
	var half_width: float = pitch.half_width()
	var field_width: float = pitch.field_width
	_add_line("Halfway", Vector3.ZERO, Vector3(field_width, 0.05, LINE_WIDTH))
	for end: int in [-1, 1]:
		_add_line(
			"TryLine%d" % end,
			Vector3(0.0, 0.03, pitch.try_line_z(end)),
			Vector3(field_width, 0.05, LINE_WIDTH)
		)
		_add_line(
			"DeadBallLine%d" % end,
			Vector3(0.0, 0.03, pitch.dead_ball_line_z(end)),
			Vector3(field_width, 0.05, LINE_WIDTH)
		)
		_add_line(
			"TwentyTwo%d" % end,
			Vector3(0.0, 0.03, pitch.line_22_z(end)),
			Vector3(field_width, 0.05, LINE_WIDTH)
		)
		_add_line(
			"FiveMetre%d" % end,
			Vector3(0.0, 0.03, end * (half_length - pitch.line_5_from_try)),
			Vector3(field_width, 0.05, LINE_WIDTH)
		)
	for half: int in [-1, 1]:
		_add_line(
			"TenMetre%d" % half,
			Vector3(0.0, 0.03, half * pitch.line_10_from_halfway),
			Vector3(field_width, 0.05, LINE_WIDTH)
		)
	for side: int in [-1, 1]:
		_add_line(
			"Touchline%d" % side,
			Vector3(side * half_width, 0.03, 0.0),
			Vector3(LINE_WIDTH, 0.05, pitch.field_length)
		)
		for distance: float in [pitch.line_5_from_touch, pitch.line_15_from_touch]:
			_add_line(
				"TouchReference%d_%d" % [side, int(distance)],
				Vector3(side * (half_width - distance), 0.02, 0.0),
				Vector3(LINE_WIDTH * 0.55, 0.025, pitch.field_length)
			)
	_add_line(
		"NearDeadBall",
		Vector3(0.0, 0.03, -pitch.half_length() - pitch.in_goal_depth),
		Vector3(field_width, 0.05, LINE_WIDTH)
	)
	_add_line(
		"FarDeadBall",
		Vector3(0.0, 0.03, pitch.half_length() + pitch.in_goal_depth),
		Vector3(field_width, 0.05, LINE_WIDTH)
	)


func _add_goal_posts(pitch: PitchGeometry, end: int) -> void:
	var z: float = pitch.try_line_z(end)
	var radius: float = pitch.goal_post_radius
	var half_gap: float = pitch.goal_post_gap * 0.5 + radius
	var material: StandardMaterial3D = _material(PAINT_WHITE)
	for side: int in [-1, 1]:
		_add_cylinder(
			"GoalUpright%d_%d" % [end, side],
			Vector3(side * half_gap, (pitch.goal_post_bottom + pitch.goal_post_top) * 0.5, z),
			2.0 * radius,
			pitch.goal_post_top - pitch.goal_post_bottom,
			material
		)
		_add_box(
			"GoalPostPad%d_%d" % [end, side],
			Vector3(side * half_gap, pitch.goal_pad_height * 0.5, z),
			Vector3(pitch.goal_pad_size, pitch.goal_pad_height, pitch.goal_pad_size),
			_material(STAND_LIGHT)
		)
	_add_cylinder(
		"GoalCrossbar%d" % end,
		Vector3(0.0, pitch.crossbar_height - radius, z),
		2.0 * radius,
		pitch.goal_post_gap + 2.0 * radius,
		material,
		Vector3(0.0, 0.0, 90.0)
	)


func _add_stands(pitch: PitchGeometry) -> void:
	var half_width: float = pitch.half_width()
	var stand_length: float = pitch.field_length + 2.0 * pitch.in_goal_depth + 16.0
	for side: int in [-1, 1]:
		var center_x: float = side * (half_width + 12.0)
		for tier: int in range(5):
			_add_box(
				"StandTier%d_%d" % [side, tier],
				Vector3(center_x + side * float(tier) * 0.75, 0.9 + float(tier) * 1.05, 0.0),
				Vector3(7.5 - float(tier) * 0.55, 1.1, stand_length - float(tier) * 2.0),
				_material(STAND_DARK if tier % 2 == 0 else STAND_LIGHT)
			)
		_add_box(
			"StandRoof%d" % side,
			Vector3(center_x + side * 1.0, 7.8, 0.0),
			Vector3(9.0, 0.4, stand_length),
			_material(STAND_DARK)
		)
		_add_crowd(side, pitch, center_x)
	for end: int in [-1, 1]:
		_add_end_stand(end, pitch)


func _add_crowd(side: int, pitch: PitchGeometry, center_x: float) -> void:
	var crowd_mesh: BoxMesh = BoxMesh.new()
	crowd_mesh.size = Vector3(0.32, 0.7, 0.28)
	var crowd_material: StandardMaterial3D = StandardMaterial3D.new()
	crowd_material.vertex_color_use_as_albedo = true
	crowd_material.roughness = 1.0
	crowd_mesh.material = crowd_material
	var crowd: MultiMeshInstance3D = MultiMeshInstance3D.new()
	crowd.name = "EditableGeneratedCrowd%d" % side
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = crowd_mesh
	var columns: int = int((pitch.field_length + 2.0 * pitch.in_goal_depth + 8.0) / 0.65)
	const ROWS: int = 5
	multimesh.instance_count = columns * ROWS
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2008 + side
	var index: int = 0
	for row: int in range(ROWS):
		for column: int in range(columns):
			var x: float = center_x + side * (float(row) * 0.82 - 1.65)
			var z: float = -pitch.half_length() - pitch.in_goal_depth - 3.5 + float(column) * 0.65
			var y: float = 1.4 + float(row) * 0.95
			var transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, y, z))
			multimesh.set_instance_transform(index, transform)
			multimesh.set_instance_color(
				index, CROWD_PALETTE[rng.randi_range(0, CROWD_PALETTE.size() - 1)]
			)
			index += 1
	crowd.multimesh = multimesh
	add_child(crowd)


func _add_end_stand(end: int, pitch: PitchGeometry) -> void:
	var center_z: float = end * (pitch.half_length() + pitch.in_goal_depth + 12.0)
	var stand_width: float = pitch.field_width + 20.0
	for tier: int in range(5):
		_add_box(
			"EndStandTier%d_%d" % [end, tier],
			Vector3(0.0, 0.9 + float(tier) * 1.05, center_z + end * float(tier) * 0.75),
			Vector3(stand_width - float(tier) * 2.0, 1.1, 7.5 - float(tier) * 0.55),
			_material(STAND_DARK if tier % 2 == 0 else STAND_LIGHT)
		)
	_add_box(
		"EndStandRoof%d" % end,
		Vector3(0.0, 7.8, center_z + end),
		Vector3(stand_width, 0.4, 9.0),
		_material(STAND_DARK)
	)
	_add_end_crowd(end, pitch, center_z)


func _add_end_crowd(end: int, pitch: PitchGeometry, center_z: float) -> void:
	var crowd_mesh: BoxMesh = BoxMesh.new()
	crowd_mesh.size = Vector3(0.28, 0.7, 0.32)
	var crowd_material: StandardMaterial3D = StandardMaterial3D.new()
	crowd_material.vertex_color_use_as_albedo = true
	crowd_material.roughness = 1.0
	crowd_mesh.material = crowd_material
	var crowd: MultiMeshInstance3D = MultiMeshInstance3D.new()
	crowd.name = "GeneratedEndCrowd%d" % end
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = crowd_mesh
	var columns: int = int((pitch.field_width + 8.0) / 0.65)
	const ROWS: int = 5
	multimesh.instance_count = columns * ROWS
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2008 + end * 10
	var index: int = 0
	for row: int in range(ROWS):
		for column: int in range(columns):
			var x: float = -pitch.half_width() - 3.5 + float(column) * 0.65
			var z: float = center_z + end * (float(row) * 0.82 - 1.65)
			var y: float = 1.4 + float(row) * 0.95
			var transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, y, z))
			multimesh.set_instance_transform(index, transform)
			multimesh.set_instance_color(
				index, CROWD_PALETTE[rng.randi_range(0, CROWD_PALETTE.size() - 1)]
			)
			index += 1
	crowd.multimesh = multimesh
	add_child(crowd)


func _add_sunlight() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "StadiumSunlight"
	light.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)


func _add_plane(plane_name: String, size: Vector2, location: Vector3, tint: Color) -> void:
	var plane: MeshInstance3D = MeshInstance3D.new()
	plane.name = plane_name
	plane.position = Vector3(location.x, location.y + 0.001, location.z)
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	plane.mesh = mesh
	plane.material_override = _material(tint)
	add_child(plane)


func _add_line(line_name: String, location: Vector3, dimensions: Vector3) -> void:
	_add_box(line_name, location, dimensions, _material(PAINT_WHITE))


func _add_cylinder(
	mesh_name: String,
	location: Vector3,
	diameter: float,
	length: float,
	mesh_material: StandardMaterial3D,
	rotation_degrees: Vector3 = Vector3.ZERO
) -> void:
	var cylinder: MeshInstance3D = MeshInstance3D.new()
	cylinder.name = mesh_name
	cylinder.position = location
	cylinder.rotation_degrees = rotation_degrees
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = length
	mesh.radial_segments = 8
	cylinder.mesh = mesh
	cylinder.material_override = mesh_material
	add_child(cylinder)


func _add_box(
	box_name: String, location: Vector3, dimensions: Vector3, box_material: StandardMaterial3D
) -> void:
	var box: MeshInstance3D = MeshInstance3D.new()
	box.name = box_name
	box.position = location
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	box.mesh = mesh
	box.material_override = box_material
	add_child(box)


func _material(tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 1.0
	return material

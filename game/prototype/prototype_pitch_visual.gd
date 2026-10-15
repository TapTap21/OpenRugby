class_name PrototypePitchVisual
extends Node3D
## Builds the sandbox's editable pitch surface and markings from its current tuning dimensions.

const FIELD_GREEN: Color = Color("287f45")
const BAND_GREEN: Color = Color("2d884a")
const LINE_CREAM: Color = Color("fff8df")
const LINE_THICKNESS: float = 0.16
const LINE_HEIGHT: float = 0.04
const MOW_BAND_COUNT: int = 8


## Rebuilds the pitch visuals to match the supplied ground collider extents.
func configure(field_half_length: float, field_half_width: float, try_line_x: float) -> void:
	for child: Node in get_children():
		child.queue_free()
	var field_length: float = field_half_length * 2.0
	var field_width: float = field_half_width * 2.0
	_add_plane("Turf", Vector2(field_length, field_width), Vector3.ZERO, FIELD_GREEN)
	var band_width: float = field_width / float(MOW_BAND_COUNT)
	for band_index: int in range(MOW_BAND_COUNT):
		if band_index % 2 == 0:
			var band_center: float = -field_half_width + (float(band_index) + 0.5) * band_width
			_add_plane(
				"MowBand%d" % band_index,
				Vector2(field_length, band_width),
				Vector3(0.0, 0.003, band_center),
				BAND_GREEN
			)
	var half_x: float = field_half_length - LINE_THICKNESS * 0.5
	var half_z: float = field_half_width - LINE_THICKNESS * 0.5
	_add_line("Halfway", Vector3.ZERO, Vector3(LINE_THICKNESS, LINE_HEIGHT, field_width))
	_add_line(
		"NearTouchline",
		Vector3(0.0, 0.015, -half_z),
		Vector3(field_length, LINE_HEIGHT, LINE_THICKNESS)
	)
	_add_line(
		"FarTouchline",
		Vector3(0.0, 0.015, half_z),
		Vector3(field_length, LINE_HEIGHT, LINE_THICKNESS)
	)
	_add_line(
		"LeftTryLine",
		Vector3(-clampf(try_line_x, -half_x, half_x), 0.015, 0.0),
		Vector3(LINE_THICKNESS, LINE_HEIGHT, field_width)
	)
	_add_line(
		"RightTryLine",
		Vector3(clampf(try_line_x, -half_x, half_x), 0.015, 0.0),
		Vector3(LINE_THICKNESS, LINE_HEIGHT, field_width)
	)


func _add_plane(plane_name: String, plane_size: Vector2, location: Vector3, tint: Color) -> void:
	var plane: MeshInstance3D = MeshInstance3D.new()
	plane.name = plane_name
	plane.position = Vector3(location.x, location.y + 0.001, location.z)
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = plane_size
	plane.mesh = mesh
	plane.material_override = _material(tint)
	add_child(plane)


func _add_line(line_name: String, location: Vector3, dimensions: Vector3) -> void:
	var line: MeshInstance3D = MeshInstance3D.new()
	line.name = line_name
	line.position = location
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	line.mesh = mesh
	line.material_override = _material(LINE_CREAM)
	add_child(line)


func _material(tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 1.0
	return material

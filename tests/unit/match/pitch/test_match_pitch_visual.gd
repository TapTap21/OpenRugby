class_name TestMatchPitchVisual
extends GdUnitTestSuite
## Checks that replacement pitch geometry follows the documented world axes and goal dimensions.

const VISUAL_SCENE: PackedScene = preload("res://game/match/pitch/match_pitch_visual.tscn")


## RE 06 §2.1 uses X across the field and Z down its length; posts match the observed mesh.
func test_pitch_visual_uses_re_coordinates_and_goal_geometry() -> void:
	var pitch_visual: MatchPitchVisual = VISUAL_SCENE.instantiate() as MatchPitchVisual
	add_child(pitch_visual)
	pitch_visual.configure(PitchGeometry.new())
	var try_line: MeshInstance3D = pitch_visual.get_node("TryLine1") as MeshInstance3D
	@warning_ignore("unused_variable")
	var r1: GdUnitFloatAssert = assert_float(try_line.position.z).is_equal(50.0)
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(try_line.position.x).is_equal(0.0)
	var turf: MeshInstance3D = pitch_visual.get_node("Turf") as MeshInstance3D
	var turf_mesh: PlaneMesh = turf.mesh as PlaneMesh
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(is_equal_approx(turf_mesh.size.x, 67.4)).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(is_equal_approx(turf_mesh.size.y, 128.2)).is_true()
	var upright: MeshInstance3D = pitch_visual.get_node("GoalUpright1_1") as MeshInstance3D
	var upright_mesh: CylinderMesh = upright.mesh as CylinderMesh
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(is_equal_approx(upright.position.x, 2.845)).is_true()
	@warning_ignore("unused_variable")
	var r6: GdUnitFloatAssert = assert_float(upright.position.z).is_equal(50.0)
	@warning_ignore("unused_variable")
	var r7: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(upright_mesh.top_radius, 0.045)).is_true()
	)
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(is_equal_approx(upright_mesh.height, 11.41)).is_true()
	var pad: MeshInstance3D = pitch_visual.get_node("GoalPostPad1_1") as MeshInstance3D
	var pad_mesh: BoxMesh = pad.mesh as BoxMesh
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(is_equal_approx(pad_mesh.size.x, 0.49)).is_true()
	@warning_ignore("unused_variable")
	var r10: GdUnitBoolAssert = assert_bool(is_equal_approx(pad_mesh.size.y, 2.0)).is_true()
	var crossbar: MeshInstance3D = pitch_visual.get_node("GoalCrossbar1") as MeshInstance3D
	@warning_ignore("unused_variable")
	var r11: GdUnitBoolAssert = assert_bool(is_equal_approx(crossbar.position.y, 2.955)).is_true()
	var crossbar_mesh: CylinderMesh = crossbar.mesh as CylinderMesh
	@warning_ignore("unused_variable")
	var r12: GdUnitBoolAssert = assert_bool(is_equal_approx(crossbar_mesh.height, 5.69)).is_true()

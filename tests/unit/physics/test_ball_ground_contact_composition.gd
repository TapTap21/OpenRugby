class_name TestBallGroundContactComposition
extends GdUnitTestSuite
## Verifies that one owner supplies the ground row to the ball contact solve.


class MeshOnlyContactSource:
	extends BallContactSource

	func detect_contacts(_position_m: Vector3, _orientation: Quaternion) -> Array[BallContact]:
		var contact: BallContact = BallContact.new()
		contact.body_id = 1
		contact.feature_id = 1
		contact.contact_kind = 1
		contact.point_m = Vector3(0.0, 0.1, 0.0)
		contact.normal = Vector3.RIGHT
		contact.penetration_m = 0.01
		return [contact]

	func is_available() -> bool:
		return true


func _physics_system(
	source: BallContactSource, position_m: Vector3, orientation: Quaternion
) -> BallPhysicsSystem:
	var params: BallPhysicsParams = BallPhysicsParams.new()
	var system: BallPhysicsSystem = BallPhysicsSystem.new(params, null, source, null)
	system.state.position_m = position_m
	system.state.orientation = orientation
	return system


## The source support point survives and is not duplicated by the legacy fallback.
func test_ground_provider_emits_exactly_one_rotated_ground_contact() -> void:
	var source: GroundPlaneContactSource = GroundPlaneContactSource.new()
	var orientation: Quaternion = Quaternion(Vector3.BACK, PI / 4.0)
	var system: BallPhysicsSystem = _physics_system(source, Vector3(1.0, 0.08, 2.0), orientation)
	var contacts: Array[BallContact] = system._detect_contacts()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(contacts.size()).is_equal(1)
	var contact: BallContact = contacts[0]
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(contact.point_m.x > 1.01).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(contact.normal == Vector3.UP).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitFloatAssert = assert_float(contact.penetration_m).is_equal_approx(
		source.detect_contacts(system.state.position_m, orientation)[0].penetration_m, 0.000001
	)


## A source that does not claim the plane leaves the legacy ground fallback enabled.
func test_empty_source_keeps_legacy_ground_fallback() -> void:
	var source: BallContactSource = BallContactSource.new()
	var system: BallPhysicsSystem = _physics_system(
		source, Vector3(2.0, 0.05, -3.0), Quaternion.IDENTITY
	)
	var contacts: Array[BallContact] = system._detect_contacts()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(contacts.size()).is_equal(1)
	var contact: BallContact = contacts[0]
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(contact.point_m == Vector3(2.0, 0.0, -3.0)).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(contact.penetration_m).is_equal_approx(0.095, 0.000001)


## A mesh-only source keeps its rows while the legacy owner supplies the ground row.
func test_mesh_only_source_keeps_ground_fallback() -> void:
	var source: MeshOnlyContactSource = MeshOnlyContactSource.new()
	var system: BallPhysicsSystem = _physics_system(
		source, Vector3(2.0, 0.05, -3.0), Quaternion.IDENTITY
	)
	var contacts: Array[BallContact] = system._detect_contacts()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(source.provides_ground_plane_contacts()).is_false()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(contacts.size()).is_equal(2)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(
			contacts.any(func(contact: BallContact) -> bool: return contact.normal == Vector3.UP)
		)
		. is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(
			contacts.any(func(contact: BallContact) -> bool: return contact.normal == Vector3.RIGHT)
		)
		. is_true()
	)


## A plane-owning provider preserves its observed open interval at both boundaries.
func test_ground_provider_keeps_strict_plane_boundaries() -> void:
	var source: GroundPlaneContactSource = GroundPlaneContactSource.new()
	var at_plane: BallPhysicsSystem = _physics_system(
		source, Vector3(0.0, 0.0, 0.0), Quaternion.IDENTITY
	)
	var at_tangent: BallPhysicsSystem = _physics_system(
		source, Vector3(0.0, 0.145, 0.0), Quaternion.IDENTITY
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(at_plane._detect_contacts().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(at_tangent._detect_contacts().size()).is_equal(0)

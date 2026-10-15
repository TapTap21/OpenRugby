class_name TestGroundPlaneContactSource
extends GdUnitTestSuite
## Acceptance tests for the RE 06 §2.4 ground-plane ellipsoid contact subset.


func _source() -> GroundPlaneContactSource:
	return GroundPlaneContactSource.new()


## RE 06 §2.4 uses the scaled plane distance and scales penetration back to metres.
func test_ground_contact_uses_scaled_distance_and_penetration() -> void:
	var source: GroundPlaneContactSource = _source()
	var contacts: Array[BallContact] = source.detect_contacts(
		Vector3(2.0, 0.0725, -3.0), Quaternion.IDENTITY
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(contacts.size()).is_equal(1)
	var contact: BallContact = contacts[0]
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(contact.penetration_m).is_equal_approx(
		0.0725, 0.000001
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(contact.normal == Vector3.UP).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(contact.point_m == Vector3(2.0, 0.0, -3.0)).is_true()


## Rotation changes the support radius and point while keeping the ground normal vertical.
func test_rotated_ellipsoid_uses_scaled_frame_support() -> void:
	var source: GroundPlaneContactSource = _source()
	var orientation: Quaternion = Quaternion(Vector3.BACK, PI / 4.0)
	var contacts: Array[BallContact] = source.detect_contacts(Vector3(1.0, 0.08, 2.0), orientation)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(contacts.size()).is_equal(1)
	var contact: BallContact = contacts[0]
	@warning_ignore("unused_variable")
	var expected_support_m: float = sqrt((0.095 * 0.095 + 0.145 * 0.145) / 2.0)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(contact.penetration_m, expected_support_m - 0.08)).is_true()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(contact.normal == Vector3.UP).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(is_equal_approx(contact.point_m.y, 0.0)).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(absf(contact.point_m.x - 1.0) > 0.01).is_true()


## The observed interval is open at both plane crossing and first tangent contact.
func test_scaled_distance_boundaries_are_excluded() -> void:
	var source: GroundPlaneContactSource = _source()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = (
		assert_int(source.detect_contacts(Vector3(0.0, 0.0, 0.0), Quaternion.IDENTITY).size())
		. is_equal(0)
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = (
		assert_int(source.detect_contacts(Vector3(0.0, 0.145, 0.0), Quaternion.IDENTITY).size())
		. is_equal(0)
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = (
		assert_int(source.detect_contacts(Vector3(0.0, -0.01, 0.0), Quaternion.IDENTITY).size())
		. is_equal(0)
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = (
		assert_int(source.detect_contacts(Vector3(0.0, 0.146, 0.0), Quaternion.IDENTITY).size())
		. is_equal(0)
	)


## Identity fields and result order are stable across repeated calls and unrelated pose order.
func test_contacts_have_stable_identity_and_detection_order() -> void:
	var source: GroundPlaneContactSource = _source()
	var pose_a: Vector3 = Vector3(2.0, 0.05, 3.0)
	var pose_b: Vector3 = Vector3(-4.0, 0.04, 1.0)
	var first_a: Array[BallContact] = source.detect_contacts(pose_a, Quaternion.IDENTITY)
	var first_b: Array[BallContact] = source.detect_contacts(pose_b, Quaternion.IDENTITY)
	var second_a: Array[BallContact] = source.detect_contacts(pose_a, Quaternion.IDENTITY)
	var first_key: Array[int] = first_a[0].sort_key()
	var second_key: Array[int] = second_a[0].sort_key()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(first_key.size()).is_equal(second_key.size())
	for index: int in range(first_key.size()):
		@warning_ignore("unused_variable")
		var key_assertion: GdUnitIntAssert = assert_int(first_key[index]).is_equal(
			second_key[index]
		)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(first_b[0].sort_key() != first_key).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(source.is_available()).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(source.is_transaction_stateless()).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = (
		assert_bool(source.snapshot().get("stadium_mesh_contacts", true) == false).is_true()
	)

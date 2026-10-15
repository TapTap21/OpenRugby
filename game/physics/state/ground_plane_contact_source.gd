class_name GroundPlaneContactSource
extends BallContactSource
## Supplies ellipsoid contacts with the y = 0 ground plane only.
## It does not provide stadium triangle contacts and cannot stand in for full match geometry.

const GROUND_BODY_ID: int = 0
const GROUND_FEATURE_ID: int = 0
const GROUND_CONTACT_KIND: int = 0

var params: BallPhysicsParams = BallPhysicsParams.new()


## Returns the single ground-plane contact when the scaled distance is strictly between 0 and 1.
func detect_contacts(position_m: Vector3, orientation: Quaternion) -> Array[BallContact]:
	var contacts: Array[BallContact] = []
	if (
		not position_m.is_finite()
		or params == null
		or not _valid_axes(params.semi_axes_m)
		or not _valid_orientation(orientation)
	):
		return contacts

	var body_orientation: Quaternion = orientation.normalized()
	var local_normal: Vector3 = body_orientation.inverse() * Vector3.UP
	var axes: Vector3 = params.semi_axes_m
	var scaled_normal: Vector3 = Vector3(
		axes.x * local_normal.x, axes.y * local_normal.y, axes.z * local_normal.z
	)
	var scaled_normal_length: float = scaled_normal.length()
	if scaled_normal_length <= 0.0:
		return contacts

	var scaled_distance: float = position_m.y / scaled_normal_length
	if scaled_distance <= 0.0 or scaled_distance >= 1.0:
		return contacts

	var support_offset_local: Vector3 = (
		-Vector3(axes.x * scaled_normal.x, axes.y * scaled_normal.y, axes.z * scaled_normal.z)
		/ scaled_normal_length
	)
	var support_point_world: Vector3 = position_m + body_orientation * support_offset_local
	var contact: BallContact = BallContact.new()
	contact.body_id = GROUND_BODY_ID
	contact.feature_id = GROUND_FEATURE_ID
	contact.contact_kind = GROUND_CONTACT_KIND
	contact.point_m = Vector3(support_point_world.x, 0.0, support_point_world.z)
	contact.normal = Vector3.UP
	contact.penetration_m = (1.0 - scaled_distance) * scaled_normal_length
	contact.source_subfeature_id = 0
	contact.detection_ordinal = 0
	contacts.append(contact)
	return contacts


## True for this plane provider only.
## A stadium mesh source is still required for full collision data.
func is_available() -> bool:
	return params != null and _valid_axes(params.semi_axes_m)


## Returns the stateless plane identity and ellipsoid dimensions used for contact detection.
func snapshot() -> Dictionary:
	var axes: Vector3 = params.semi_axes_m if params != null else Vector3.ZERO
	return {
		"provider": "ground_plane_only",
		"semi_axes_m": [axes.x, axes.y, axes.z],
		"stadium_mesh_contacts": false,
	}


## Detection depends only on the pose arguments and configured semi-axes.
func is_transaction_stateless() -> bool:
	return true


func _valid_axes(axes: Vector3) -> bool:
	return axes.is_finite() and axes.x > 0.0 and axes.y > 0.0 and axes.z > 0.0


func _valid_orientation(orientation: Quaternion) -> bool:
	if not is_finite(orientation.x) or not is_finite(orientation.y):
		return false
	if not is_finite(orientation.z) or not is_finite(orientation.w):
		return false
	return orientation.length_squared() > 0.000001

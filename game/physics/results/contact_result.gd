class_name ContactResult
extends RefCounted
## Hook value: stable detected geometry plus the three adjustable response values.

var body_id: int = 0
var feature_id: int = 0
var contact_kind: int = 0
var point_m: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var penetration_m: float = 0.0
var source_subfeature_id: int = 0
var detection_ordinal: int = 0
var restitution: float = 0.0
var friction: float = 0.0
var rolling_resistance: float = 0.0


## Copies stable identity from detector geometry and response values from the selected surface.
static func create(contact: BallContact) -> ContactResult:
	var result: ContactResult = ContactResult.new()
	result.body_id = contact.body_id
	result.feature_id = contact.feature_id
	result.contact_kind = contact.contact_kind
	result.point_m = contact.point_m
	result.normal = contact.normal
	result.penetration_m = contact.penetration_m
	result.source_subfeature_id = contact.source_subfeature_id
	result.detection_ordinal = contact.detection_ordinal
	return result


## Serializes every exact identity and response value that can affect a pending solve.
func snapshot() -> Dictionary:
	return {
		"body_id": body_id,
		"feature_id": feature_id,
		"contact_kind": contact_kind,
		"point_m": [point_m.x, point_m.y, point_m.z],
		"normal": [normal.x, normal.y, normal.z],
		"penetration_m": penetration_m,
		"source_subfeature_id": source_subfeature_id,
		"detection_ordinal": detection_ordinal,
		"restitution": restitution,
		"friction": friction,
		"rolling_resistance": rolling_resistance,
	}

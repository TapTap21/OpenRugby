class_name BallContact
extends RefCounted
## Deterministic contact supplied by an S1/S6/S7 geometry provider.

var body_id: int = 0
var feature_id: int = 0
var contact_kind: int = 0
var point_m: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var penetration_m: float = 0.0
var source_subfeature_id: int = 0
var detection_ordinal: int = 0


## Returns the required total deterministic ordering key.
func sort_key() -> Array[int]:
	return [
		body_id,
		feature_id,
		contact_kind,
		roundi(point_m.x * 1000000.0),
		roundi(point_m.y * 1000000.0),
		roundi(point_m.z * 1000000.0),
		roundi(normal.x * 1000000.0),
		roundi(normal.y * 1000000.0),
		roundi(normal.z * 1000000.0),
		source_subfeature_id,
		detection_ordinal,
	]

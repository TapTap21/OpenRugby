class_name PassLaunch
extends RefCounted
## Typed ballistic pass launch result.

var velocity_m_s: Vector3 = Vector3.ZERO
var flight_time_s: float = 0.0
var target_m: Vector3 = Vector3.ZERO
var unresolved: bool = false


func snapshot() -> Dictionary:
	return {
		"velocity": [velocity_m_s.x, velocity_m_s.y, velocity_m_s.z],
		"flight_time_s": flight_time_s,
		"target": [target_m.x, target_m.y, target_m.z],
		"unresolved": unresolved
	}

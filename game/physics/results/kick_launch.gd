class_name KickLaunch
extends RefCounted
## Typed ball velocity and spin result for S2 kick launch hooks.

var velocity_m_s: Vector3 = Vector3.ZERO
var spin_rad_s: Vector3 = Vector3.ZERO
var kick_type: int = 0
var unresolved: bool = false


func snapshot() -> Dictionary:
	return {
		"velocity": [velocity_m_s.x, velocity_m_s.y, velocity_m_s.z],
		"spin": [spin_rad_s.x, spin_rad_s.y, spin_rad_s.z],
		"kick_type": kick_type,
		"unresolved": unresolved
	}

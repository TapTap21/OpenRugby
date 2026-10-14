class_name BallPredictionState
extends RefCounted
## Plain kinematic input/output for the stateless ball path predictor.

var position_m: Vector3 = Vector3.ZERO
var velocity_m_s: Vector3 = Vector3.ZERO
var rolling: bool = false
var hop_time_s: float = INF


func snapshot() -> Dictionary:
	return {
		"position": [position_m.x, position_m.y, position_m.z],
		"velocity": [velocity_m_s.x, velocity_m_s.y, velocity_m_s.z],
		"rolling": rolling,
		"hop_time_s": hop_time_s,
	}

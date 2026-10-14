class_name S2WindPolicy
extends RefCounted
## Owner-resolved wind enablement and vector for one match setup.

var resolved: bool = false
var enabled: bool = false
var vector_km_h: Vector3 = Vector3.ZERO


## Creates an explicit wind policy, including an intentional wind-off policy.
static func create(p_enabled: bool, p_vector_km_h: Vector3) -> S2WindPolicy:
	var policy: S2WindPolicy = S2WindPolicy.new()
	policy.resolved = p_vector_km_h.is_finite()
	policy.enabled = p_enabled
	policy.vector_km_h = p_vector_km_h
	return policy


## True when the owner supplied a finite, resolved vector.
func is_valid() -> bool:
	return resolved and vector_km_h.is_finite()


## Stable serialization for fingerprints and snapshots.
func snapshot() -> Dictionary:
	return {
		"resolved": resolved,
		"enabled": enabled,
		"vector_km_h": [vector_km_h.x, vector_km_h.y, vector_km_h.z],
	}


## Returns a detached copy of the injected policy.
func duplicate_policy() -> S2WindPolicy:
	var copy: S2WindPolicy = S2WindPolicy.new()
	copy.resolved = resolved
	copy.enabled = enabled
	copy.vector_km_h = vector_km_h
	return copy

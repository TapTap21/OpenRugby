class_name ReplayHeader
extends RefCounted
## Metadata stored with a recorded input log.

const _INT_KEYS: PackedStringArray = [
	"format_version", "seed", "tick_rate", "slot_count", "axes_per_slot"
]
const CURRENT_FORMAT_VERSION: int = 3
const _STRING_KEYS: PackedStringArray = [
	"game_version", "mod_set_hash", "action_layout_hash", "setup_fingerprint"
]

var format_version: int = CURRENT_FORMAT_VERSION
var game_version: String = ""
var seed: int = 0
var mod_set_hash: String = ""
var action_layout_hash: String = ""
var setup_fingerprint: String = ""
var tick_rate: int = 60
var slot_count: int = 1
var axes_per_slot: int = 2


## Builds a header from [param d]; null when a key is missing or has the wrong type.
static func from_dict(d: Dictionary) -> ReplayHeader:
	for key: String in _INT_KEYS:
		if not d.has(key) or typeof(d[key]) != TYPE_INT:
			return null
	for key: String in _STRING_KEYS:
		if key == "setup_fingerprint" and d.get("format_version", 1) < 2:
			continue
		if not d.has(key) or typeof(d[key]) != TYPE_STRING:
			return null
	if d["format_version"] < 1 or d["format_version"] > CURRENT_FORMAT_VERSION:
		return null
	var expected_key_count: int = 9 if d["format_version"] >= 2 else 8
	if d.size() != expected_key_count:
		return null
	if d["tick_rate"] < 1 or d["slot_count"] < 1 or d["axes_per_slot"] < 0:
		return null
	var header: ReplayHeader = ReplayHeader.new()
	header.format_version = d["format_version"]
	header.game_version = d["game_version"]
	header.seed = d["seed"]
	header.mod_set_hash = d["mod_set_hash"]
	header.action_layout_hash = d["action_layout_hash"]
	header.setup_fingerprint = d.get("setup_fingerprint", "")
	header.tick_rate = d["tick_rate"]
	header.slot_count = d["slot_count"]
	header.axes_per_slot = d["axes_per_slot"]
	return header


## Serialises the header to a dictionary.
func to_dict() -> Dictionary:
	var result: Dictionary = {
		"format_version": format_version,
		"game_version": game_version,
		"seed": seed,
		"mod_set_hash": mod_set_hash,
		"action_layout_hash": action_layout_hash,
	}
	if format_version >= 2:
		result["setup_fingerprint"] = setup_fingerprint
	result["tick_rate"] = tick_rate
	result["slot_count"] = slot_count
	result["axes_per_slot"] = axes_per_slot
	return result


## True when compatibility hashes and tick rate match; game_version is informational.
func is_compatible_with(
	p_mod_set_hash: String, p_action_layout_hash: String, p_setup_fingerprint: String
) -> bool:
	return (
		format_version == CURRENT_FORMAT_VERSION
		and mod_set_hash == p_mod_set_hash
		and action_layout_hash == p_action_layout_hash
		and setup_fingerprint == p_setup_fingerprint
		and tick_rate == MatchSim.TICKS_PER_SECOND
	)

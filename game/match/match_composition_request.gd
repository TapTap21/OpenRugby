class_name MatchCompositionRequest
extends RefCounted
## All caller-owned values required by the canonical live/replay builder.

var config: MatchConfig
var systems: Array[SimSystem] = []
var mod_set_hash: String = ""
var action_layout_hash: String = ""
var extension_points: ExtensionPoints
var s2: S2RuntimePort

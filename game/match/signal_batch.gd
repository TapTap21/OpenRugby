class_name SignalBatch
extends RefCounted
## Immutable ordered set of deferred MatchSim signals.

var signals: Array[StagedSignal]:
	get:
		return _copy_signals(_signals)

var _signals: Array[StagedSignal]


func _init(p_signals: Array[StagedSignal] = []) -> void:
	_signals = _copy_signals(p_signals)


## Number of staged notifications.
func size() -> int:
	return _signals.size()


static func _copy_signals(values: Array[StagedSignal]) -> Array[StagedSignal]:
	var result: Array[StagedSignal] = []
	for value: StagedSignal in values:
		if value == null:
			continue
		result.append(StagedSignal.new(value.kind, value.from_state, value.to_state, value.period))
	return result

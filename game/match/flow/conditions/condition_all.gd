class_name ConditionAll
extends MatchCondition
## Met when every listed condition is met. An empty list is met.

@export var conditions: Array[MatchCondition] = []


func is_met(sim: MatchSim) -> bool:
	var result: ConditionEvaluationResult = evaluate_checked(sim)
	return result.ok and result.value


## Evaluates children in order and propagates the first checked failure unchanged.
func evaluate_checked(sim: MatchSim) -> ConditionEvaluationResult:
	for condition: MatchCondition in conditions:
		if condition == null:
			return ConditionEvaluationResult.new(false, false, ERR_INVALID_DATA)
		var result: ConditionEvaluationResult = condition.evaluate_checked(sim)
		if not _valid_result_shape(result):
			return ConditionEvaluationResult.new(false, false, ERR_INVALID_DATA)
		if not result.ok:
			return result
		if not result.value:
			return ConditionEvaluationResult.new(true, false, OK)
	return ConditionEvaluationResult.new(true, true, OK)


func _valid_result_shape(result: ConditionEvaluationResult) -> bool:
	return (
		result != null
		and (
			(result.ok and result.error == OK)
			or (not result.ok and not result.value and result.error != OK)
		)
	)

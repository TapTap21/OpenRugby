class_name ConditionAll
extends MatchCondition
## Met when every listed condition is met. An empty list is met.

@export var conditions: Array[MatchCondition] = []


func is_met(sim: MatchSim) -> bool:
	for condition: MatchCondition in conditions:
		if condition == null or not condition.is_met(sim):
			return false
	return true

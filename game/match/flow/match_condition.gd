class_name MatchCondition
extends Resource
## Base class for data-driven transition conditions. The base condition is never met.


## Evaluates this condition with an explicit checked failure channel.
func evaluate_checked(sim: MatchSim) -> ConditionEvaluationResult:
	return ConditionEvaluationResult.new(true, is_met(sim), OK)


## Compatibility predicate for simple condition resources.
func is_met(_sim: MatchSim) -> bool:
	return false

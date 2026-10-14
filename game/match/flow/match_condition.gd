class_name MatchCondition
extends Resource
## Base class for data-driven transition conditions. The base condition is never met.


## Returns true when the condition holds for [param _sim].
func is_met(_sim: MatchSim) -> bool:
	return false

class_name ConditionPeriodExpired
extends MatchCondition
## Met when the current period has reached its nominal length.

enum Which { ANY, LAST, NOT_LAST }

@export var which: Which = Which.ANY


func is_met(sim: MatchSim) -> bool:
	if not sim.clock.is_period_expired():
		return false
	match which:
		Which.LAST:
			return sim.clock.is_last_period()
		Which.NOT_LAST:
			return not sim.clock.is_last_period()
		_:
			return true

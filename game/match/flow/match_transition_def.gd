class_name MatchTransitionDef
extends Resource
## One data-driven transition of the match flow.
##
## It fires when the trigger is empty or pending, and the condition is null or met.

## What happens to the match clock when the transition is applied.
enum PeriodEffect { NONE, START, ADVANCE }

## Target state id.
@export var to: StringName
## Trigger that must be pending; empty means no trigger is needed.
@export var trigger: StringName = &""
## Extra condition; null means none.
@export var condition: MatchCondition
## Clock effect applied with the transition.
@export var period_effect: PeriodEffect = PeriodEffect.NONE

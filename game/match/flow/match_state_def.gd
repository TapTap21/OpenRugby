class_name MatchStateDef
extends Resource
## One state of the match flow.

@export var id: StringName
## True when the match clock advances in this state.
@export var clock_runs: bool = false
## True when entering this state ends the current period.
@export var ends_period: bool = false
## True when entering this state finishes the match.
@export var terminal: bool = false
## Transitions in evaluation order.
@export var transitions: Array[MatchTransitionDef] = []

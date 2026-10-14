class_name EventBusImpl
extends Node
## Global event bus autoload for cross-feature events only (see ADR-004).
##
## Rules: signals are typed and past tense; a signal lives here only when its emitter and its
## listeners are in different feature folders; the match simulation never emits or listens here
## (the match runner relays sim signals after each tick); listeners never mutate sim state.
## Every signal names the slice that owns it. Adding one requires a spec update.

## The match flow moved from [param from_state] to [param to_state] on [param tick].
## Owner: S1 (relayed by [MatchRunner]).
signal match_state_changed(from_state: StringName, to_state: StringName, tick: int)

## A match period (1-based) started. Owner: S1 (relayed by [MatchRunner]).
signal match_period_started(period: int)

## A match period (1-based) ended. Owner: S1 (relayed by [MatchRunner]).
signal match_period_ended(period: int)

## The match reached a terminal state. Owner: S1 (relayed by [MatchRunner]).
signal match_finished(final_tick: int)

## The mod loader finished applying the enabled mod set. Owner: S1 (emitted by [ModLoader]).
signal mods_loaded(mod_set_hash: String)

## Input bindings changed (remap, reset or load). Owner: S9 (emitted by [InputBindings]).
signal input_bindings_changed

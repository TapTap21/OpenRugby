class_name InputActionDef
extends Resource
## One bindable input action: its context, default bindings and stick deadzone.
##
## Actions are data. The action list lives in the default action set resource, so a layout change
## is a data edit and never a code edit.

## Where an action is consumed. MATCH actions are sampled into the simulation frame, UI actions
## drive menus, and SYSTEM actions stay active during a match but never reach the frame.
enum Context { MATCH, UI, SYSTEM }

## Stable action identifier, used by [InputMap], axes and saved bindings.
@export var id: StringName = &""

## Where the action is consumed. See [enum Context].
@export var context: Context = Context.MATCH

## Translation key of the action's display name.
@export var display_name_key: String = ""

## Whether players may change this action's bindings.
@export var remappable: bool = true

## Analog deadzone applied to joypad motion bindings.
@export var deadzone: float = 0.2

## Default gamepad bindings.
@export var gamepad_events: Array[InputEvent] = []

## Default keyboard and mouse bindings.
@export var keyboard_events: Array[InputEvent] = []

## True while the layout awaits confirmation from the controls data.
@export var provisional: bool = true

class_name InputAxisDef
extends Resource
## A two-dimensional axis (a stick or a d-pad) built from four MATCH action ids.

## Axis identifier, unique within its action set.
@export var id: StringName = &""

## Action id that drives the axis towards negative x.
@export var negative_x: StringName = &""

## Action id that drives the axis towards positive x.
@export var positive_x: StringName = &""

## Action id that drives the axis towards negative y.
@export var negative_y: StringName = &""

## Action id that drives the axis towards positive y.
@export var positive_y: StringName = &""

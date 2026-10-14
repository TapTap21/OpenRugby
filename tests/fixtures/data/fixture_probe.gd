class_name FixtureProbe
extends Resource
## Test-only resource with one exported field of each patchable kind (used by the mod tests).

enum Level { LOW, MID, HIGH }

@export var count: int = 1
@export var ratio: float = 0.5
@export var strength: float = 1.0
@export var enabled: bool = false
@export var label: String = "base"
@export var tag: StringName = &"base_tag"
@export var level: Level = Level.LOW
@export var tint: Color = Color.WHITE
@export var offset: Vector3 = Vector3.ZERO
@export var kit: Kit
@export var bag: Dictionary[StringName, int] = {&"b": 2, &"c": 3}
@export var values: Array[int] = [1, 2, 3]
@export var kits: Array[Kit] = []

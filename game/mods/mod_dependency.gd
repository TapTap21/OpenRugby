class_name ModDependency
extends RefCounted
## One dependency of a mod on another mod (or on [code]base[/code], the game itself).

var id: StringName = &""
var constraint: VersionConstraint = null
var constraint_text: String = "*"
var optional: bool = false

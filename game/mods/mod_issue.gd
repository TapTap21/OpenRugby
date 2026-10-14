class_name ModIssue
extends RefCounted
## One error or warning produced while discovering, resolving or applying mods.
##
## [member message] is English developer text; the mod manager UI (S11) maps [member code] to a
## translation key.

enum Severity { WARNING, ERROR }

var code: StringName = &""
var mod_id: StringName = &""
var message: String = ""
var severity: Severity = Severity.ERROR


func _init(
	p_code: StringName = &"",
	p_mod_id: StringName = &"",
	p_message: String = "",
	p_severity: Severity = Severity.ERROR
) -> void:
	code = p_code
	mod_id = p_mod_id
	message = p_message
	severity = p_severity


func _to_string() -> String:
	var level: String = "error" if is_error() else "warning"
	return "[%s] %s (%s): %s" % [level, code, mod_id, message]


## Returns a new error issue.
static func error(p_code: StringName, p_mod_id: StringName, p_message: String) -> ModIssue:
	return ModIssue.new(p_code, p_mod_id, p_message, Severity.ERROR)


## Returns a new warning issue.
static func warning(p_code: StringName, p_mod_id: StringName, p_message: String) -> ModIssue:
	return ModIssue.new(p_code, p_mod_id, p_message, Severity.WARNING)


## Returns true when this issue is an error.
func is_error() -> bool:
	return severity == Severity.ERROR

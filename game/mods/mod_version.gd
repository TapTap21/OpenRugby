class_name ModVersion
extends RefCounted
## A semantic version (SemVer 2.0): [code]MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD][/code].
##
## Build metadata is accepted and ignored. Precedence follows SemVer 2.0.

const _PATTERN: String = (
	"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)"
	+ "(?:-((?:0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)"
	+ "(?:\\.(?:0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
	+ "(?:\\+[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*)?$"
)

static var _regex: RegEx = null

var major: int = 0
var minor: int = 0
var patch: int = 0
var prerelease: PackedStringArray = PackedStringArray()


func _init(p_major: int = 0, p_minor: int = 0, p_patch: int = 0) -> void:
	major = p_major
	minor = p_minor
	patch = p_patch


func _to_string() -> String:
	var text: String = "%d.%d.%d" % [major, minor, patch]
	if not prerelease.is_empty():
		text += "-" + ".".join(prerelease)
	return text


## Parses [param text]; returns null when it is not a valid version.
static func parse(text: String) -> ModVersion:
	if _regex == null:
		_regex = RegEx.create_from_string(_PATTERN)
	var found: RegExMatch = _regex.search(text)
	if found == null:
		return null
	var version: ModVersion = ModVersion.new(
		found.get_string(1).to_int(), found.get_string(2).to_int(), found.get_string(3).to_int()
	)
	var pre: String = found.get_string(4)
	if not pre.is_empty():
		version.prerelease = pre.split(".")
	return version


## Returns -1, 0 or 1 as this version precedes, equals or follows [param other].
func compare(other: ModVersion) -> int:
	var parts: Array[int] = [major - other.major, minor - other.minor, patch - other.patch]
	for diff: int in parts:
		if diff != 0:
			return signi(diff)
	if prerelease.is_empty() or other.prerelease.is_empty():
		return signi(int(prerelease.is_empty()) - int(other.prerelease.is_empty()))
	var shared: int = mini(prerelease.size(), other.prerelease.size())
	for i: int in shared:
		var result: int = _compare_identifier(prerelease[i], other.prerelease[i])
		if result != 0:
			return result
	return signi(prerelease.size() - other.prerelease.size())


static func _compare_identifier(left: String, right: String) -> int:
	var left_numeric: bool = _is_numeric(left)
	var right_numeric: bool = _is_numeric(right)
	if left_numeric and right_numeric:
		return signi(left.to_int() - right.to_int())
	if left_numeric != right_numeric:
		return -1 if left_numeric else 1
	if left == right:
		return 0
	return -1 if left < right else 1


static func _is_numeric(identifier: String) -> bool:
	if identifier.is_empty():
		return false
	for i: int in identifier.length():
		var code: int = identifier.unicode_at(i)
		if code < 48 or code > 57:
			return false
	return true

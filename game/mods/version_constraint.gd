class_name VersionConstraint
extends RefCounted
## A version range such as [code]>=0.1.0 <0.2.0[/code], [code]^1.2.0[/code] or
## [code]1.0.0 || 3.0.0[/code].
##
## Alternatives are separated by [code]||[/code]; each alternative is one or more
## whitespace-separated comparators that must all match. Comparators: [code]*[/code],
## [code]X[/code] / [code]=X[/code], [code]>X[/code], [code]>=X[/code], [code]<X[/code],
## [code]<=X[/code], [code]^X[/code] and [code]~X[/code], where [code]X[/code] is a full version.
## Comparison is plain SemVer precedence.

## Operator prefixes, longest first so that [code]>=[/code] wins over [code]>[/code].
const _PREFIXES: Array[String] = [">=", "<=", ">", "<", "=", "^", "~"]

## The text this constraint was parsed from.
var text: String = ""

## Each alternative is an [Array] of [VersionConstraint._Comparator].
var _alternatives: Array[Array] = []


func _to_string() -> String:
	return text


## Parses [param p_text]; returns null when it is not a valid constraint.
static func parse(p_text: String) -> VersionConstraint:
	var stripped: String = p_text.strip_edges()
	if stripped.is_empty():
		return null
	var constraint: VersionConstraint = VersionConstraint.new()
	constraint.text = stripped
	for alternative_text: String in stripped.split("||"):
		var tokens: PackedStringArray = _tokens(alternative_text)
		if tokens.is_empty():
			return null
		var alternative: Array[_Comparator] = []
		for token: String in tokens:
			if not _append_comparators(token, alternative):
				return null
		constraint._alternatives.append(alternative)
	return constraint


## Returns true when [param version] satisfies this constraint.
func matches(version: ModVersion) -> bool:
	if version == null:
		return false
	for alternative: Array in _alternatives:
		var all_match: bool = true
		for comparator: _Comparator in alternative:
			if not comparator.matches(version):
				all_match = false
				break
		if all_match:
			return true
	return false


static func _tokens(alternative_text: String) -> PackedStringArray:
	return alternative_text.replace("\t", " ").split(" ", false)


static func _append_comparators(token: String, out: Array[_Comparator]) -> bool:
	if token == "*":
		out.append(_Comparator.new(_Comparator.Op.ANY, null))
		return true
	var prefix: String = ""
	for candidate: String in _PREFIXES:
		if token.begins_with(candidate):
			prefix = candidate
			break
	var version: ModVersion = ModVersion.parse(token.substr(prefix.length()))
	if version == null:
		return false
	match prefix:
		"", "=":
			out.append(_Comparator.new(_Comparator.Op.EQ, version))
		">":
			out.append(_Comparator.new(_Comparator.Op.GT, version))
		">=":
			out.append(_Comparator.new(_Comparator.Op.GE, version))
		"<":
			out.append(_Comparator.new(_Comparator.Op.LT, version))
		"<=":
			out.append(_Comparator.new(_Comparator.Op.LE, version))
		"^":
			out.append(_Comparator.new(_Comparator.Op.GE, version))
			var caret_upper: ModVersion = ModVersion.new(version.major + 1, 0, 0)
			if version.major == 0:
				caret_upper = ModVersion.new(0, version.minor + 1, 0)
			out.append(_Comparator.new(_Comparator.Op.LT, caret_upper))
		"~":
			out.append(_Comparator.new(_Comparator.Op.GE, version))
			out.append(
				_Comparator.new(
					_Comparator.Op.LT, ModVersion.new(version.major, version.minor + 1, 0)
				)
			)
	return true


## One comparator of an alternative.
class _Comparator:
	extends RefCounted

	enum Op { ANY, EQ, GT, GE, LT, LE }

	var op: Op = Op.ANY
	var version: ModVersion = null

	func _init(p_op: Op, p_version: ModVersion) -> void:
		op = p_op
		version = p_version

	func matches(candidate: ModVersion) -> bool:
		if op == Op.ANY:
			return true
		var order: int = candidate.compare(version)
		match op:
			Op.EQ:
				return order == 0
			Op.GT:
				return order > 0
			Op.GE:
				return order >= 0
			Op.LT:
				return order < 0
		return order <= 0

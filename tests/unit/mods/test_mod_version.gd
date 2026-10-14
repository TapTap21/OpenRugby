class_name TestModVersion
extends GdUnitTestSuite
## Tests for ModVersion and VersionConstraint: SemVer parsing, precedence and ranges
## (S1-modloader section 3, criteria M-01 to M-03).


## M-01: valid SemVer texts parse, invalid ones give null.
func test_m01_parse_accepts_valid_and_rejects_invalid() -> void:
	var failures: Array[String] = []
	for valid: String in ["1.2.3", "0.1.0-beta.2", "1.0.0+build.5"]:
		if ModVersion.parse(valid) == null:
			@warning_ignore("return_value_discarded")
			failures.append("rejected valid %s" % valid)
	for invalid: String in ["1.2", "01.2.3", "a.b.c", ""]:
		if ModVersion.parse(invalid) != null:
			@warning_ignore("return_value_discarded")
			failures.append("accepted invalid %s" % invalid)
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(failures).is_empty()
	var built: ModVersion = ModVersion.parse("1.0.0+build.5")
	if built != null:
		@warning_ignore("unused_variable")
		var r2: GdUnitStringAssert = assert_str(str(built)).is_equal("1.0.0")


## M-02: SemVer precedence chain, checked pairwise in both directions.
func test_m02_precedence_chain() -> void:
	var chain: Array[String] = [
		"1.0.0-alpha",
		"1.0.0-alpha.1",
		"1.0.0-beta",
		"1.0.0-beta.2",
		"1.0.0-rc.1",
		"1.0.0",
		"1.0.1",
		"1.1.0",
		"2.0.0",
	]
	var failures: Array[String] = []
	for index: int in range(chain.size() - 1):
		var lower: ModVersion = ModVersion.parse(chain[index])
		var higher: ModVersion = ModVersion.parse(chain[index + 1])
		if lower == null or higher == null:
			@warning_ignore("return_value_discarded")
			failures.append("parse %d" % index)
		elif lower.compare(higher) != -1 or higher.compare(lower) != 1:
			@warning_ignore("return_value_discarded")
			failures.append("%s vs %s" % [chain[index], chain[index + 1]])
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(failures).is_empty()


func _matches(constraint_text: String, version_text: String) -> bool:
	var constraint: VersionConstraint = VersionConstraint.parse(constraint_text)
	var version: ModVersion = ModVersion.parse(version_text)
	if constraint == null or version == null:
		return false
	return constraint.matches(version)


## M-03: caret, tilde, ranges, alternatives and wildcard; ">=x" is invalid.
func test_m03_constraint_matching() -> void:
	# [constraint, version, expected]
	var cases: Array = [
		["^1.2.0", "1.9.9", true],
		["^1.2.0", "2.0.0", false],
		["^0.2.0", "0.2.5", true],
		["^0.2.0", "0.3.0", false],
		["~1.2.0", "1.2.9", true],
		["~1.2.0", "1.3.0", false],
		[">=1.0.0 <2.0.0", "1.5.0", true],
		[">=1.0.0 <2.0.0", "2.0.0", false],
		["1.0.0 || 3.0.0", "3.0.0", true],
		["1.0.0 || 3.0.0", "2.0.0", false],
		["*", "9.9.9", true],
	]
	var failures: Array[String] = []
	for entry: Array in cases:
		var constraint_text: String = entry[0]
		var version_text: String = entry[1]
		var expected: bool = entry[2]
		if _matches(constraint_text, version_text) != expected:
			@warning_ignore("return_value_discarded")
			failures.append("%s / %s" % [constraint_text, version_text])
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(failures).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitObjectAssert = assert_object(VersionConstraint.parse(">=x")).is_null()

class_name TestSmoke
extends GdUnitTestSuite
## Smoke test proving the gdUnit4 runner works headless.


func test_runner_works() -> void:
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(1 + 1).is_equal(2)

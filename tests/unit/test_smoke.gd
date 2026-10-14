class_name TestSmoke
extends GdUnitTestSuite
## Smoke tests: the gdUnit4 runner works headless and translation keys resolve.


func test_runner_works() -> void:
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(1 + 1).is_equal(2)


func test_translation_keys_resolve() -> void:
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(TranslationServer.translate("GAME_TITLE")).is_equal(
		"OpenRugby"
	)

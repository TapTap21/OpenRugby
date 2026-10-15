class_name TestDetachedCommandBundle
extends GdUnitTestSuite
## Focused tests for the defensive typed command bundle seam.


class CommandRecord:
	extends RefCounted
	var value: int

	func _init(p_value: int) -> void:
		value = p_value

	func detached_copy() -> RefCounted:
		return CommandRecord.new(value)

	func snapshot() -> Dictionary:
		return {"value": value}


class UnsupportedRecord:
	extends RefCounted


func test_builder_seals_ordered_concrete_copies() -> void:
	var first: CommandRecord = CommandRecord.new(4)
	var second: CommandRecord = CommandRecord.new(9)
	var builder: DetachedCommandBundleBuilder = DetachedCommandBundleBuilder.new()
	@warning_ignore("unused_variable")
	var append_first: Error = builder.append(first)
	@warning_ignore("unused_variable")
	var append_second: Error = builder.append(second)
	var bundle: DetachedCommandBundle = builder.seal()
	first.value = 100
	var copied_records: Array[RefCounted] = bundle.records_in_order()
	var first_copy: CommandRecord = copied_records[0] as CommandRecord
	var second_copy: CommandRecord = copied_records[1] as CommandRecord
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(first_copy.value).is_equal(4)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(second_copy.value).is_equal(9)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(first_copy == first).is_false()


func test_unsupported_mutable_payload_copy_is_rejected() -> void:
	var builder: DetachedCommandBundleBuilder = DetachedCommandBundleBuilder.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(builder.append(UnsupportedRecord.new())).is_equal(
		ERR_INVALID_DATA
	)
	var bundle: DetachedCommandBundle = DetachedCommandBundle.new([UnsupportedRecord.new()])
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(bundle.is_valid()).is_false()

class_name TestSimRng
extends GdUnitTestSuite
## Tests for SimRng: seeded PCG32 wrapper used by the match simulation (S1-core section 2.1).

const DRAW_COUNT: int = 1000


## C-01: two SimRng with the same seed produce identical sequences.
func test_c01_same_seed_same_sequence() -> void:
	var a: SimRng = SimRng.new(42)
	var b: SimRng = SimRng.new(42)
	var seq_a: Array[int] = []
	var seq_b: Array[int] = []
	for i: int in range(DRAW_COUNT):
		@warning_ignore("return_value_discarded")
		seq_a.append(a.next_int())
		@warning_ignore("return_value_discarded")
		seq_b.append(b.next_int())
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(seq_a).is_equal(seq_b)


## C-02: different seeds (1 and 2) give different first-10 sequences.
func test_c02_different_seeds_differ() -> void:
	var a: SimRng = SimRng.new(1)
	var b: SimRng = SimRng.new(2)
	var seq_a: Array[int] = []
	var seq_b: Array[int] = []
	for i: int in range(10):
		@warning_ignore("return_value_discarded")
		seq_a.append(a.next_int())
		@warning_ignore("return_value_discarded")
		seq_b.append(b.next_int())
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(seq_a).is_not_equal(seq_b)


## C-03: get_state, 50 draws, set_state reproduces the same 50 draws.
func test_c03_state_save_and_restore_reproduces_draws() -> void:
	var rng: SimRng = SimRng.new(7)
	var saved: int = rng.get_state()
	var first: Array[int] = []
	for i: int in range(50):
		@warning_ignore("return_value_discarded")
		first.append(rng.next_int())
	rng.set_state(saved)
	var second: Array[int] = []
	for i: int in range(50):
		@warning_ignore("return_value_discarded")
		second.append(rng.next_int())
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(second).is_equal(first)


## C-04: range_int(3, 5) only returns 3, 4 or 5 over 1000 draws; next_float is in [0, 1).
func test_c04_range_and_float_bounds() -> void:
	var rng: SimRng = SimRng.new(99)
	var range_ok: bool = true
	var float_ok: bool = true
	for i: int in range(DRAW_COUNT):
		var value: int = rng.range_int(3, 5)
		if value < 3 or value > 5:
			range_ok = false
		var fraction: float = rng.next_float()
		if fraction < 0.0 or fraction >= 1.0:
			float_ok = false
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(range_ok).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(float_ok).is_true()

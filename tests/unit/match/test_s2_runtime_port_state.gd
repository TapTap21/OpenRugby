class_name TestS2RuntimePortState
extends GdUnitTestSuite
## Scene consumers receive stable, detached, immutable state snapshots through the runtime port.


func test_m04_player_and_ball_state_snapshots_are_ordered_and_read_only() -> void:
	var locomotion: LocomotionSystem = LocomotionSystem.new()
	var later: PlayerMotionState = PlayerMotionState.new()
	later.player_id = &"away-9"
	later.team_id = &"away"
	later.shirt_number = 9
	later.position_m = Vector3(1.0, 2.0, 3.0)
	var earlier: PlayerMotionState = PlayerMotionState.new()
	earlier.player_id = &"home-1"
	earlier.team_id = &"home"
	earlier.shirt_number = 1
	earlier.position_m = Vector3(4.0, 5.0, 6.0)
	locomotion.players = [later, earlier]
	var ball: BallPhysicsSystem = BallPhysicsSystem.new()
	ball.state.position_m = Vector3(7.0, 8.0, 9.0)
	var port: S2RuntimePort = S2RuntimePort.new()
	var unbound_ball_snapshot: Dictionary = port.ball_state_snapshot()
	port.bind(ball, locomotion, null)
	var players: Array[Dictionary] = port.player_state_snapshots()
	var ball_snapshot: Dictionary = port.ball_state_snapshot()
	var player_position: Array = players[0]["position"]
	var ball_position: Array = ball_snapshot["position"]
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(players.size()).is_equal(2)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(players[0]["player_id"]).is_equal("away-9")
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(players[1]["player_id"]).is_equal("home-1")
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(players.is_read_only()).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(players[0].is_read_only()).is_true()
	@warning_ignore("unused_variable")
	var r6: GdUnitBoolAssert = assert_bool(player_position.is_read_only()).is_true()
	@warning_ignore("unused_variable")
	var r7: GdUnitBoolAssert = assert_bool(ball_snapshot.is_read_only()).is_true()
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(ball_position.is_read_only()).is_true()
	@warning_ignore("unused_variable")
	var r9: GdUnitFloatAssert = assert_float(locomotion.players[1].position_m.x).is_equal(4.0)
	@warning_ignore("unused_variable")
	var r10: GdUnitFloatAssert = assert_float(ball.state.position_m.x).is_equal(7.0)
	@warning_ignore("unused_variable")
	var r11: GdUnitBoolAssert = assert_bool(unbound_ball_snapshot.is_read_only()).is_true()

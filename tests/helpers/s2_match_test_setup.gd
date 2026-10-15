class_name S2MatchTestSetup
extends RefCounted
## Test-only composition setup for match, replay and Main integration tests.


## Deterministic no-contact provider for tests that keep the ball held.
class EmptyWorldContactSource:
	extends BallContactSource

	func detect_contacts(_position_m: Vector3, _orientation: Quaternion) -> Array[BallContact]:
		return []

	func is_available() -> bool:
		return true

	func snapshot() -> Dictionary:
		return {"fixture": "empty_world_contact_source", "version": 1}

	func is_transaction_stateless() -> bool:
		return true


## Deterministic solver for the empty-world provider's empty contact rows.
class EmptyWorldContactSolver:
	extends BallContactSolver

	func solve_contacts(
		_state: BallState, contacts: Array[BallContact], responses: Array[ContactResult], _dt: float
	) -> bool:
		return contacts.is_empty() and responses.is_empty()

	func is_available() -> bool:
		return true

	func snapshot() -> Dictionary:
		return {"fixture": "empty_world_contact_solver", "version": 1}

	func is_transaction_stateless() -> bool:
		return true


## Creates an S2-valid match config with explicit fixture environment values.
static func match_config(seed_value: int = 0) -> MatchConfig:
	var config: MatchConfig = MatchConfig.create_default()
	assert(config != null)
	assert(config.s2_physics != null)
	config.seed = seed_value
	config.s2_physics.pitch_condition = 0
	config.s2_physics.stadium_id = 0
	return config


## Creates a complete fixture port. The player is off pitch and the ball is held, so these
## integration tests do not claim to cover player-owner or collision behavior.
static func runtime_port() -> S2RuntimePort:
	var port: S2RuntimePort = S2RuntimePort.new()
	port.set_contact_source(EmptyWorldContactSource.new())
	port.set_contact_solver(EmptyWorldContactSolver.new())
	var environment_set: bool = port.set_locomotion_environment(0, 0)
	assert(environment_set, "test environment setup must be valid")
	if not environment_set:
		return null
	var wind_policy: S2WindPolicy = S2WindPolicy.create(false, Vector3.ZERO)
	var wind_set: bool = port.set_wind_policy(wind_policy)
	assert(wind_set, "test wind policy must be valid")
	if not wind_set:
		return null
	var ball_setup: S2BallInitialization = S2BallInitialization.new()
	ball_setup.mode = BallState.Mode.HELD
	ball_setup.goal_kick_state = BallState.GoalKickState.OFF
	ball_setup.wind_policy = wind_policy
	var ball_initialized: bool = port.initialize_ball(ball_setup)
	assert(ball_initialized, "test ball setup must be valid")
	if not ball_initialized:
		return null
	var player: PlayerMotionState = PlayerMotionState.new()
	player.player_id = &"fixture-player"
	player.team_id = &"fixture-team"
	player.shirt_number = 1
	player.on_pitch = false
	player.initialized = true
	player.speed_stat = 0.0
	player.acceleration_stat = 0.0
	player.urgency = 0.0
	player.sprint_request = 0
	player.sprint_energy = 0.0
	player.sprint_energy_initialized = true
	var player_setup: S2PlayerInitialization = S2PlayerInitialization.new()
	player_setup.player = player
	var player_added: bool = port.add_player(player_setup)
	assert(player_added, "test player setup must be valid")
	if not player_added:
		return null
	return port

class_name PreparedTick
extends RefCounted
## Opaque one-use authorization and rollback handle for a prepared simulation tick.

var candidate_frame: InputFrame:
	get:
		return SimTickContext._copy_frame(_candidate_frame)
var commands: DetachedCommandBundle:
	get:
		return DetachedCommandBundle.new(_commands.records_in_order())
var outcome: SimTickOutcome:
	get:
		return _outcome
var outputs: Array[RefCounted]:
	get:
		return SystemTickResult._copy_records(_outputs)
var signal_batch: SignalBatch:
	get:
		return _signal_batch
var candidate_tick: int:
	get:
		return _outcome.candidate_tick

var _sim: MatchSim
var _checkpoint: Dictionary
var _owner_captures: Array[OwnerCapture]
var _candidate_frame: InputFrame
var _commands: DetachedCommandBundle
var _outcome: SimTickOutcome
var _outputs: Array[RefCounted]
var _signal_batch: SignalBatch
var _active: bool = true
var _replay_source_row: Variant


func _init(
	p_sim: MatchSim,
	p_checkpoint: Dictionary,
	p_owner_captures: Array[OwnerCapture],
	p_candidate_frame: InputFrame,
	p_commands: DetachedCommandBundle,
	p_outcome: SimTickOutcome,
	p_outputs: Array[RefCounted],
	p_signal_batch: SignalBatch,
	p_replay_source_row: Variant = null
) -> void:
	_sim = p_sim
	_checkpoint = p_checkpoint
	_owner_captures = p_owner_captures.duplicate()
	_candidate_frame = SimTickContext._copy_frame(p_candidate_frame)
	_commands = DetachedCommandBundle.new(p_commands.records_in_order())
	_outcome = p_outcome
	_outputs = SystemTickResult._copy_records(p_outputs)
	_signal_batch = p_signal_batch
	_replay_source_row = p_replay_source_row

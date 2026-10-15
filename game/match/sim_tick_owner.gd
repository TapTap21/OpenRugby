class_name SimTickOwner
extends SimSystem
## Opt-in lifecycle participant in the ordinary ordered system registry.


## Captures this owner's immutable pre-update view.
func capture_tick(_context: SimTickContext) -> OwnerCaptureResult:
	return OwnerCaptureResult.new(false, null, ERR_UNCONFIGURED)


## Commits the capture against the completed generic outcome.
func commit_tick(
	_context: SimTickContext, _capture: OwnerCapture, _outcome: SimTickOutcome
) -> OwnerCommitResult:
	return OwnerCommitResult.new(false, ERR_UNCONFIGURED)

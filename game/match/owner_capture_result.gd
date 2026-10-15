class_name OwnerCaptureResult
extends RefCounted
## Checked result from a tick owner's pre-update capture.

var ok: bool:
	get:
		return _ok
var capture: OwnerCapture:
	get:
		return _capture
var error: Error:
	get:
		return _error

var _ok: bool
var _capture: OwnerCapture
var _error: Error


func _init(p_ok: bool, p_capture: OwnerCapture, p_error: Error) -> void:
	_ok = p_ok
	_capture = p_capture
	_error = p_error

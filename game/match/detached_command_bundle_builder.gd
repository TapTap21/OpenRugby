class_name DetachedCommandBundleBuilder
extends RefCounted
## Mutable sampling buffer that seals into an immutable ordered command bundle.

var _records: Array[RefCounted] = []
var _sealed: bool = false


## Appends a detached copy of one concrete command record.
func append(record: RefCounted) -> Error:
	if _sealed or record == null:
		return ERR_INVALID_PARAMETER
	var copy: RefCounted = DetachedCommandBundle._copy_record(record)
	if copy == null:
		return ERR_INVALID_DATA
	_records.append(copy)
	return OK


## Seals the current ordered records. Later appends are rejected.
func seal() -> DetachedCommandBundle:
	_sealed = true
	return DetachedCommandBundle.new(_records)

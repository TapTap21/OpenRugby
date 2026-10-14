class_name PitchSurfaceTable
extends Resource
## Observed six-row pitch response table from RE 06 §2.4.

@export var rows: Array[PitchSurfaceParams] = []


static func create_classic() -> PitchSurfaceTable:
	var table: PitchSurfaceTable = PitchSurfaceTable.new()
	var values: Array[Array] = [
		[1.6, 1.5, 0.2, 0.7, 0.06],
		[1.6, 1.5, 0.2, 0.7, 0.06],
		[1.5, 1.4, 0.15, 0.7, 0.06],
		[1.3, 1.2, 0.1, 0.6, 0.07],
		[1.4, 1.4, 0.2, 0.8, 0.07],
		[1.4, 1.5, 0.2, 0.6, 0.04],
	]
	for row_values: Array in values:
		var row: PitchSurfaceParams = PitchSurfaceParams.new()
		row.bounce_side_on = row_values[0]
		row.bounce_end_on = row_values[1]
		row.unused_bounce_randomness = row_values[2]
		row.friction = row_values[3]
		row.rolling_resistance = row_values[4]
		table.rows += [row]
	return table


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if rows.size() != 6:
		errors += PackedStringArray(["pitch surface table must contain six rows"])
	for row: PitchSurfaceParams in rows:
		if row == null:
			errors += PackedStringArray(["pitch surface row is missing"])
		else:
			errors.append_array(row.validate())
	return errors


## Stadium ids 0x19/0x1d select row 2 regardless of pitch condition.
func get_for(condition: int, stadium_id: int) -> PitchSurfaceParams:
	var selected: int = 2 if stadium_id == 0x19 or stadium_id == 0x1d else condition
	if selected < 0 or selected >= rows.size():
		return null
	return rows[selected]

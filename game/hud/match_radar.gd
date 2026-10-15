class_name MatchRadar
extends Control
## Optional two-team radar with the observed fifteen-player dot capacity per side.

const PLAYERS_PER_TEAM: int = 15
const CONTROLLED_COLORS: Array[Color] = [
	Color("00468c"), Color("e60000"), Color("00a5ff"), Color("d7ff00")
]
const DOT_SIZE: Vector2 = Vector2(9.0, 9.0)

@export var field_length: float = 100.0
@export var field_width: float = 70.0
@export var home_color: Color = Color("ba332d")
@export var away_color: Color = Color("315d8b")

var _home_dots: Array[ColorRect] = []
var _away_dots: Array[ColorRect] = []
@onready var _field_area: Control = %FieldArea


func _ready() -> void:
	_create_dots(_home_dots, home_color)
	_create_dots(_away_dots, away_color)


## Toggles the radar overlay independently of other match HUD items.
func set_radar_enabled(enabled: bool) -> void:
	visible = enabled


## Updates player positions and highlights a controlled dot for controller slots 1 through 4.
func set_players(
	home_positions: Array[Vector3],
	away_positions: Array[Vector3],
	controlled_side: int = -1,
	controlled_player: int = -1,
	controller_slot: int = 0
) -> void:
	_update_team(_home_dots, home_positions, home_color)
	_update_team(_away_dots, away_positions, away_color)
	if controller_slot < 1 or controller_slot > CONTROLLED_COLORS.size():
		return
	var dots: Array[ColorRect] = _home_dots if controlled_side == 0 else _away_dots
	if controlled_side >= 0 and controlled_side <= 1 and controlled_player >= 0:
		if controlled_player < dots.size() and dots[controlled_player].visible:
			dots[controlled_player].color = CONTROLLED_COLORS[controller_slot - 1]


func _create_dots(dots: Array[ColorRect], tint: Color) -> void:
	for player_index: int in range(PLAYERS_PER_TEAM):
		var dot: ColorRect = ColorRect.new()
		dot.name = "PlayerDot%d" % player_index
		dot.size = DOT_SIZE
		dot.color = tint
		dot.visible = false
		_field_area.add_child(dot)
		dots.append(dot)


func _update_team(dots: Array[ColorRect], positions: Array[Vector3], tint: Color) -> void:
	var area_size: Vector2 = _field_area.size
	var visible_count: int = mini(positions.size(), dots.size())
	for player_index: int in range(dots.size()):
		var dot: ColorRect = dots[player_index]
		dot.color = tint
		dot.visible = player_index < visible_count
		if not dot.visible:
			continue
		var position: Vector3 = positions[player_index]
		var fraction_x: float = clampf(position.x / field_length + 0.5, 0.0, 1.0)
		var fraction_z: float = clampf(position.z / field_width + 0.5, 0.0, 1.0)
		dot.position = Vector2(
			fraction_x * area_size.x - DOT_SIZE.x * 0.5, fraction_z * area_size.y - DOT_SIZE.y * 0.5
		)

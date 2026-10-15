class_name BroadcastScoreboard
extends Control
## Match score and clock overlay; data is supplied by the match owner.

@export var home_color: Color = Color("ba332d")
@export var away_color: Color = Color("315d8b")

var _home_score: int = 0
var _away_score: int = 0

@onready var _home_name: Label = %HomeName
@onready var _away_name: Label = %AwayName
@onready var _score: Label = %Score
@onready var _clock: Label = %Clock
@onready var _period: Label = %Period


func _ready() -> void:
	_home_name.add_theme_color_override("font_color", home_color)
	_away_name.add_theme_color_override("font_color", away_color)


## Sets the two display names supplied by the selected match setup.
func configure(home_name: String, away_name: String) -> void:
	_home_name.text = home_name
	_away_name.text = away_name
	_refresh_score()


## Updates both sides of the scorebox.
func set_score(home_score: int, away_score: int) -> void:
	_home_score = maxi(0, home_score)
	_away_score = maxi(0, away_score)
	_refresh_score()


## Displays a game-time value and the current period caption.
func set_clock(seconds: float, period_label: String) -> void:
	var whole_seconds: int = maxi(0, floori(seconds))
	_clock.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	_period.text = period_label


func _refresh_score() -> void:
	_score.text = "%d  –  %d" % [_home_score, _away_score]

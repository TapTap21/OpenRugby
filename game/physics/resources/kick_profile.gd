class_name KickProfile
extends Resource
## Observed velocity and elevation ranges for one kick type (RE 06 §2.6).

@export var type_id: int = -1
@export var speed_low_m_s: float = 0.0
@export var speed_high_m_s: float = 0.0
@export var elevation_low_degrees: float = 0.0
@export var elevation_high_degrees: float = 0.0
@export var power_rating_applies: bool = false

class_name CampfireLight
extends OmniLight3D
## Warm flickering light for campfires.

const _FLICKER_SPEED := 9.0
const _FLICKER_AMOUNT := 0.35

var _noise := FastNoiseLite.new()
var _t := randf() * 100.0


func _ready() -> void:
	light_color = GameConstants.CAMPFIRE_LIGHT_COLOR
	omni_range = GameConstants.CAMPFIRE_LIGHT_RANGE
	light_energy = GameConstants.CAMPFIRE_LIGHT_ENERGY
	shadow_enabled = false
	_noise.frequency = 1.0


func _process(delta: float) -> void:
	_t += delta * _FLICKER_SPEED
	light_energy = GameConstants.CAMPFIRE_LIGHT_ENERGY * (1.0 + _FLICKER_AMOUNT * _noise.get_noise_1d(_t))

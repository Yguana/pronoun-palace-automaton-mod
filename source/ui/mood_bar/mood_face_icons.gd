extends Sprite2D

var original_pos: Vector2
var shake_percent: float = 0.0
var smooth_tween

func _ready() -> void:
	original_pos = global_position
	set_process(false)

func set_shake(start_shaking: bool) -> void:
	var final_value = 1.0 if start_shaking else 0.0
	
	if start_shaking:
		set_process(true)
		shake_percent = 0.01 # To not immediately set bad to 0 due to delta
	
	if smooth_tween:
		smooth_tween.kill()
	smooth_tween = create_tween()
	smooth_tween.tween_property(self,"shake_percent",final_value,0.2)

func _shake() -> void:
	global_position.x = original_pos.x + (randf_range(-0.4,0.4) * shake_percent)
	global_position.y = original_pos.y + (randf_range(-0.4,0.4) * shake_percent)

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	if shake_percent == 0.0:
		set_process(false)
		global_position = original_pos
		return
	_shake()

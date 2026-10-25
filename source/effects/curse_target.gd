extends "res://source/effects/coord_target.gd"

@export var color_gradient: Gradient
var unique_timer = 4.0 # Replicating the same duration as tile_sprite.tscn > cursed


func _ready() -> void:
	super._ready()
	modulate_loop()

func modulate_loop() -> void:
	var color_tween = create_tween()
	color_tween.tween_method(_set_modulate_to_tween,0.0,1.0,unique_timer)
	await color_tween.finished
	modulate_loop()

func _set_modulate_to_tween(tween_value: float) -> void:
	modulate.r = color_gradient.sample(tween_value).r
	modulate.g = color_gradient.sample(tween_value).g
	modulate.b = color_gradient.sample(tween_value).b

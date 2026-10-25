extends Node2D

const starting_scale = Vector2(0.75,0.75)
const ending_scale = Vector2(1.3,1.3)
const poof_scales = [ Vector2(1.15,1.15), Vector2(1.1,1.1) ]
const starting_poof_modulates = [Color("BD401F"),Color("ffde4f") ]
const poof_speed_playbacks = [ 1.8, 1.5, 1.5 ]
const ending_poof_modulate = Globals.COLORS.COAL

# Code from this script takes heavily from battle_unit_sprite.gd

var poof_cloud_room = preload("res://source/effects/poofcloud.tscn")


func travel_and_disappear(global_destination: Vector2,faster_anim_time: bool) -> void:
	
	if Game.main.enemy is Enemy:
		z_index = Game.main.enemy.z_index + 1
	scale = starting_scale
	
	var animation_time = _get_animation_time(faster_anim_time)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self,"global_position",global_destination,animation_time).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self,"scale",ending_scale,animation_time).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	for x in range(poof_scales.size()):
		var poof_cloud = poof_cloud_room.instantiate()
		Game.main.add_child(poof_cloud)
		poof_cloud.scale = poof_scales[x]
		poof_cloud.global_position = self.global_position
		poof_cloud.modulate = starting_poof_modulates[x]
		poof_cloud.speed_scale = poof_speed_playbacks[x]
		poof_cloud.color_fade(ending_poof_modulate, 3 - poof_speed_playbacks[x])
		poof_cloud.rotation_degrees = randi_range(1,4) * 90
	
	queue_free()

func _get_animation_time(faster_anim: bool) -> float:
	return 0.35 if faster_anim else 0.4

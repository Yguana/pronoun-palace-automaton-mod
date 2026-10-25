extends Node

var effect_color = Color("fff")

func prepare_work_color(work_type:Automaton.WORK_TYPES) -> void:
	effect_color = Automaton.WORK_TYPE_COLORS[work_type]

func prepare_finger_picked_color(new_color: Color) -> void:
	effect_color = new_color

func play_fade_on_enemy(enemy_node:Node2D) -> void:
	var previous_modulate = enemy_node.modulate
	enemy_node.modulate = effect_color
	var tween = get_tree().create_tween()
	tween.tween_property(enemy_node,"modulate",previous_modulate,0.6)
	await tween.finished
	queue_free()

extends Node
class_name IntentBounceAnimator

var _previous_multiplier: float = 0.0
var _new_multiplier: float = 0.0

func _init(previous_multiplier: float, new_multiplier:float) -> void:
	_previous_multiplier = previous_multiplier
	_new_multiplier = new_multiplier

func bounce_intent(target_intent: Node2D) -> void:
	var tween = get_tree().create_tween()
	var scale_difference = 1.15 if _new_multiplier > _previous_multiplier else 0.85
	target_intent.scale = Vector2(scale_difference,scale_difference)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(target_intent,"scale",Vector2(1,1),0.6)
	await tween.finished
	queue_free()

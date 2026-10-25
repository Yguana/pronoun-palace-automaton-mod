extends ArcingProjectile

func set_up_and_throw_self(root_node: AutomatonMoodBar = null) -> void:
	if root_node == null:
		return
	position = root_node.offset_node.position
	rotation_degrees = root_node.offset_node.rotation_degrees
	var sprite_clone = root_node.sprite.duplicate()
	add_child(sprite_clone)
	sprite_clone.frame = 2
	
	var destination = Vector2(position.x + randi_range(-30,-50),1000)
	launch(global_position, destination, 40)
	angular_velocity = 0
	angular_deceleration = 0
	decelerate_to = 0

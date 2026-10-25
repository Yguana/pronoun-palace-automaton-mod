extends Node


# This script goes unused. Keeping it here in case i figure a way to make it work.

@onready var sprite = %Sprite

func _ready() -> void:
	move_and_await()

func move_and_await() -> void:
	var new_pos = sprite.position
	while new_pos == sprite.position:
		new_pos = Vector2(sprite.position.x + randi_range(-1,1),sprite.position.y + randi_range(-1,1))
		new_pos.x = clamp(new_pos.x,-1,1)
		new_pos.y = clamp(new_pos.y,-1,1)
	sprite.position = new_pos
	await Game.timeout(randf_range(1.0,3.0))
	move_and_await()

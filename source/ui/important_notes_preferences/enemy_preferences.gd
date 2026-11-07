extends Control

@export var preference_icons: Array[Node]

@onready var enemy_sprite = %EnemySprite
@onready var custom_enemy_sprite = %CustomEnemySprite
@onready var error_sprite = %ErrorSprite


func prepare_preference(enemy_id, single_preferences: Array) -> void:
	_set_enemy_icon(enemy_id)
	
	for icon in preference_icons:
		icon.set_sprite(single_preferences)

func _set_enemy_icon(enemy_id) -> void:
	enemy_sprite.visible = false
	custom_enemy_sprite.visible = false
	error_sprite.visible = false
	
	if enemy_id in EnemyLoader.custom_phonebook_icons:
		custom_enemy_sprite.texture=load(EnemyLoader.custom_phonebook_icons[enemy_id])
		custom_enemy_sprite.visible = true
		return
	
	var coord = Enemies.get_icon_frame_coord(enemy_id)
	if coord == Vector2i(0,0) and enemy_id != Enemies.CAT and Enemies.DECLAWED:
		error_sprite.visible = true
		return
	
	if Enemies.is_shadow(enemy_id):
		enemy_sprite.texture = load("res://arte/ui/enemy_shadow_icons.png")
	else:
		enemy_sprite.texture = load("res://arte/ui/enemy_icons.png")
	
	enemy_sprite.frame_coords = coord
	enemy_sprite.visible = true

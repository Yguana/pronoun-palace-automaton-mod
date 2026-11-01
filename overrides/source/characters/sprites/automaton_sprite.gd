@tool
extends CharacterSprite

const fireball_attack = preload("res://mods/automaton_character/source/effects/fireball_attack.tscn")
var moving_enemy_true_markers = {
	Enemies.NOPPY: "NoppyOffset/Noppy",
	Enemies.SOPPY: "NoppyOffset/Noppy",
	Enemies.SNOWBALL: "Sprite",
	Enemies.NOBODY: "CigaretteMarker"
}
var special_enemy_markers = {
	Enemies.NPCS: _special_npc_targeting,
	Enemies.TRAFFIC: _special_npc_targeting
}
var special_enemy_offsets = {
	# ACT 1
	Enemies.CAT: Vector2(30,10),
	Enemies.DECLAWED: Vector2(30,10),
	
	Enemies.NPCS: Vector2(0,-39),
	Enemies.TRAFFIC: Vector2(0,-39),
	
	Enemies.PEOPLE: Vector2(30,10),
	Enemies.DECEDENT: Vector2(30,10),
	
	Enemies.NOPPY: Vector2(-10,-15),
	Enemies.SOPPY: Vector2(-10,-15),
	
	Enemies.FAT_CAT: Vector2(30,20),
	Enemies.PURRGEOISIE: Vector2(30,20),
	
	# ACT 2
	Enemies.SNOWBALL: Vector2(-15,-60),
	Enemies.EIGHTBALL: Vector2(-15,-60),
	
	Enemies.STRAWMAN: Vector2(5,35),
	Enemies.HOUSEBROKEN: Vector2(5,35),
	
	Enemies.UFO: Vector2(-15,25),
	
	Enemies.BRUTALIST: Vector2(20,10),
	
	# ACT 3
	Enemies.PRODIGY: Vector2(10,-15),
	Enemies.INVALID: Vector2(10,-15),
	
	Enemies.UMAMI: Vector2(10,-10),
	Enemies.SALT: Vector2(10,-10),
	
	Enemies.BAMMON: Vector2(30,-10),
}
@onready var fireball_point = %FireballMarker


func _init() -> void:
	bleed_override = Color("222")

func summon_and_throw_fireball() -> void:
	var enemy_id = Game.main.enemy.id
	var fire_instance = fireball_attack.instantiate()
	Game.main.add_child(fire_instance)
	fire_instance.global_position = fireball_point.global_position
	
	
	var enemy_hit_pos
	var faster_anim = false
	
	if special_enemy_markers.keys().has(enemy_id):
		faster_anim = true
		var method_to_call : Callable = special_enemy_markers[enemy_id]
		enemy_hit_pos = method_to_call.call().global_position
		
	elif moving_enemy_true_markers.keys().has(enemy_id):
		faster_anim = true
		var possible_node = Game.main.enemy.sprite.get_node(moving_enemy_true_markers[enemy_id])
		if possible_node != null:
			enemy_hit_pos = possible_node.global_position
		else:
			enemy_hit_pos = Game.main.enemy.hit_marker.global_position 
	else:
		enemy_hit_pos = Game.main.enemy.hit_marker.global_position
	
	var hit_offset = Vector2(20,0)
	if special_enemy_offsets.keys().has(enemy_id):
		hit_offset = special_enemy_offsets[enemy_id]
	enemy_hit_pos.x += hit_offset.x
	enemy_hit_pos.y += hit_offset.y
	
	
	fire_instance.travel_and_disappear(enemy_hit_pos,faster_anim)
	await fire_instance.tree_exited
	emit_signal("hit")
	AudioManager.play_sound(Sounds.GENERIC.HIT)

func _special_npc_targeting() -> Node2D:
	var first_npc = Game.main.enemy.sprite.get_live_npcs()[0]
	return first_npc

func play_extra_hurt_sound() -> void:
	AudioManager.play_sound(Sounds.PROLE_SERVICE.TONE,0.5,1.4)
	await Game.timeout(0.02)
	AudioManager.play_sound(Sounds.PROLE_SERVICE.TONE,0.65,1.4)

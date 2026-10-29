extends Node2D
class_name AutomatonMoodBar

const nobody_bar_fragment_room = preload("res://mods/automaton_character/source/ui/mood_bar/mood_bar_nobody_fragment.tscn")
const sprite_ammount_per_spritesheet = 4

enum DIRECTION {
	HORIZONTAL,
	VERTICAL
}
@export var bar_direction: DIRECTION = DIRECTION.HORIZONTAL
@export var on_debug_enviroment: bool = false

@onready var sprite = %MainSprite
@onready var happy_face_sprite = %FunMoodFace
@onready var sad_face_sprite = %SadMoodFace
@onready var pointer = %Pointer
@onready var ghost_pointer = %GhostPointer
@onready var extreme_point_l: Marker2D = %MaxHappyPoint
@onready var extreme_point_r: Marker2D = %MaxSadPoint
@onready var anim_player:AnimPlayer = %AnimPlayer

@onready var offset_node = %MoodBarOffset
@onready var tooltip_collision = %TooltipCollision

var mood_tooltip: GameTooltip = null

var spell_node: Spell = null # Connected via important_nodes.gd._ready()

var pointer_move_tween
var bar_space_length = 0
var step_length = 0

var is_hidden = false

signal fully_loaded

func _ready() -> void:
	bar_space_length = extreme_point_l.position.distance_to(extreme_point_r.position)
	
	if not on_debug_enviroment:
		Game.main.player_action_started.connect(_on_player_actionable)
		Game.main.word_builder.submitted_word.connect(_on_word_was_submitted)
	else:
		play_mutually_exclusive_fade(true)
	
	if bar_direction == DIRECTION.VERTICAL:
		sprite.hframes = sprite_ammount_per_spritesheet
	elif bar_direction == DIRECTION.HORIZONTAL:
		sprite.vframes = sprite_ammount_per_spritesheet
	
	tooltip_collision.generate_tooltip.connect(_give_tooltip_mood_infodump)
	tooltip_collision.hovered_off.connect(_remove_tooltip)
	step_length = bar_space_length/20
	reset_pointers()
	
	if spell_node.player_spell_slot == null:
		await spell_node.charge_updated
	spell_node.player_spell_slot.despawned.connect(func(): queue_free())
	
	fully_loaded.emit()


func _on_player_actionable() -> void:
	play_mutually_exclusive_fade(true)

@warning_ignore("unused_parameter")
func _on_word_was_submitted(word,damage,turn_end) -> void: #Arguments are signal leftovers
	if not _should_wait_to_dissappear_on_turn_end():
		play_mutually_exclusive_fade(false)

func play_mutually_exclusive_fade(appearing: bool) -> void:
	anim_player.play_reversible_appear_disappear(appearing,false,"appear","disappear")
	is_hidden = appearing

func reset_pointers() -> void:
	if pointer_move_tween:
		pointer_move_tween.kill()
	set_normal_pointer_position(0)
	set_and_show_ghost_pointer_position(0)
	hide_ghost_pointer()
	_shake_applicable_mood_faces(0)

func _get_proper_coord_from_mood_value(mood_value: int) -> float:
	return step_length * -mood_value

func set_normal_pointer_position(mood_value: int) -> void:
	if pointer == null:
		for x in range(get_child_count()):
			var new_child = await child_entered_tree
			if new_child == pointer:
				break
	
	match bar_direction:
		DIRECTION.HORIZONTAL:
			pointer.position.x = _get_proper_coord_from_mood_value(mood_value)
		DIRECTION.VERTICAL:
			pointer.position.y = _get_proper_coord_from_mood_value(mood_value)
	_shake_applicable_mood_faces(mood_value)

func set_and_show_ghost_pointer_position(mood_value: int) -> void:
	ghost_pointer.show()
	match bar_direction:
		DIRECTION.HORIZONTAL:
			ghost_pointer.position.x = _get_proper_coord_from_mood_value(mood_value)
		DIRECTION.VERTICAL:
			ghost_pointer.position.y = _get_proper_coord_from_mood_value(mood_value)

func hide_ghost_pointer() -> void:
	if ghost_pointer == null:
		return
	ghost_pointer.hide()

func slide_pointer_to_new_position(new_mood_value: int) -> void:
	var new_pos = _get_proper_coord_from_mood_value(new_mood_value)
	var affected_tween_property = "position:x" if bar_direction == DIRECTION.HORIZONTAL else  "position:y"
	if pointer_move_tween:
		pointer_move_tween.kill()
	pointer_move_tween = create_tween()
	pointer_move_tween.set_trans(Tween.TRANS_BACK)
	pointer_move_tween.set_ease(Tween.EASE_IN_OUT)
	pointer_move_tween.tween_property(pointer,affected_tween_property,new_pos,0.3)
	await pointer_move_tween.finished
	_shake_applicable_mood_faces(new_mood_value)

func _give_tooltip_mood_infodump(tooltip: GameTooltip) -> void:
	mood_tooltip = tooltip
	var mood_string_group = StringManager.get_string_group(Automaton.STRINGS.MOOD_STRING_GROUP)
	var is_fighting_nobody = Game.main.enemy.id == Enemies.NOBODY
	tooltip.add_subtooltip(
		mood_string_group.get_string(Automaton.STRINGS.MOOD_STRING_GROUP_ITEMS.NAME),
		mood_string_group.get_string(Automaton.STRINGS.MOOD_STRING_GROUP_ITEMS.DESCRIPTION,{on_nobody = is_fighting_nobody})
	)

func _remove_tooltip() -> void:
	if mood_tooltip != null:
		mood_tooltip.queue_free()

func animate_apperance_to_nobody_state(instant: bool,nobody_node: NobodyBoss = null) -> void:
	if instant:
		_hide_non_nobody_components()
		return
	if nobody_node == null:
		return
	
	var shake_tween = create_tween()
	var original_offset_pos = offset_node.position
	shake_tween.tween_method(_shake_offset.bind(original_offset_pos),0.0,2.0,2)
	# Signal comes from nobody_automaton.gd, which is the only situation this func should be called
	await nobody_node.reached_shatter_moodbar_moment
	
	var jump_offset = Vector2(position.x - 2, position.y - 12)
	var jump_tween = create_tween()
	jump_tween.set_parallel(true)
	jump_tween.tween_property(self,"position", jump_offset ,0.1).set_trans(Tween.TRANS_BACK)
	jump_tween.tween_property(offset_node,"rotation_degrees", -2 ,0.1)
	AudioManager.play_sound(Sounds.BAMMON.BONE_CRACK,0.7)
	await jump_tween.finished
	
	self.position = Vector2(0,0)
	offset_node.position = Vector2( offset_node.position.x + jump_offset.x, offset_node.position.y + jump_offset.y)
	_hide_non_nobody_components()
	sprite.position.y -= 4
	
	shake_tween.kill()
	shake_tween = create_tween()
	create_tween().tween_property(sprite,"position:y", sprite.position.y + 4 ,0.3).set_trans(Tween.TRANS_BACK)
	shake_tween.tween_method(_shake_offset.bind(offset_node.position),2.0,0.0,0.5)
	var bounce_back_tween = create_tween()
	bounce_back_tween.set_parallel(true)
	bounce_back_tween.set_trans(Tween.TRANS_BACK)
	bounce_back_tween.set_ease(Tween.EASE_OUT)
	bounce_back_tween.tween_property(offset_node,"position",original_offset_pos,1).set_delay(0.8)
	bounce_back_tween.tween_property(offset_node,"rotation_degrees",0,1).set_delay(0.8)
	var nobody_bar_piece = nobody_bar_fragment_room.instantiate()
	add_child(nobody_bar_piece)
	nobody_bar_piece.set_up_and_throw_self(self)

func _hide_non_nobody_components() -> void:
	sprite.frame = 1
	happy_face_sprite.hide()


func _shake_offset(seconds_since_tween_start:float,original_pos: Vector2) -> void:
	offset_node.position = Vector2(
		original_pos.x + (randf_range(-2,2) * seconds_since_tween_start),
		original_pos.y + (randf_range(-2,2) * seconds_since_tween_start)
	)

# Will be called manually by imporant_nodes.gd when this happens
func _should_wait_to_dissappear_on_turn_end() -> bool:
	return abs(spell_node.mood_value) == 10 or spell_node.is_fully_charged()

func _shake_applicable_mood_faces(on_mood_set_to: int) -> void:
	happy_face_sprite.set_shake(false)
	sad_face_sprite.set_shake(false)
	
	if on_mood_set_to == 10:
		happy_face_sprite.set_shake(true)
	elif on_mood_set_to == -10:
		sad_face_sprite.set_shake(true)

func debug_slider(slider_value: float) -> void:
	slide_pointer_to_new_position(int(slider_value))

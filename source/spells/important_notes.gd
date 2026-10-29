extends Spell

const work_preferences = preload("res://mods/automaton_character/misc/work_preferences.gd")
const special_enemy_sprites = preload("res://mods/automaton_character/misc/special_enemy_sprites.gd")
const enemy_color_filter = preload("res://mods/automaton_character/source/effects/enemy_color_filter.tscn")
const mood_bar_room = preload("res://mods/automaton_character/source/ui/mood_bar/mood_bar.tscn")
const multiplier_sub_tooltip = preload("res://mods/automaton_character/source/ui/mood_bar/mood_multipliers_subtooltip.tscn")

var Intent = WordBuilder.Intent

const preference_multipliers = [
	1.12,  # Really Likes
	0.83,  # Likes
	-0.83, # Dislikes
	-1.12  # Really Dislikes
]
const default_preferences_failsafe = [
	Automaton.WORK_PREFERENCES.LIKES,
	Automaton.WORK_PREFERENCES.DISLIKES,
	Automaton.WORK_PREFERENCES.REALLY_LIKES,
	Automaton.WORK_PREFERENCES.REALLY_DISLIKES
]

const main_use_sound = Sounds.SPELLS.PILLS

var mood_value = 0
var max_pos_mood_value = 10
var max_neg_mood_value = -10

var pos_mood_revert_bonus = 3 # Amount of defense which will be added when mood goes from 10 -> 0
var should_add_pos_mood_bonus = false # Used to indicate when the defense bonus from above should be calculated
var neg_mood_revert_bonus = 5 # Amount of attack which will be added when mood goes from -10 -> 0
var should_add_neg_mood_bonus = false # Used to indicate when the damage bonus from above should be calculated

# Amount of times the mood bar has been reset in an encounter due to bonus triggers
# Starts as -1 as it always increases duing turn end, while the effect only happens at turn start
var mood_bonus_resets_on_this_fight = -1 

var has_switched_to_nobody_moods = false 
var has_red_letter_upgraded_this_session = false

# state (using enum from mod.gd) is the var used to mannipulate sprite changes and behaviour changes
# if it is set to a valid word type range
# -1 is no work selected; 0-3 is work types, 4 is for shimmer edge case, and 5 is for repeated words
var state = -1 


# Used to store the last X words used (X being max_recent_words_size)
var recent_words = []
const max_recent_words_size = 5
var recent_word_queue_placement = 0 # Used when a word in recent_words is in word builder to display label properly
var last_checked_recent_word = "" # Auxiliary var used for working out situations with shimmered words
var _ignoring_repeat_words = false # Used mainly for debug

var mood_bar: AutomatonMoodBar = null
var is_mood_bar_placed = false
var current_multiplier_preview: GameTooltip = null

signal mood_value_changed(new_value)
signal mood_value_previewed(preview_value)
signal placed_mood_bar
signal presented_categorized_word(mood_value_change)

func _ready() -> void :
	_run_starting_configs()

func _run_starting_configs() -> void:
	_update_state_logic(state)
	Game.main.player_action_started.connect(_on_turn_start)
	word_builder.finished_updating_stats.connect(_correct_intents_post_builder_update)
	tile_board.turn_ended.connect(early_turn_end)
	player_spell_slot.tooltip_collision.generate_tooltip.connect(_on_tooltip_generated)
	
	if Game.main.is_battle and not is_mood_bar_placed:
		place_mood_bar_ui()
	
	work_preferences.push_modded_enemies_into_list()

func get_hv_frames() -> Vector2i:
	return Vector2i(1, 7)

func get_frame() -> int:
	return state + 1

func switch_state(new_state: int):
	if state == new_state and new_state != 5:
		return
	if new_state < -1 || new_state > 5:
		return
	
	_update_state_logic(new_state)

func _update_state_logic(new_state: int) -> void:
	state = new_state
	
	if state == 5: # Recent repeat word
		if _is_word_builder_with_last_checked_recent_word():
			return
	else:
		last_checked_recent_word = ""
	
	shake.emit()
	frame_updated.emit()
	description_updated.emit()

func get_save_data():
	var save = super.get_save_data()
	save["mood_value"] = mood_value
	save["recent_words"] = recent_words
	save["should_add_pos_mood_bonus"] = should_add_pos_mood_bonus
	save["should_add_neg_mood_bonus"] = should_add_neg_mood_bonus
	save["mood_bonus_resets_on_this_fight"] = mood_bonus_resets_on_this_fight
	return save

func load_save_data(save):
	super.load_save_data(save)
	mood_value = save.mood_value
	recent_words = save.recent_words
	should_add_pos_mood_bonus = save.should_add_pos_mood_bonus
	should_add_neg_mood_bonus = save.should_add_neg_mood_bonus
	mood_bonus_resets_on_this_fight = save.mood_bonus_resets_on_this_fight
	if not is_mood_bar_placed:
		await Game.main.player_action_started
		await place_mood_bar_ui(true)
		await mood_bar.fully_loaded
	mood_bar.set_normal_pointer_position(mood_value)

func is_ignoring_updates() -> bool:
	return ((not Game.main.is_game_actionable()) and word_builder.tiles.is_empty()) or word_builder.is_submitting

# Is called by nobody_automaton in two instances: 
# - During the nobody_automaton mood bar cutscene;
# - and when reloading the game with nobody_automaton as the enemy;
func make_nobody_changes(from_continue_run: bool) -> void:
	has_switched_to_nobody_moods = true
	if from_continue_run:
		if not is_mood_bar_placed:
			await placed_mood_bar
		mood_bar.animate_apperance_to_nobody_state(true)
	max_pos_mood_value = 0



#==================================================================================
#                                TOOLTIP & LABELS

func get_tooltip_context():
	return {curse = curse, work_type = state, recent_word_queue_placement = recent_word_queue_placement}

func _is_word_builder_with_last_checked_recent_word() -> bool:
	var local_words = word_builder.get_words().words.duplicate()
	while local_words.size() > 2:
		local_words.pop_back()
	for word in local_words:
		if word == last_checked_recent_word:
			return true
	_update_recent_word_queue_placement(word_builder.get_words().words)
	return false

func _update_recent_word_queue_placement(words: Array[String]) -> void:
	var new_pos = -1
	for word in words:
		if recent_words.has(word):
			var pos_in_recent_array = recent_words.find(word)
			if pos_in_recent_array > new_pos:
				last_checked_recent_word = word
				new_pos = pos_in_recent_array
	if new_pos == -1:
		return
	
	var new_value
	if recent_words.size() == max_recent_words_size:
		new_value = new_pos + 1
	else:
		new_value = max_recent_words_size - recent_words.size() + new_pos
	recent_word_queue_placement = new_value

func _is_word_builder_words_in_recent_uses() -> bool:
	var written_words = word_builder.get_words().words
	var max_word_ammount = 1 if not _is_word_builder_with_shimmer() else 2
	if written_words.is_empty():
		return false
	if written_words.size() > max_word_ammount:
		return true #Satefy measure as to avoid continuing and blocking use regardless
		
	for word in written_words:
		if recent_words.has(word): 
			return true
	return false

# Slightly more technical name. Treat it as if it was on_hover with a delay
@warning_ignore("unused_parameter")
func _on_tooltip_generated(tooltip) -> void:
	_toggle_extra_hover_info(true)

func on_unhover() -> void:
	_toggle_extra_hover_info(false)

func _toggle_extra_hover_info(showing_info: bool):
	if current_multiplier_preview != null:
			current_multiplier_preview.queue_free()
	if showing_info:
		if state == -1 or state == 5: # Item cannot be used, thus shouldn't preview lot of things
			return 
		var future_mood = get_future_mood_value() if state != 4 else -mood_value
		if mood_value == future_mood:
			if mood_value == max_pos_mood_value or mood_value == max_neg_mood_value:
				_replace_multiplier_tooltip(future_mood)
			return
		_replace_multiplier_tooltip(future_mood)
		if mood_bar == null:
			return
		mood_value_previewed.emit(future_mood)
		mood_bar.set_and_show_ghost_pointer_position(future_mood)
	else:
		if mood_bar == null:
			return
		mood_bar.hide_ghost_pointer()

func get_curse_description() -> String:
	if curse == CURSE.CURSED:
		return StringManager.get_string("curse/automaton_character_item_generic")
	return super.get_curse_description()



#==================================================================================
#                               ENEMY PREFERENCES

func get_enemy_word_preference(enemy_id:String) -> Array:
	if _is_enemy_in_category_preferences(enemy_id):
		return work_preferences.list[enemy_id]
	
	if enemy_id == Enemies.NOBODY:
		# Checks if this is the actual Automaton Nobody
		if ( 
			Game.main.enemy.has_method("instinct")   and
			Game.main.enemy.has_method("insight")    and
			Game.main.enemy.has_method("attachment") and
			Game.main.enemy.has_method("repression")
		):
			return _get_nobody_current_preference()
		else: # If it is a generic nobody (i.e.: For coop fights)
			return work_preferences.edgecase_nobody_preference
	
	return default_preferences_failsafe

func _is_enemy_in_category_preferences(enemy_id: String) -> bool:
	if work_preferences.list.keys().has(enemy_id):
		return true
	return false

func _get_nobody_current_preference() -> Array:
	var nobody_node: NobodyBoss = Game.main.enemy
	var nobody_move_names = Automaton.STRINGS.INTENT_STRING_GROUP_ITEMS 
	var preferences = [
		Automaton.WORK_PREFERENCES.REALLY_DISLIKES,
		Automaton.WORK_PREFERENCES.REALLY_DISLIKES,
		Automaton.WORK_PREFERENCES.REALLY_DISLIKES,
		Automaton.WORK_PREFERENCES.REALLY_DISLIKES
	]
	
	var index_to_change = -1
	match nobody_node.next_move:
		nobody_move_names.NOBODY_INSTINCT:
			index_to_change = 0
		nobody_move_names.NOBODY_INSIGHT:
			index_to_change = 1
		nobody_move_names.NOBODY_ATTACHMENT:
			index_to_change = 2
		nobody_move_names.NOBODY_REPRESSION:
			index_to_change = 3
	preferences[index_to_change] = Automaton.WORK_PREFERENCES.LIKES
	
	return preferences



#==================================================================================
#                                WORD CATEGORIES

func get_word_category(word:String) -> int:
	if _is_word_in_category_list(word):
		return Automaton.WORD_CATEGORIES[word]
	return -1

func _is_word_in_category_list(word: String) -> bool:
	if Automaton.WORD_CATEGORIES.keys().has(word):
		return true
	return false

func _has_valid_words_on_word_builder() -> bool:
	# Checks for word_builder.can_submit(), but ignores the repeat word condition
	if not word_builder.can_submit_tiles() or not word_builder.can_submit_words(word_builder.get_words()):
		switch_state(-1) # No work type state
		return false
	if _is_word_builder_words_in_category_list():
		if _is_word_builder_words_in_recent_uses() and not _ignoring_repeat_words:
			switch_state(5) #Repeated word state
			return false
		var word_work_type
		if _is_word_builder_with_shimmer():
			var work_list = [
				get_word_category(word_builder.get_words().words[0]),
				get_word_category(word_builder.get_words().words[1])
			]
			if work_list[0] > -1 and work_list[1] > -1: # Both shimmer words have a work type
				switch_state(4) # Shimmer state
				return true
			else:
				word_work_type = work_list[0] if work_list[0] > -1 else work_list[1]
			
		else:
			word_work_type = get_word_category(word_builder.get_words().words[0])
		assert(
			word_work_type >= 0 and word_work_type <= 3,
			"'%s' category listed as a type %s, which is invalid." % [word_builder.get_words().words[0], word_work_type])
		switch_state(word_work_type) # Matching work type state
		return true
	switch_state(-1) # No work type state
	return false

func _is_word_builder_words_in_category_list() -> bool:
	var written_words = word_builder.get_words().words
	var max_word_ammount = 1 if not _is_word_builder_with_shimmer() else 2
	if written_words.size() > max_word_ammount or written_words.is_empty():
		return false
	
	for word in written_words:
		if _is_word_in_category_list(word): 
			return true
	return false

func _is_word_builder_with_shimmer() -> bool:
	for tile: Tile in word_builder.tiles:
		if tile.is_shimmering():
			return true
	return false



#==================================================================================
#                                  SPELL USAGE

func is_usable():
	return super.is_usable() and _has_valid_words_on_word_builder()

func _use():
	if not is_usable():
		_end_use()
		return
	
	_toggle_extra_hover_info(false)
	
	# First sound placed here to give feedback that the spell is working, but mood didn't change
	AudioManager.play_sound(main_use_sound)
	
	var new_value
	if state == 4: # Shimmer tiles at play
		new_value = -mood_value
	else:
		new_value = get_future_mood_value(not has_curse(CURSE.CURSED)) # Doesn't clamp value if it is cursed
	
	# One of the Hazel clearence curse gimmicks.
	if has_curse(CURSE.CURSED):
		var cursed_tile_ammount = 0
		if new_value > max_pos_mood_value: 
			cursed_tile_ammount = new_value - max_pos_mood_value
		elif new_value < max_neg_mood_value:
			cursed_tile_ammount = new_value - max_neg_mood_value
		cursed_tile_ammount = ( abs(cursed_tile_ammount) + 1 ) * 2
		
		if cursed_tile_ammount > 0: 
			_handle_cursed_tiles_spawning(cursed_tile_ammount)
			new_value = clamp(new_value,max_neg_mood_value,max_pos_mood_value)
	
	var should_run_main_use = mood_value != new_value
	
	if should_run_main_use:
		_main_use(new_value)
	
	if state != 4: # Not in shimmer state
			# Emits signal particularly important for nobody_automaton.gd
			var presented_word = word_builder.get_words().words[0]
			presented_categorized_word.emit(get_word_category(presented_word),presented_word.length())
			
			# Checks if the main use function hasn't been run
			# When fighting Nobody, the use case where using the sound wouldn't play
			# isn't applicable, as the word submitted should give feeback regardless
			# of if the mood value changed.
			if not should_run_main_use and has_switched_to_nobody_moods:
				_run_visual_and_audio_use_effects(new_value)
	
	switch_state(-1)
	_post_use()

# Essentially just a part of _use(). Separated into another function to make that function more readable
# Changes mood value, updates all relevant indicators and corrects intents to match.
func _main_use(new_mood_value: int) -> void:
	var old_mults = _get_mood_affected_full_multipliers(mood_value)
	mood_value = new_mood_value
	mood_value_changed.emit(new_mood_value)
	mood_bar.slide_pointer_to_new_position(new_mood_value)
	_correct_intents_post_builder_update() # Certifies that damage mult and defense mult intents will exist
	
	
	var max_word_to_add_in_recent = 1 if state != 4 else 2 #Changes to add two words to recent in shimmer state
	
	for word_index in range(max_word_to_add_in_recent):
		var possible_recent_word = word_builder.get_words().words[word_index]
		if not recent_words.has(possible_recent_word):
			recent_words.append(possible_recent_word)
			if recent_words.size() > max_recent_words_size:
				recent_words.pop_front()
	
	_run_visual_and_audio_use_effects(new_mood_value)
	
	if old_mults.damage_multiplier != word_builder.damage_multiplier:
		_request_intent_bounce_tween(
			_get_existing_intent_node(Intent.DAMAGE_MULTIPLIER),
			old_mults.damage_multiplier,
			word_builder.damage_multiplier
		)
	if old_mults.defense_multiplier != word_builder.defense_multiplier:
		_request_intent_bounce_tween(
			_get_existing_intent_node(Intent.DEFENSE_MULTIPLIER),
			old_mults.defense_multiplier,
			word_builder.defense_multiplier
		)
		

func get_future_mood_value(clamp_result: bool = true) -> int:
	if not is_usable(): # If the is useable, state and word_builder.get_words() should only return legal values
		return mood_value
	var word_work_type = state
	var word_size = word_builder.get_words().words[0].length()
	var full_enemy_preferences = get_enemy_word_preference(Game.enemy.id)
	
	var mood_gain_multiplier = preference_multipliers[full_enemy_preferences[word_work_type]]
	var mood_value_change = _get_mood_value_change_from_word_length(word_size)
	mood_value_change = int(mood_value_change*mood_gain_multiplier)
	var base_value
	if (mood_value_change > 0) == (mood_value > 0) or mood_value == 0 or has_switched_to_nobody_moods:
		base_value = mood_value
	else:
		base_value = _get_fair_lowered_mood_for_sign_swap()
	
	var new_mood_value = base_value + mood_value_change
	
	if clamp_result:
		return clamp(new_mood_value,max_neg_mood_value,max_pos_mood_value)
	
	return new_mood_value

func _get_mood_value_change_from_word_length(length: int) -> float:
	return length # Returns a greater value with red letter

func _get_fair_lowered_mood_for_sign_swap() -> int:
		return mood_value - ceil(mood_value*(2.0/7)) 

func _get_mood_affected_base_multipliers(fomula_value: int) -> Dictionary:
	fomula_value = clamp(fomula_value, max_neg_mood_value, max_pos_mood_value)
	var raw_damage_mult = _math_formula(-fomula_value)
	var raw_defense_mult = _math_formula(fomula_value)
	var return_dict = {
		"damage_multiplier" : raw_damage_mult,
		"defense_multiplier": raw_defense_mult 
	} 
	return return_dict

func _get_mood_affected_full_multipliers(fomula_value: int, with_corrected_value: bool = false) -> Dictionary:
	var base_multipliers = _get_mood_affected_base_multipliers(fomula_value)
	var crit_dam_multiplier_additions
	var crit_def_multiplier_additions
	
	if not with_corrected_value:
		crit_dam_multiplier_additions = word_builder.damage_multiplier  - 1
		crit_def_multiplier_additions = word_builder.defense_multiplier - 1
	else:
		var current_mood_mults = _get_mood_affected_base_multipliers(mood_value)
		crit_dam_multiplier_additions = word_builder.damage_multiplier  - current_mood_mults.damage_multiplier
		crit_def_multiplier_additions = word_builder.defense_multiplier - current_mood_mults.defense_multiplier
		
	base_multipliers.damage_multiplier  += crit_dam_multiplier_additions
	base_multipliers.defense_multiplier += crit_def_multiplier_additions 
	return base_multipliers

# Exponential equation that results in the proper multipliers. Done by Natalie. Thanks Natalie :-)
func _math_formula(x:int) -> float:
	var rawY = pow(((0.0174293 * x ) + 1.17429),10.01728) 
	var y = ceil(rawY)/10
	return y



#==================================================================================
#                            VANILLA SIGNAL HANDLERS 

func _on_game_state_changed() -> void:
	if Game.main.is_paused(): 
		_toggle_extra_hover_info(false)

func _on_turn_start() -> void:
	if should_add_pos_mood_bonus:
		_create_mood_bonus_reset_filter(true)
		_play_extra_use_sound(10) # As if it was a negative mood increase
		player.defense += get_bonus_reset_value(true)
		should_add_pos_mood_bonus = false
		
	elif should_add_neg_mood_bonus:
		_create_mood_bonus_reset_filter(false)
		_play_extra_use_sound(-10) # As if it was a negative mood increase
		# No other variables is changed as that the real bonus is managed through the damage recalculation
	
	if not is_mood_bar_placed:
		await place_mood_bar_ui()
	mood_bar.play_mutually_exclusive_fade(true)

func early_turn_end(): # Called just as tile_board emits turn_ended
	switch_state(-1)
	_toggle_extra_hover_info(false)

func turn_end():
	should_add_neg_mood_bonus = false
	should_add_pos_mood_bonus = false
	
	# Uses abs() 10 instead of max_pos_mood_value/max_neg_mood_value as the overflow should only happen
	# to avoid situations outside of the Nobody fight, which is designed with that in mind
	if abs(mood_value) == 10:
		await _handle_max_mood_reset_and_bonus()
	
	super.turn_end()
	if is_fully_charged():
		if has_curse(CURSE.CURSED):
			_set_for_late_cursed_transform()
			
		_handle_no_use_mood_halving()
	

func battle_started():
	super.battle_started()
	if not is_mood_bar_placed:
		await place_mood_bar_ui()
	mood_bar.play_mutually_exclusive_fade(true)

func battle_ended():
	mood_value = 0
	if is_mood_bar_placed:
		mood_bar.reset_pointers()
	
	should_add_neg_mood_bonus = false
	should_add_pos_mood_bonus = false
	mood_bonus_resets_on_this_fight = -1



#==================================================================================
#                                VISUALS & AUDIO

func _run_visual_and_audio_use_effects(from_mood_value: int) -> void:
	_play_extra_use_sound(from_mood_value)
	_create_enemy_mood_filter_effect() 

func _play_extra_use_sound(mood_value_for_pitch: int) -> void:
	var sfx_pitch = 1 + (mood_value_for_pitch * 0.05)
	AudioManager.play_sound(Sounds.SPELLS.CLOVER_EAT_A,sfx_pitch,1.5)

func _request_intent_bounce_tween(target_node: Node2D, previous_mult: float, new_mult: float) -> void:
	var tween_node = IntentBounceAnimator.new(previous_mult,new_mult)
	Game.main.add_child(tween_node)
	tween_node.bounce_intent(target_node)

func _create_enemy_mood_filter_effect() -> void:
	var enemy_filter = enemy_color_filter.instantiate()
	enemy_filter.prepare_work_color(state)
	Game.enemy.add_child(enemy_filter)
	var sprites = _get_enemy_effect_target()
	for sprite in sprites:
		enemy_filter.play_fade_on_enemy(sprite)

func _get_enemy_effect_target() -> Array[Node2D]:
	if special_enemy_sprites.list.keys().has(Game.main.enemy.id):
		var return_array:Array[Node2D] = []
		for sprite_path in special_enemy_sprites.list[Game.main.enemy.id]:
			return_array.append(Game.main.enemy.get_node(sprite_path))
		return return_array
	return [Game.main.enemy]



#==================================================================================
#                                   MOOD BAR

func _create_mood_bar() -> void:
	if mood_bar == null:
		mood_bar = mood_bar_room.instantiate()
		mood_bar.spell_node = self

func place_mood_bar_ui(play_fade_in: bool = false) -> void:
	if is_mood_bar_placed:
		return
	if mood_bar == null:
		_create_mood_bar()
	var ui_layer = Game.main.get_node("GameUILayer")
	if Game.main.enemy == null or ui_layer == null:
		return
	ui_layer.add_child(mood_bar)
	is_mood_bar_placed = true
	placed_mood_bar.emit()
	mood_bar.tree_exiting.connect( func(): is_mood_bar_placed = false)
	await mood_bar.tree_entered
	if play_fade_in:
		mood_bar.play_mutually_exclusive_fade(true)

func _replace_multiplier_tooltip(new_mood: int) -> void:
	if current_multiplier_preview != null:
		current_multiplier_preview.queue_free()
	
	var tooltip: GameTooltip = player_spell_slot.tooltip_collision.tooltip_scene.instantiate()
	var next_mults = _get_mood_affected_full_multipliers(new_mood,true)
	var sub_tooltip: AutomatonMultipliersSubTooltip = multiplier_sub_tooltip.instantiate()
	
	Game.main.tile_board.add_child(tooltip)
	tooltip.add_subtooltip_node(sub_tooltip)
	
	sub_tooltip.set_new_multiplier_labels(
		next_mults.damage_multiplier,
		next_mults.defense_multiplier,
		(new_mood == max_pos_mood_value or new_mood == max_neg_mood_value) and new_mood == mood_value
	)
	tooltip.z_index = 99
	
	var board_reference = Game.main.tile_board
	if board_reference == null:
		return
	tooltip.global_position = board_reference.global_position
	tooltip.global_position.y -= 60
	tooltip.global_position.x += - (tooltip.size.x / 2)
	tooltip.update_panels()
	tooltip.reset_size()
	tooltip.display()
	current_multiplier_preview = tooltip



#==================================================================================
#                                   MOOD BONUS

func _handle_no_use_mood_halving() -> void:
	mood_value = ceil(mood_value/2.0)
	
	await _force_mood_bar_turn_end_change(mood_value)

func _handle_max_mood_reset_and_bonus() -> void:
	# Reaches this part of the code already assuming mood_value is at the normal max (10 or -10)
	
	if mood_value > 0: # Positive/Happy Mood
		should_add_pos_mood_bonus = true
	else: # Negative/Segative Mood
		should_add_neg_mood_bonus = true
	mood_value = 0
	
	AudioManager.play_sound(main_use_sound)
	mood_bonus_resets_on_this_fight += 1
	
	await _force_mood_bar_turn_end_change(mood_value)

func _force_mood_bar_turn_end_change(new_mood_value: int) -> void:
	AudioManager.play_sound(main_use_sound)
	await mood_bar.slide_pointer_to_new_position(new_mood_value)
	await Game.timeout(0.4)
	mood_bar.play_mutually_exclusive_fade(false)
	await Game.timeout(0.1)

func get_bonus_reset_value(for_positive_bonus: bool) -> int:
	if for_positive_bonus:
		return pos_mood_revert_bonus + (mood_bonus_resets_on_this_fight * 2)
	else:
		return neg_mood_revert_bonus + (mood_bonus_resets_on_this_fight * 2)

func _create_mood_bonus_reset_filter(positive_mood: bool) -> void:
	var enemy_filter = enemy_color_filter.instantiate()
	var matching_color = Color("89B831") if positive_mood else Color("EB4929")
	
	enemy_filter.prepare_finger_picked_color(matching_color)
	player.add_child(enemy_filter)
	enemy_filter.play_fade_on_enemy(player.sprite)

#==================================================================================
#                                  RED LETTER

func _first_spawn(is_transform: = false) -> void:
	var check_for_mood_bar = false
	
	if is_transform:
		has_red_letter_upgraded_this_session = true
		check_for_mood_bar = true
	if Game.main.is_battle:
		check_for_mood_bar = true
	
	if check_for_mood_bar and mood_bar == null:
			await place_mood_bar_ui()


func transform_spell(new_spell_id, keep_secret_id = true, keep_curse = true, keep_charge_amount = false, keep_charge_properties = false, keep_extra_max_charge = false, early_modifier: = Callable()) -> Spell:
	if mood_bar != null:
		mood_bar.queue_free()
	var spell = super.transform_spell(new_spell_id,keep_secret_id,keep_curse,keep_charge_amount,keep_charge_properties,keep_extra_max_charge,early_modifier)
	return spell



#==================================================================================
#                                 HAZEL CLEARANCE

func _handle_cursed_tiles_spawning(cursed_tile_ammount: int) -> void:
	if not has_curse(CURSE.CURSED):
		return
	if cursed_tile_ammount < 1:
		cursed_tile_ammount = 1
	
	var target_tiles = []
	for x in range(cursed_tile_ammount):
		var tiles = tile_board.get_tiles({
			effect_priority = [Globals.TileStatus.CURSED],
			exclude_final_effect_priority = true,
			exclude_tiles = target_tiles
		})
		if tiles.is_empty():
			break
		
		shake.emit()
		var iteration_tile: Tile = rng.spell.pick_random(tiles)
		target_tiles.append(iteration_tile)
		iteration_tile.add_status(TileStatus.CURSED)
		iteration_tile.add_poofcloud(iteration_tile.get_color())
		await Game.timeout(0.12)

func _get_cursed_tile_ammount(specific_mood_value: int) -> int:
	return abs(specific_mood_value - int(specific_mood_value/3))

func _set_for_late_cursed_transform() -> void:
	var saved_mood_value = mood_value
	await Game.main.player_action_started
	_handle_cursed_tiles_spawning(_get_cursed_tile_ammount(saved_mood_value))




#==================================================================================
# Everything beyond this point is mainly just stuff to create the illusion that
# the base attack/defense multipliers are changing. It consists of mainly redoing
# or meddling with things in intent_container.gd and word_builder.gd

@warning_ignore("unused_parameter") #Piggybacking off a convenient signal. "words" is never directly used on this one.
func _correct_intents_post_builder_update(words = null):
	if is_ignoring_updates():
		return
	var corrected_multipliers: Dictionary = _get_mood_affected_full_multipliers(mood_value)
	word_builder.damage_multiplier  = corrected_multipliers.damage_multiplier
	word_builder.defense_multiplier = corrected_multipliers.defense_multiplier
	
	_force_update_multiplier_intent(Intent.DAMAGE_MULTIPLIER, word_builder.damage_multiplier) 
	_force_update_multiplier_intent(Intent.DEFENSE_MULTIPLIER, word_builder.defense_multiplier) 
	
	var no_mult_values: Dictionary = _builder_recalculate_damamge_defense()
	if no_mult_values.damage != 0 or should_add_neg_mood_bonus:
		var final_flat_damage = no_mult_values.damage
		if should_add_neg_mood_bonus:
			final_flat_damage += get_bonus_reset_value(false)
		word_builder.damage = int(ceil(final_flat_damage * word_builder.damage_multiplier))
		if should_add_neg_mood_bonus: 
			_force_update_damage_intent(word_builder.damage,no_mult_values.damage)
		else:
			_force_update_relevant_intent_node(_get_existing_intent_node(Intent.DAMAGE),word_builder.damage)
	if no_mult_values.defense != 0:
		word_builder.defense = int(ceil(no_mult_values.defense * word_builder.defense_multiplier))
		_force_update_relevant_intent_node(_get_existing_intent_node(Intent.DEFENSE),word_builder.defense)


func _get_existing_intent_node(intent_type) -> Node2D:
	var already_existing_intent = null # intent.gd
	for existing_intent in word_builder.intent_container.intent_instances:
		if existing_intent.get_key() == Intent.keys()[intent_type].to_lower():
			already_existing_intent = existing_intent
			break
	return already_existing_intent


func _force_update_relevant_intent_node(intent_node, context_value) -> void:
	if intent_node == null: 
		return 
	
	var relevant_intents = [Intent.DAMAGE, Intent.DEFENSE, Intent.DAMAGE_MULTIPLIER, Intent.DEFENSE_MULTIPLIER]
	var node_type = intent_node.intent
	if not relevant_intents.has(node_type):
		return
	
	var specific_context
	match node_type:
		Intent.DAMAGE:
			specific_context = {damage = context_value}
		Intent.DEFENSE:
			specific_context = {defense = context_value}
		Intent.DAMAGE_MULTIPLIER, Intent.DEFENSE_MULTIPLIER:
			specific_context = {multiplier = context_value}
	intent_node.set_intent(node_type,specific_context)

func _force_update_damage_intent(true_damage,before_fix_damage) -> void:
	if before_fix_damage != 0: # No damage tiles are on the word builder:
		_force_update_relevant_intent_node(_get_existing_intent_node(Intent.DAMAGE),true_damage)
		return
	word_builder.add_intent(Intent.DAMAGE, {damage = true_damage})

func _force_update_multiplier_intent(intent_type, context_value) -> void:
	var no_tile_addition_mults = _get_mood_affected_base_multipliers(mood_value)
	if context_value != no_tile_addition_mults[Intent.keys()[intent_type].to_lower()]: 
		#Reaches here when crits have surpassed usual threshold and already made an intent node
		_force_update_relevant_intent_node(_get_existing_intent_node(intent_type),context_value)
		return
	word_builder.add_intent(intent_type, {multiplier = context_value})

func _builder_recalculate_damamge_defense() -> Dictionary:
	var return_dict = {
		"damage" : 0,
		"defense": 0 
	} 
	for tile: Tile in word_builder.tiles:
		var value: = tile.get_value()
		var frozen: = tile.has_status(TileStatus.FROZEN)
		
		if tile.has_value():
			if tile.type == TileType.DAMAGE or frozen:
				return_dict.damage += value
			if tile.type == TileType.DEFENSE or frozen:
				return_dict.defense += value
	return return_dict

func _builder_recalculate_multipliers() -> Dictionary:
	var return_dict = {
		"damage_multiplier" : 1.0,
		"defense_multiplier": 1.0,
	}
	
	for tile: Tile in word_builder.tiles:
		var is_crit: = tile.has_status(TileStatus.CRIT)
		var bomb_status = tile.get_status(TileStatus.BOMB)
		if bomb_status:
			is_crit = bomb_status.turns == 1

		if is_crit:
			var crit_addition: float = Game.balance.crit_value - 1
			if tile.type == TileType.DAMAGE:
				return_dict.damage_multiplier += crit_addition
			else:
				return_dict.defense_multiplier += crit_addition
	return return_dict

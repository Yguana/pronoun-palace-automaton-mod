extends Spell

const work_preferences = preload("res://mods/automaton_character/misc/work_preferences.gd")
const special_enemy_sprites = preload("res://mods/automaton_character/misc/special_enemy_sprites.gd")
const enemy_color_filter = preload("res://mods/automaton_character/source/effects/enemy_color_filter.tscn")
const mood_bar_room = preload("res://mods/automaton_character/source/ui/mood_bar/mood_bar.tscn")
const multiplier_sub_tooltip = preload("res://mods/automaton_character/source/ui/mood_bar/mood_multipliers_subtooltip.tscn")
const enemy_preference_tooltip = preload("res://mods/automaton_character/source/ui/important_notes_preferences/enemy_preferences.tscn")

var Intent = WordBuilder.Intent

const preference_multipliers = [
	1,43,  # Really Likes
	1.11,  # Likes
	-1.11, # Dislikes
	-1.43  # Really Dislikes
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

var pos_mood_revert_bonus = 2 # Amount of defense which will be added when mood goes from 10 -> 0
var should_add_pos_mood_bonus = false # Used to indicate when the defense bonus from above should be calculated
var neg_mood_revert_bonus = 2 # Amount of attack which will be added when mood goes from -10 -> 0
var should_add_neg_mood_bonus = false # Used to indicate when the damage bonus from above should be calculated

var base_mult_extreme: float:
	get():
		return min(
			min_base_mult_extreme + (base_mult_extreme_step * (mood_bonus_resets_on_this_fight + 1)),
			max_base_mult_extreme
		)
var min_base_mult_extreme = 1.4
var max_base_mult_extreme = 2.0
var base_mult_extreme_step: float:
	get():
		return get_base_mult_extreme_step()

# Amount of times the mood bar has been reset in an encounter due to bonus triggers
# Starts as -1 as it always increases duing turn end, while the effect only happens at turn start
var mood_bonus_resets_on_this_fight = -1 

var has_switched_to_nobody_moods = false 
var has_red_letter_upgraded_this_session = false

# state (using enum from mod.gd) is the var used to mannipulate sprite changes and behaviour changes
# if it is set to a valid word type range
# -1 is no work selected; 0-3 is work types, 4 is for shimmer edge case, and 5 is for repeated words
var state = -1 


# Used to store the last X words used (X being max_recent_words_size).
# This is used to prevent words brom being used back-to-back by the spell
var recent_words = []
const max_recent_words_size = 5
var recent_word_queue_placement = 0 # Used when a word in recent_words is in word builder to display label properly
var last_checked_recent_word = "" # Auxiliary var used for working out situations with shimmered words
var _ignoring_repeat_words = false # Used mainly for debug

# The mood bar is an additional UI element added to show the player the current mood_value value
var mood_bar: AutomatonMoodBar = null
var is_mood_bar_placed = false

# Preview that shows the damage and defense multiplier when hovering above the spell if it can be used
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
	
	work_preferences.push_modded_enemies_into_list()

func get_hv_frames() -> Vector2i:
	return Vector2i(1, 7)

func get_frame() -> int:
	return state + 1

func switch_state(new_state: int):
	# Checks if the state would changed to a different one. Exception is made for
	# state "5" as that might need to update the spell label to match the word position
	# in the recent word queue. 
	# Also checks if the state is within a valid range
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
	if not is_mood_bar_placed: # Places moodbar and corrects the pointer back to the match mood_value position
		await Game.main.player_action_started
		await place_mood_bar_ui(true)
		await mood_bar.fully_loaded
	mood_bar.set_normal_pointer_position(mood_value)

func is_ignoring_updates() -> bool:
	return ((not Game.main.is_game_actionable()) and word_builder.tiles.is_empty()) or word_builder.is_submitting

# Next method is called by nobody_automaton in two instances: 
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

func generate_player_spell_base_tooltip(tooltip: GameTooltip) -> void:
	var enemy_mood_holder = tile_board.create_preview_tile()
	enemy_mood_holder.hover_container.visible = false # Hides the tile sprite
	
	var true_tooltip = enemy_preference_tooltip.instantiate()
	enemy_mood_holder.add_child(true_tooltip)
	tooltip.add_subtooltip(get_title(), get_description(),enemy_mood_holder)
	
	true_tooltip.prepare_preference(Game.enemy.id,get_enemy_word_preference(Game.enemy.id))

func get_curse_description() -> String:
	if curse == CURSE.CURSED:
		return StringManager.get_string("curse/automaton_character_item_generic")
	return super.get_curse_description()

## Updates the value of recent_word_queue_placement.[br]
## Reserved for when the spell enters state "5", which means the word builder has a repeat term.
func _is_word_builder_with_last_checked_recent_word() -> bool:
	var local_words = word_builder.get_words().words.duplicate()
	while local_words.size() > 2: # Lowers it up enough to check in case there is shimmer terms
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
			if pos_in_recent_array > new_pos: # Prioritizes always showing the longest shimmer word
				last_checked_recent_word = word
				new_pos = pos_in_recent_array
	if new_pos == -1:
		return
	
	var new_value
	if recent_words.size() == max_recent_words_size:
		new_value = new_pos + 1
	else:
		new_value = max_recent_words_size - recent_words.size() + new_pos
	recent_word_queue_placement = new_value # Saves the value in the var which is passed on the label context

func _is_word_builder_words_in_recent_uses() -> bool:
	var written_words = word_builder.get_words().words
	var max_word_ammount = 1 if not _is_word_builder_with_shimmer() else 2
	if written_words.is_empty():
		return false
	if written_words.size() > max_word_ammount:
		return true # Satefy measure as to avoid continuing and blocking use regardless
		
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
		if state == -1 or state == 5: # spell cannot be used, thus shouldn't instantiate a new tooltip
			return 
		var future_mood = get_future_mood_value() if state != 4 else -mood_value
		if mood_value == future_mood:
			# Exception made to indicate to the player they are already at one of the mood extremes
			# This is a very specific edgecase that doesn't happen normally
			# This is mostly leftovers of a previous iteration of the spell, but it is being kept in
			# case other mods or future gimmicks allow for auto spells to be rechaged on the same turn
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
	tooltip.z_index = 300 # Set to be higher than screw and linked tile effects
	
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
		nobody_move_names.NOBODY_INSTINCT:   index_to_change = 0
		nobody_move_names.NOBODY_INSIGHT:    index_to_change = 1
		nobody_move_names.NOBODY_ATTACHMENT: index_to_change = 2
		nobody_move_names.NOBODY_REPRESSION: index_to_change = 3
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
	# Checks for word_builder.can_submit(), but ignores the repeat words and checks if the word is in a category
	if (
		not word_builder.can_submit_tiles() or
		not word_builder.can_submit_words(word_builder.get_words()) or 
		not _is_word_builder_words_in_category_list()
	):
		switch_state(-1) # No work type state
		return false
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
	switch_state(word_work_type) # Sets the state to match the current word category / work type
	return true

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
	
	# Removes any tooltips and mood bar preview changes if those were active
	_toggle_extra_hover_info(false) 
	
	# First sound placed here to give feedback that the spell is working even if mood didn't change
	AudioManager.play_sound(main_use_sound)
	
	var new_value
	if state == 4: # Shimmer tiles at play
		new_value = -mood_value
	else:
		new_value = get_future_mood_value(not has_curse(CURSE.CURSED)) # Doesn't clamp value if it is cursed
	
	# Previous Hazel clearence gimmick
	
	#if has_curse(CURSE.CURSED):
	#	var cursed_tile_ammount = 0
	#	if new_value > max_pos_mood_value: 
	#		cursed_tile_ammount = new_value - max_pos_mood_value
	#	elif new_value < max_neg_mood_value:
	#		cursed_tile_ammount = new_value - max_neg_mood_value
	#	cursed_tile_ammount = max(0,abs(cursed_tile_ammount))
	#	
	#	if cursed_tile_ammount > 0:
	#		_handle_cursed_tiles_spawning(cursed_tile_ammount)
	#		new_value = clamp_to_fit_mood_value_range(new_value)
	
	var should_run_main_use = mood_value != new_value
	
	if should_run_main_use:
		_main_use(new_value)
	
	if state != 4: # Not in shimmer state
			# Emits signal particularly important for nobody_automaton.gd
			var presented_word = word_builder.get_words().words[0]
			presented_categorized_word.emit(get_word_category(presented_word),presented_word.length())
			
			# Checks if the main use function hasn't been run.
			# When fighting Nobody, the use case where using the sound wouldn't play
			# (when the spell will not run it's main function) isn't applicable, as the
			# word submitted can still have an effect due to Nobody's intent gimmick and
			# thus give feeback regardless of if the mood value changed.
			if not should_run_main_use and has_switched_to_nobody_moods:
				_run_visual_and_audio_use_effects(new_value)
	
	if has_curse(CURSE.CURSED):
		await _hazel_tarnish_presented_word()
	
	switch_state(-1) # No work type state
	_post_use()

# Essentially just a part of _use(). Separated into another function to make that function more readable
# Changes mood value, updates all relevant indicators and corrects intents to match.
func _main_use(new_mood_value: int) -> void:
	var old_mults = _get_mood_affected_full_multipliers(mood_value)
	mood_value = new_mood_value
	mood_value_changed.emit(new_mood_value)
	mood_bar.slide_pointer_to_new_position(new_mood_value)
	_correct_intents_post_builder_update() # Certifies that damage mult and defense mult intents will exist
	
	
	var max_word_to_add_in_recent = 1 if state != 4 else 2 # Changes to add two words to recent_words if in shimmer state
	
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
	if not is_usable(): # If the is usable, state and word_builder.get_words() should only return legal values
		return mood_value
	var word_work_type = state
	var word_size = word_builder.get_words().words[0].length()
	var full_enemy_preferences = get_enemy_word_preference(Game.enemy.id)
	
	var mood_gain_multiplier = preference_multipliers[full_enemy_preferences[word_work_type]]
	var mood_value_change = _get_mood_value_change_from_word_length(word_size)
	mood_value_change = int(mood_value_change * mood_gain_multiplier)
	
	var final_change
	if mood_value_change < 1 and mood_value_change > -1: 
		final_change = mood_value_change/abs(mood_value_change)
	else:
		final_change = mood_value_change
	
	var base_value
	if (final_change > 0) == (mood_value > 0) or mood_value == 0 or has_switched_to_nobody_moods:
		base_value = mood_value
	else:
		# When switching from Happy --> Sad or Sad --> Happy, gives the the player a small boost by
		# using a lowered mood value as the base. This is to allow for easier switches in desperate
		# situations, which could feel unfair / tedious otherwise.
		base_value = _get_fair_lowered_mood_for_sign_swap()
	
	var new_mood_value = base_value + final_change
	
	if clamp_result:
		return clamp_to_fit_mood_value_range(new_mood_value)
	
	return new_mood_value

func clamp_to_fit_mood_value_range(value: int) -> int:
	return clamp(value,max_neg_mood_value,max_pos_mood_value)

func _get_mood_value_change_from_word_length(length: int) -> float:
	return length # Returns a greater value with red letter

func _get_fair_lowered_mood_for_sign_swap() -> int:
	return mood_value - ceil(mood_value*(2.0/7)) 

func _get_mood_affected_base_multipliers(fomula_value: int) -> Dictionary:
	fomula_value = clamp(fomula_value, max_neg_mood_value, max_pos_mood_value)
	var raw_damage_mult = _math_formula(-fomula_value)
	var raw_defense_mult = _math_formula(fomula_value)
	
	var return_dict = {
		"damage_multiplier" : min(raw_damage_mult,base_mult_extreme),
		"defense_multiplier": min(raw_defense_mult,base_mult_extreme)
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

func get_base_mult_extreme_step() -> float:
	return 0.2

# Exponential equation that results in the proper multipliers. Done by Natalie. Thanks Natalie :-)
func _math_formula(x:int) -> float:
	var rawY = pow(((0.0174293 * x ) + 1.17429),10.01728) 
	var y = ceil(rawY)/10
	return y



#==================================================================================
#                            VANILLA SIGNAL HANDLERS 

func _on_game_state_changed() -> void:
	if Game.main.is_paused():
		# Removes any tooltips/previews so they don't interfere with pause behaviour (appear above it)
		_toggle_extra_hover_info(false) 

func _on_turn_start() -> void:
	if should_add_pos_mood_bonus:
		_create_mood_bonus_reset_filter(true)
		_play_extra_use_sound(10) # As if it was a positive mood increase
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
	var has_reset_mood = false
	
	# Uses abs() == 10 instead of max_pos_mood_value/max_neg_mood_value because, while normally
	# those do return an absolute value of 10, during the Nobody fight, the player should be res-
	# tricted from getting positive mood bonuses, due to the mood bar being broken in half.
	if abs(mood_value) == 10:
		has_reset_mood = true
		await _handle_max_mood_reset_and_bonus()
	
	super.turn_end()
	
	if is_fully_charged():
		# Previous Hazel clearence gimmick
		#if has_curse(CURSE.CURSED):
		#	_set_for_late_cursed_transform()
			
		if mood_value != 0 and not has_reset_mood:
			_handle_no_use_mood_lowering()

func battle_started():
	super.battle_started()
	if not is_mood_bar_placed:
		await place_mood_bar_ui()
	mood_bar.play_mutually_exclusive_fade(true)

func battle_ended():
	mood_value = 0 # Resets mood value
	if is_mood_bar_placed:
		mood_bar.reset_pointers() # Resets mood value indication
	
	# Resets all values tied to mood bonuses
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

## Creates a temporary color filter overlay on the enemy sprite.
func _create_enemy_mood_filter_effect() -> void:
	var enemy_filter = enemy_color_filter.instantiate()
	enemy_filter.prepare_work_color(state)
	Game.enemy.add_child(enemy_filter)
	var sprites = _get_enemy_effect_target()
	for sprite in sprites:
		if sprite != null:
			enemy_filter.play_fade_on_enemy(sprite)

## Returns the proper node or nodes which displays the "real body" of an enemy.[br]
## Meant to make so things like Brutalist's ground plates or Nobody's table
## don't change color when the _create_enemy_mood_filter_effect() is called.
func _get_enemy_effect_target() -> Array[Node2D]:
	if special_enemy_sprites.list.keys().has(Game.main.enemy.id):
		var return_array:Array[Node2D] = []
		for sprite_path in special_enemy_sprites.list[Game.main.enemy.id]:
			return_array.append(Game.main.enemy.get_node(sprite_path))
		return return_array
	return [Game.main.enemy]

## Creates an IntentBounceAnimator node which bounces a specific node.[br]
## Meant to be called to indicate, though an animation on the multiplier intents, 
## that their value has changed.
func _request_intent_bounce_tween(target_node: Node2D, previous_mult: float, new_mult: float) -> void:
	var tween_node = IntentBounceAnimator.new(previous_mult,new_mult)
	Game.main.add_child(tween_node)
	tween_node.bounce_intent(target_node)



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
	mood_bar.set_normal_pointer_position(mood_value)
	await mood_bar.tree_entered
	if play_fade_in:
		mood_bar.play_mutually_exclusive_fade(true)

#==================================================================================
#                                   MOOD BONUS

## Lowers mood value, usually rounding up (exception made so the value can reach 0)[br]
## Reserved for a situation where the player didn't use the spell during a turn.
func _handle_no_use_mood_lowering() -> void:
	if abs(mood_value) != 1:
		mood_value = floor(mood_value/2.0)
	else:
		mood_value = 0
		
	await _force_mood_bar_turn_end_change(mood_value)

## Resets mood value and gives a bonus based on if enemy mood was positive or negative.[br]
## Reserved for situations where the player has reached one of the mood bar's extremes.
func _handle_max_mood_reset_and_bonus() -> void:
	# Reaches this part of the code already assuming mood_value is at the normal max (10 or -10)
	var crit_tile_type
	
	if mood_value > 0: # Positive/Happy Mood
		should_add_pos_mood_bonus = true
		crit_tile_type = TileType.DEFENSE
	else: # Negative/Segative Mood
		should_add_neg_mood_bonus = true
		crit_tile_type = TileType.DAMAGE
	mood_value = 0
	mood_bonus_resets_on_this_fight += 1
	
	await _force_mood_bar_turn_end_change(mood_value,true)
	
	var crit_ammount = ceil(float(mood_bonus_resets_on_this_fight)/3)
	crit_ammount = min(crit_ammount,3)
	await _summon_bonus_crit_tile(crit_tile_type,crit_ammount)
	
	await Game.timeout(0.42)

func _force_mood_bar_turn_end_change(new_mood_value: int, big_delay: bool = false) -> void:
	mood_bar.slide_pointer_to_new_position(new_mood_value)
	await Game.timeout(0.015 if big_delay else 0.007)
	AudioManager.play_sound(main_use_sound)
	await mood_bar.pointer_move_tween.finished
	
	await Game.timeout(0.5)
	mood_bar.play_mutually_exclusive_fade(false)
	await Game.timeout(0.3)

func get_bonus_reset_value(for_positive_bonus: bool) -> int:
	if for_positive_bonus:
		return pos_mood_revert_bonus + mood_bonus_resets_on_this_fight
	else:
		return neg_mood_revert_bonus + mood_bonus_resets_on_this_fight

func _create_mood_bonus_reset_filter(positive_mood: bool) -> void:
	# Reuses the same tweener as the one called in _create_enemy_mood_filter_effect()
	var enemy_filter = enemy_color_filter.instantiate()
	var matching_color = Color("89B831") if positive_mood else Color("EB4929")
	
	enemy_filter.prepare_finger_picked_color(matching_color)
	player.add_child(enemy_filter)
	enemy_filter.play_fade_on_enemy(player.sprite)

func _summon_bonus_crit_tile(target_type: TileType, amount: int = 1) -> void:
	var affect_tiles: Array[Tile] = []
	
	for x in range(amount):
		var tile_groups = tile_board.get_tile_groups({
			type_priority = target_type,
			exclude_tiles = affect_tiles
		})
		
		if tile_groups.is_empty():
			break
		
		var priority_group = tile_groups[0]
		affect_tiles.append(rng.spell.pick_random(priority_group))
	
	for tile in affect_tiles:
		tile.add_status(TileStatus.CRIT)
		tile.set_type(target_type)
		tile.add_poofcloud(tile.get_color())
		await Game.timeout(0.08)
	
	

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
	Game.main.player_action_started.disconnect(_on_turn_start)
	word_builder.finished_updating_stats.disconnect(_correct_intents_post_builder_update)
	tile_board.turn_ended.disconnect(early_turn_end)
	player_spell_slot.tooltip_collision.generate_tooltip.disconnect(_on_tooltip_generated)
	
	
	var spell = super.transform_spell(new_spell_id,keep_secret_id,keep_curse,keep_charge_amount,keep_charge_properties,keep_extra_max_charge,early_modifier)
	return spell



#==================================================================================
#                                 HAZEL CLEARANCE

func _hazel_tarnish_presented_word() -> void:
	var tiles: Array[Tile] = word_builder.tiles
	
	for tile: Tile in tiles:
		if not tile.has_harmful_status() and not tile.has_status(TileStatus.CRIT):
			tile.add_status(TileStatus.POOP)
			tile.add_poofcloud(tile.get_color())
			await Game.timeout(0.12)


# Parts of the first iteration of the hazel gimmick. Goes unused with the current tarnish gimmick
#func _handle_cursed_tiles_spawning(cursed_tile_ammount: int) -> void:
#	if not has_curse(CURSE.CURSED):
#		return
#	if cursed_tile_ammount < 1:
#		cursed_tile_ammount = 1
#	
#	var target_tiles = []
#	for x in range(cursed_tile_ammount):
#		var tiles = tile_board.get_tiles({
#			effect_priority = [Globals.TileStatus.CURSED],
#			exclude_final_effect_priority = true,
#			exclude_tiles = target_tiles
#		})
#		if tiles.is_empty():
#			break
#		
#		shake.emit()
#		var iteration_tile: Tile = rng.spell.pick_random(tiles)
#		target_tiles.append(iteration_tile)
#		iteration_tile.add_status(TileStatus.CURSED)
#		iteration_tile.add_poofcloud(iteration_tile.get_color())
#		await Game.timeout(0.12)
#
#func _get_late_cursed_tiles_ammount(specific_mood_value: int) -> int:
#	return abs(specific_mood_value - int(specific_mood_value/3))
#
#func _set_for_late_cursed_transform() -> void:
#	var saved_mood_value = mood_value
#	await Game.main.player_action_started
#	_handle_cursed_tiles_spawning(_get_late_cursed_tiles_ammount(saved_mood_value))


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

extends TileModifierSpell


var watering_tween

enum STATES {
	SEED,            # Seedling
	FLOWER_AMOUNT_0, # Growing
	FLOWER_AMOUNT_1, # Flowering
	FLOWER_AMOUNT_2, # Effloresced
	FLOWER_AMOUNT_3, # Complete
	DEAD             # Failed
}

const CHARGE_AMOUNTS: Dictionary = { 
	0: 1, # Seedling
	1: 2, # Growing
	2: 2, # Flowering
	3: 3, # Effloresced
	4: 3, # Complete
}

# Returns the value of TOTAL USAGE needed, not just between each stage
const usage_needed: Dictionary = { 
	0: 4,  # Seedling     to Growing
	1: 10,  # Growing      to Flowering
	2: 16, # Flowering    to Effloresced
	3: 23, # Effloresced  to Complete
}

const CHARGE_TYPES: Dictionary = { 
	0: "b", # Seedling
	1: "c", # Growing
	2: "c", # Flowering
	3: "c", # Effloresced
	4: "a", # Complete
	5: "a", # Failed
}

var state = STATES.SEED
var state_before_death = null # Used to prevent weird interactions when reloading run

# Points to how many times this spell was used in a run
# Done like this instead of with Game.main.run_stats.spell_usages because of 12 Gauge Clay
var num_usage = 0 
var has_to_evolve = false

const crit_rng_percent = 0.25
const extra_tile_rng_percent = 0.5

func get_hv_frames() -> Vector2i:
	return Vector2i(3,2)

func get_frame() -> int:
	return state

func switch_state(new_state: int, from_continue: bool = false):
	if new_state <= state:
		return
	_update_state_logic(new_state,from_continue)

func _update_state_logic(new_state: STATES, from_continue: bool = false) -> void:
	if player.get_using_spell() == self:
		player.cancel_selection()
	
	if new_state == STATES.DEAD:
		set_status_tooltips() # Calls it earlier to properly call tarnished
		if not from_continue:
			state_before_death = state
		AudioManager.play_sound(Sounds.XRAFSTAR.PARASITE_ATTACK,0.1)
	
	state = new_state 
	_change_charge_type_and_ammount(new_state,from_continue)
	
	set_status_tooltips()
	shake.emit()
	frame_updated.emit()
	description_updated.emit()

func get_save_data():
	var save = super.get_save_data()
	save["state"] = state
	save["state_before_death"] = state_before_death
	save["num_usage"] = num_usage
	return save

func load_save_data(save):
	super.load_save_data(save)
	state = save.state
	state_before_death = save.state_before_death
	num_usage = save.num_usage
	switch_state(state,true)
	set_status_tooltips()

func get_tooltip_context():
	return {state = state}

func set_status_tooltips():
	if state != STATES.SEED:
		status_tooltips = [get_application_status()]
	
	if state == STATES.DEAD:
		status_tooltips.append(Automaton.STRINGS.CACTUS_FAILED_STRING_GROUP)
	elif state > STATES.FLOWER_AMOUNT_1:
		status_tooltips.append(TileStatus.CRIT)

func _use():
	if state == STATES.SEED:
		await _do_watering_effects()
		_post_use()
		return
	
	# For all other states:
	super._use()


func apply_to_tile(_tile: Tile, _real_tile: Tile, _is_preview: bool, _is_preview_update: bool) -> void:
	var extra_tile: Tile = null
	
	if not _is_preview and state != STATES.DEAD and state > STATES.FLOWER_AMOUNT_0: # Flowering, Effloresced or Complete
		var possible_extra_tiles = tile_board.get_tile_groups({
				exclude_tiles = [_tile],
				effect_priority = [Globals.TileStatus.DEFAULT,Globals.TileStatus.ENHANCED],
				exclude_final_effect_priority = true
		})
		if not possible_extra_tiles.is_empty():
			if _roll_for_extra_tile():
				extra_tile = rng.spell.pick_random(possible_extra_tiles[0])
	
	var can_roll_crit = not _is_preview and state != STATES.DEAD and state > STATES.FLOWER_AMOUNT_1 # Effloresced or Complete
	
	_target_tile_for_conversion(_tile,can_roll_crit,_is_preview)
	if extra_tile != null: # No extra conditional needs to be run as extra tile is always null on preview
		await Game.timeout(0.18)
		_target_tile_for_conversion(extra_tile,can_roll_crit,_is_preview,true)

func _target_tile_for_conversion(tile : Tile, can_roll_crit : bool, is_preview: bool, is_extra_tile : bool = false) -> void:
	var status_to_apply = get_application_status()
	if can_roll_crit:
		if _roll_for_crit_conversion():
			status_to_apply = Globals.TileStatus.CRIT
			if is_extra_tile:
				# Crit sound doesn't play for the extra tile. Manually fixest that
				AudioManager.play_sound(Sounds.TILE.CRIT)
	tile.add_status(status_to_apply)
	if not is_preview:
		tile.add_poofcloud(tile.get_color())

func _roll_for_crit_conversion() -> bool:
	return _do_rng_roll(crit_rng_percent)

func _roll_for_extra_tile() -> bool:
	return _do_rng_roll(extra_tile_rng_percent)

func _do_rng_roll(crit_chance:float) -> bool:
	var rng_roll = rng.spell.randf()
	if rng_roll < crit_chance:
		return true
	return false

func _post_use(use_charge = true, is_rerolling = false, trigger_use_completed: bool = true):
	if trigger_use_completed:
		num_usage += 1
		_trigger_use_completed()
		await _set_state_based_on_usage()
	super._post_use(use_charge,is_rerolling,false)
	_check_evolution()

func is_tile_selectable(_tile: Tile) -> bool:
	if state == STATES.FLOWER_AMOUNT_3:
		return true
	elif state == STATES.DEAD:
		return not _tile.has_status(get_application_status())
	elif state == STATES.FLOWER_AMOUNT_0:
		return (
			not _tile.has_status(get_application_status()) and
			not _tile.has_harmful_status() and
			_tile.is_type(TileType.DAMAGE)
		)
	else:
		return not _tile.has_status(get_application_status()) and not _tile.has_harmful_status()

func get_application_status() -> String:
	return Globals.TileStatus.ENHANCED if state != STATES.DEAD else Globals.TileStatus.POOP

func _set_state_based_on_usage() -> void:
	if state == STATES.FLOWER_AMOUNT_3 or state == STATES.DEAD:
		return
	
	var goal = usage_needed.get(state,-1)
	
	if num_usage >= goal and goal != -1:
		has_to_evolve = true # Makes so it sets it's state to state +1 later down the line
		await _do_pre_evolution_startup()

func is_about_to_evolve() -> bool:
	return num_usage == usage_needed.get(state,-1) -1

func _change_charge_type_and_ammount(state_to_look, from_continue: bool) -> void:
	var is_dead = state_to_look == STATES.DEAD
	
	if is_dead:
		state_to_look = state_before_death
	
	if state_to_look == null:
		return
	
	if not is_dead:
		var new_amount = CHARGE_AMOUNTS[state_to_look]
		var to_add = new_amount - max_charge
		add_max_charge(to_add)
		if not from_continue:
			add_charge(max_charge, true, true)
	
	var new_charge_type = CHARGE_TYPES[state] # Using state instead of state_to_look to override charge to be A if dead
	if new_charge_type != charge_character:
		charge_character = new_charge_type
		charge_container.update_charge_character()

func battle_started():
	super.battle_started()
	if Game.main.is_battle and Game.enemy is NobodyBoss and state != STATES.FLOWER_AMOUNT_3 and state != STATES.DEAD:
		await Game.main.player_action_started
		switch_state(STATES.DEAD)

func _check_evolution() -> void:
	if has_to_evolve and state < STATES.FLOWER_AMOUNT_3:
		has_to_evolve = false
		switch_state(state + 1)
		_do_evolution_effects()

# ======================================================================
#                        VISUAL + AUDIO EFFECTS

func _do_evolution_effects() -> void:
	if state == STATES.DEAD:
		return
	player_spell_slot.spell_sprite.anim_player.play("charge")
	_play_evolution_sounds()

func _do_pre_evolution_startup() -> void:
	await Game.timeout(0.4) # initial delay
	
	var original_sprite_pos = player_spell_slot.spell_sprite.position
	var sound_duration = 1.4
	var sound_playback = AudioManager.play_sound(Sounds.URCHIN.SHIELD_LOOP.SOUND,2.0,0.0)
	var raise_volume_tween = player_spell_slot.create_tween()
	raise_volume_tween.tween_method(
		sound_playback._fade_tween_callback.bind(sound_playback.audio_player.get_stream_playback()),
		0.0,
		2.0,
		sound_duration
	)
	
	var shake_tween = player_spell_slot.create_tween().set_parallel(false)
	shake_tween.tween_method(_shake_offset.bind(original_sprite_pos),0.0,2.0,sound_duration/2)
	shake_tween.tween_method(_shake_offset.bind(original_sprite_pos),2.0,0.7,sound_duration/2)
	
	await raise_volume_tween.finished
	sound_playback.stop()
	player_spell_slot.spell_sprite.position = original_sprite_pos
	player_spell_slot.spell_sprite.anim_player.play("charge",-1,2.0)

func _play_evolution_sounds() -> void:
	var audio_repeat_ammount = 5
	var audio_initial_delay = 0.05
	var audio_initial_pitch = 0.5
	
	for x in range(audio_repeat_ammount):
		AudioManager.play_sound(
			Sounds.TILE.CRIT,
			max(0.1,audio_initial_pitch + (x * 0.1)),
			float(audio_repeat_ammount)/max(x-1,2)
		)
		await Game.timeout(audio_initial_delay + (x * 0.08))

# Edited version of a function from mood_bar_core.gd
func _shake_offset(seconds_since_tween_start:float,original_pos: Vector2) -> void:
	player_spell_slot.spell_sprite.position = Vector2(
		original_pos.x + (randf_range(-2,2) * seconds_since_tween_start),
		original_pos.y + (randf_range(-2,2) * seconds_since_tween_start)
	)

func _do_watering_effects() -> void:
	AudioManager.play_sound(Sounds.LIQUID_HUMAN.DO_NOTHING,1.5)
	
	var old_modulate = player_spell_slot.spell_sprite.modulate
	var watering_color = Color(0.0,0.5,1.0)
	player_spell_slot.spell_sprite.modulate = watering_color
	if watering_tween:
		watering_tween.kill()
	
	watering_tween = player_spell_slot.create_tween()
	watering_tween.tween_property(player_spell_slot.spell_sprite,"modulate",old_modulate,0.5)
	if is_about_to_evolve():
		await watering_tween.finished

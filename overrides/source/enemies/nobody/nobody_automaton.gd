extends NobodyBoss

# Quick access to a global list which presents the same names as the act() methods
const mood_intent_list = Automaton.STRINGS.INTENT_STRING_GROUP_ITEMS
var automaton_char_spell = Game.player.spell_container.get_spells()[0]
var cursed_target = load("res://mods/automaton_character/source/effects/curse_target.tscn")
# Used by all moves to change values when the player uses important notes
var mood_mofifier = 0
var player_used_wrong_category = false

var waiting_parry_intent_update_delay = false

signal started_moodbar_cutscene
signal reached_shatter_moodbar_moment
signal redrawing_cursed_targets_effect

func _init():
	super._init()

	launch_from_scene_character = Globals.CHARACTERS.LEXICOGRAPHER
	next_move = "instinct"

	moves = {
		instinct = {
			damage = {
				0: 1, 
				2: 2, 
				3: 3
			}, 
			count = {
				0: 4, 
				1: 7,
				3: 10
			}, 
			next = "attachment"
		},
		attachment = {
			ash = {
				0: 10, 
				2: 16,
				3: 20,
			},
			next = "insight"
		},
		insight = {
			target_column = {
				0: 2,
				2: 0,
			},
			next = "repression"
		},
		repression = {
			damage = {
				0: 7, 
				2: 10, 
				3: 20
			}, 
			parry = {
				0: 12,
				1: 14, 
				2: 18, 
				3: 24
			},
			next = "instinct"
		},
	}

func _get_health_scaling():
	return [60, 70, 80, 90] # Same as Child/Fisher/Addict

func get_save_data():
	var save = super.get_save_data()
	save.mood_mofifier = mood_mofifier
	save.player_used_wrong_category = player_used_wrong_category
	return save

func load_save_data(save):
	super.load_save_data(save)
	mood_mofifier = save.mood_mofifier
	player_used_wrong_category = save.player_used_wrong_category
	
	automaton_char_spell = Game.player.spell_container.get_spells()[0]
	_alert_and_connect_important_notes_spell(automaton_char_spell,true)

func _alert_and_connect_important_notes_spell(spell_node: Spell, from_continue_run: bool) -> void:
	if not spell_node.has_method("make_nobody_changes") or not spell_node.has_signal("presented_categorized_word"):
		push_error("Character item is not Important Notes. Something was loaded incorrectly.")
		return
	spell_node.make_nobody_changes(from_continue_run)
	spell_node.presented_categorized_word.connect(_on_important_notes_use)


func display_intent() -> void :
	var mood_intent_root = Automaton.STRINGS.INTENT_STRING_GROUP
	var context = get_next_move_context()
	
	match next_move:
		mood_intent_list.NOBODY_INSTINCT:
			add_intent(Intent.ATTACK, {damage = context.damage, count = context.count})
		mood_intent_list.NOBODY_INSIGHT:
			add_intent(
				Intent.APPLY_STATUS,
				{
					status = TileStatus.CURSED,
					count = tile_board.num_rows if not player_used_wrong_category else tile_board.num_columns,
					name_override = "automaton_cursed_column",
					description_override = "automaton_cursed_column",
				}
			)
		mood_intent_list.NOBODY_ATTACHMENT:
			add_intent(Intent.APPLY_STATUS, {status = TileStatus.ASH, count = context.ash})
			add_intent(Intent.EXPAND_BOARD, {size_x = 6, size_y = 4})
		mood_intent_list.NOBODY_REPRESSION:
			add_intent(Intent.ATTACK, {damage = context.damage})
			add_parry_intent()
			add_intent(Intent.EXPAND_BOARD, {size_x = 4, size_y = 4})
	add_intent("_".join([mood_intent_root,next_move]))


func add_parry_intent():
	var words: WordList = word_builder.get_words()
	var parry = get_true_parry()
	
	if main.is_player_turn and words.maximum_length > 0:
		var needed_parry = get_needed_parry()
		if needed_parry == 0:
			add_intent(Intent.PARRY, {length = parry, parried = true})
		else:
			add_intent(Intent.PARRY, {length = parry, needed_length = needed_parry})
		
	else:
		add_intent(Intent.PARRY, {length = parry})

func get_needed_parry():
	var words: WordList = word_builder.get_words()
	return max(get_true_parry() - words.maximum_length, 0)

func get_true_parry():
	return max(moves[next_move].parry - mood_mofifier,0)



func instinct() -> void:
	await animate_attack()
	
	var context = get_next_move_context()
	var delay = 0.33 if context.count < 6 else 0.25
	
	for i in range(context.count):
		hit_player(context.damage, i == context.count - 1)
		if i != context.count - 1:
			await Game.timeout(delay)
	
	await wait_for_idle()

func insight() -> void:
	reset_curse_target_indicators()
	await animate_attack()
	
	var target_tiles = get_insight_target_tiles()
	for tile in target_tiles:
		tile.randomize_if_faceless(rng.move)
		tile.add_status(TileStatus.CURSED)
		tile.add_poofcloud(tile.get_color())
		
		var interval = 0.06
		await Game.timeout(interval)
	
	
	await wait_for_idle()
	run_waiting_parry_intent_update_delay() 

func attachment() -> void:
	await tile_board.set_size(6, 4)
	
	await animate_attack()
	
	var context = get_next_move_context()
	
	var target_tiles = get_tiles({
		amount = context.ash, 
		effect_priority = EFFECT_PRIORITY.STATUS_ONLY, 
	})
	
	var delay = 0.08 if context.ash < 10 else 0.06
	
	for tile: Tile in target_tiles:
		tile.add_status(TileStatus.ASH)
		tile.add_poofcloud(tile.get_color())
		await Game.timeout(delay)
	
	await wait_for_idle()

func repression() -> void:
	if is_parried:
		await tile_board.set_size(4, 4)
		await wait_for_idle()
		return
	
	await animate_attack()
	
	var context = get_next_move_context()
	hit_player(context.damage, true)
	
	await tile_board.set_size(4, 4)
	
	await wait_for_idle()


func unique_end_player_action() -> void :
	if next_move == "repression":
		dooming_columns = [4, 5, 6]

func _on_important_notes_use(word_category: int, word_size:int) -> void:
	var matching_pos_array = [
		mood_intent_list.NOBODY_INSTINCT,
		mood_intent_list.NOBODY_INSIGHT,
		mood_intent_list.NOBODY_ATTACHMENT,
		mood_intent_list.NOBODY_REPRESSION
	]
	var is_matching_mood = matching_pos_array[word_category] == next_move
	if not is_matching_mood:
		player_used_wrong_category = true
	
	var to_bounce_intent = {
		mood_intent_list.NOBODY_INSTINCT: Intent.ATTACK,
		mood_intent_list.NOBODY_INSIGHT: Intent.APPLY_STATUS,
		mood_intent_list.NOBODY_ATTACHMENT: Intent.APPLY_STATUS
	}
	
	match next_move:
		mood_intent_list.NOBODY_INSTINCT, mood_intent_list.NOBODY_INSIGHT:
			if is_matching_mood:
				if mood_mofifier < 0:
					mood_mofifier = 0
				mood_mofifier += word_size
			_request_intent_bounce_tween(to_bounce_intent[next_move],true)
			if next_move == mood_intent_list.NOBODY_INSIGHT:
				indicate_cursed_targets()
		
		mood_intent_list.NOBODY_ATTACHMENT:
			var num_signal = -1 if is_matching_mood else +2
			mood_mofifier = mood_mofifier + (word_size*num_signal)
			_request_intent_bounce_tween(to_bounce_intent[next_move],is_matching_mood)
		
		mood_intent_list.NOBODY_REPRESSION:
			var num_signal = 1 if is_matching_mood else -1
			mood_mofifier = max(mood_mofifier + (word_size*num_signal),0)
			_request_intent_bounce_tween(Intent.ATTACK, not is_matching_mood)
			_request_intent_bounce_tween(Intent.PARRY, is_matching_mood)
	
	update_intents()

func _request_intent_bounce_tween(intent_type: Intent, intent_expand_outwards: bool) -> void:
	var intent_node = null # intent.gd
	for existing_intent in intent_container.intent_instances:
		if existing_intent.get_key() == Intent.keys()[intent_type].to_lower():
			intent_node = existing_intent
			break
	
	automaton_char_spell._request_intent_bounce_tween(
		intent_node,
		0.0 if intent_expand_outwards else 1.0,
		1.0 if intent_expand_outwards else 0.0
	)

func get_next_move_context() -> Dictionary:
	match next_move:
		mood_intent_list.NOBODY_INSTINCT:
			return _get_instinct_values()
		mood_intent_list.NOBODY_INSIGHT:
			return _get_insight_values()
		mood_intent_list.NOBODY_ATTACHMENT:
			return _get_attachment_values()
		mood_intent_list.NOBODY_REPRESSION:
			return _get_repression_values()
	return {}

func _get_instinct_values() -> Dictionary:
	var sum_count = moves.instinct.count + mood_mofifier
	var true_damage = moves.instinct.damage if not player_used_wrong_category else sum_count
	var true_count  = sum_count if not player_used_wrong_category else moves.instinct.damage
	return {damage = true_damage, count = true_count}

func _get_insight_values() -> Dictionary:
	var target_column = wrap(
		moves.insight.target_column + mood_mofifier,
		0,
		tile_board.num_columns
	)
	return {target_column = target_column}

func _get_attachment_values() -> Dictionary:
	var ash = max(moves.attachment.ash + mood_mofifier,0)
	return {ash = ash}

func _get_repression_values() -> Dictionary:
	return {damage = moves.repression.damage + mood_mofifier}

func wait_for_idle():
	reset_internal_mood_for_next_move()
	await super.wait_for_idle()

func reset_internal_mood_for_next_move() -> void:
	mood_mofifier = 0
	player_used_wrong_category = false

func animate_flinch(_damage):
	if word_builder.is_submitting:
		if last_words_submitted != null and last_words_submitted.words.size() > 0:
			play_morse(last_words_submitted.words)

	last_words_submitted = null

	sprite.particle_reset_velocity()

	var current_anim: = anim_player.assigned_animation
	var flinch_anim: = "flinch_" + current_anim

	if is_parried and _is_playing_parriable_animation():
		flinch_anim = "die_fake"

	if flinch_anim in anim_player.get_animation_list():
		anim_player.play(flinch_anim)
	else:
		anim_player.play("flinch_idle")

	if flinch_anim == "die_fake" and is_parried:
		anim_player.queue("approach")
	anim_player.queue(current_anim)
	
	if flinch_anim == "die_fake" and is_parried:
		await pend_animation_played("approach")
	await pend_animation_played(current_anim)

func flinch_lethal(amount: int):
	Automaton.handle_custom_achievemnts_on_run_clear(Game.difficulty)
	super.flinch_lethal(amount)

func _is_playing_parriable_animation() -> bool:
	if anim_player.assigned_animation != "flinch_time_to_lean_loop":
		return false
	return true

func _on_sprite_event(event: String) -> void :
	if event == "hide_health":
		if anim_player.assigned_animation == "die_fake":
			return
		health_bar.disappear()

func _on_finished_updating_stats(_words):
	if "parry" in moves[next_move]:
		if main.is_player_turn and not waiting_parry_intent_update_delay:
			update_intents()

func update_intents():
	intent_container.reset_intents()
	display_intent()
	intent_container.update_intents()

# Manual override meant to avoid weird interactions with the parry intent
func run_waiting_parry_intent_update_delay() -> void:
	waiting_parry_intent_update_delay = true
	await Game.main.player_action_started
	waiting_parry_intent_update_delay = false

func _on_word_submitted(words: WordList, _damage: int, _ending_turn: bool) -> void:
	super._on_word_submitted(words,_damage,_ending_turn)
	# Recalculates is_paried accounting for item usage:
	if "parry" in moves[next_move]:
		is_parried = words.maximum_length >= get_true_parry()

func prepare_next_turn():
	super.prepare_next_turn()
	if next_move == "insight":
		indicate_cursed_targets()

# Modified version of a code from greeb.gd
func indicate_cursed_targets() -> void:
	reset_curse_target_indicators()
	for coord in get_insight_target_coords():
		var new_target = cursed_target.instantiate()
		#new_target.tie_to_nobody_signal(self)
		tile_board.set_coord_status(coord, new_target)

func get_insight_target_tiles() -> Array[Tile]:
	return get_tiles(_get_insight_call_paremeters())

func get_insight_target_coords() -> Array[Vector2i]:
	return get_coords(_get_insight_call_paremeters())

func _get_insight_call_paremeters() -> Dictionary:
	var parameters
	if player_used_wrong_category:
		parameters = {
			amount = tile_board.num_columns, 
			sorted = true,
			rows = [-1], 
		}
	else:
		var context = get_next_move_context()
		parameters ={
			amount = tile_board.num_rows,
			sorted = true,
			columns = [context.target_column], 
		}
	return parameters

func reset_curse_target_indicators() -> void:
	var targets = tile_board.get_targeted_coords()
	for target in targets:
		var coord = tile_board.get_status_coord(target)
		tile_board.set_coord_status(coord, null)
		target.clear()

# =======================================================================================
#                                  CUTSCENE OVERRIDES

func custom_battle_transition(_skipping: bool = false) -> void :
	await main.play_versus_text()
	anim_player.play_advance("approach")
	anim_player.queue("idle")
	await anim_player.pend_animation_stopped("approach")
	var cutscene: = pick_cutscene()
	if cutscene != "":
		await play_cutscene(cutscene)
	await _play_special_moodbar_cutscene()
	tile_board.stay_off_screen = false
	tile_board.prevent_filling = false
	tile_board.reset_board()
	super.play_battle_music(true)
	await tile_board.slide_in()
	await tile_board.fill_board()
	main.show_health()

func _play_special_moodbar_cutscene() -> void:
	# Assimuing this is being loaded while playing as Automaton, first spell should
	# have an easy access to the moodbar pointer
	automaton_char_spell = Game.player.spell_container.get_spells()[0]
	# Makes use of the fact this is already calling the spell node to run
	# a flag change relevant to the nobody fight
	_alert_and_connect_important_notes_spell(automaton_char_spell,false)
	
	
	if not automaton_char_spell.is_mood_bar_placed:
		automaton_char_spell.place_mood_bar_ui()
	var moodbar_node: AutomatonMoodBar = automaton_char_spell.mood_bar
	moodbar_node.play_mutually_exclusive_fade(true)
	var audio_dict = {
		"SOUND": Sounds.BOTTOM_FEEDER.SUCK.SOUND,
		"PLAY_FROM": 0.60
	}
	
	
	await get_tree().create_timer(0.8).timeout
	var fake_smoke_player = AudioManager.play_sound(audio_dict,0.3,0.4)
	

	anim_player.play_advance("smoke_break")
	anim_player.queue("smoke_break_idle")
	
	await anim_player.pend_animation_stopped("smoke_break")
	moodbar_node.animate_apperance_to_nobody_state(false,self)
	await sprite.pend_flag("can_end", true)
	await sprite.event_emitted # Waiting for breath_smoke
	fake_smoke_player.fade_out(0.2)
	reached_shatter_moodbar_moment.emit()
	await get_tree().create_timer(1.5).timeout
	
	anim_player.play("smoke_break_end")
	# Next bit of code taken from nobody.gd > animate_attack()
	await sprite.hit 
	var parent_node: = get_tree().get_first_node_in_group("nobody_office_chunk")
	var projectile: ArcingProjectile = cigarette_butt_scene.instantiate()
	projectile.angular_velocity = PI * 10
	projectile.angular_deceleration = PI * 18
	projectile.decelerate_to = PI * 2
	projectile.rotation = randf_range(0.0, TAU)
	parent_node.add_child(projectile)
	var dest: = Util.random_point_in_collision_object(sprite.cigarette_target, Game.random)
	projectile.launch(sprite.cigarette_marker.global_position, dest, 80)
	await anim_player.pend_animation_stopped("smoke_break_end")
	await get_tree().create_timer(0.3).timeout
	anim_player.play_advance("smoke_break")
	anim_player.queue("smoke_break_idle")

# Following functions are taken from other scripts
# set_speech_bubble_sprite() and reset_speech_bubble() are minimally
# modified versions of the code contained in custom_nobody.gd from Xanderath/Emarald64's framework.
# advance_cutscene is a mixture between Xander's previous additions to it and nobody.gd
# vanilla iteration in 1.2.10

func reset_speech_bubble():
	for path in [^"%Bubble",^"%Tail"]:
		var bubble_sprite:Sprite2D=active_speech_bubble.get_node(path)
		bubble_sprite.hframes=4
		bubble_sprite.vframes=2
	
	var label:RichTextLabel=active_speech_bubble.get_node("%RichTextLabel")
	label.remove_theme_color_override("default_color")

func set_speech_bubble_sprite():
	var bubble:Sprite2D=active_speech_bubble.get_node("%Bubble")
	bubble.hframes=1
	bubble.vframes=1
	bubble.texture=load(Automaton.STRINGS.SPEECH_BUBBLE_FILEPATHS.MAIN)
	
	var tail:Sprite2D=active_speech_bubble.get_node("%Tail")
	tail.hframes=1
	tail.vframes=1
	tail.texture=load(Automaton.STRINGS.SPEECH_BUBBLE_FILEPATHS.TAIL)
	
	# Added this bit to set a color override to the label:
	var label:RichTextLabel=active_speech_bubble.get_node("%RichTextLabel")
	label.add_theme_color_override("default_color", Automaton.MISC.SPEECH_BUBBLE_TEXT_COLOR)

func advance_cutscene(instant: = false) -> void :
	active_cutscene_index += 1
	var str_index: = str(active_cutscene_index)
	if not active_cutscene.has_string_at_path([str_index]):
		await finish_cutscene()
		return

	var line_flags: = PackedStringArray()
	if active_cutscene.has_string_group(str_index):
		if active_cutscene.has_string_at_path([str_index, "flags"]):
			line_flags = active_cutscene.get_string_at_path([str_index, "flags"]).split(" ")

	if "character" in line_flags:
		next_bubble_nobody = false
	elif "nobody" in line_flags:
		next_bubble_nobody = true

	var should_play_line: = true
	var bubble_delay: float = 0.0
	for flag in line_flags:
		if flag.begins_with("spell_"):
			var spell_id: = flag.trim_prefix("spell_")
			should_play_line = player.has_spell_id(spell_id)

		if flag == "pro_piracy" and not Game.is_steam_inactive():
			should_play_line = false

		if flag == "pre_trans" and player.is_trans():
			should_play_line = false
		elif flag == "post_trans" and not player.is_trans():
			should_play_line = false

		if flag.begins_with("delay_"):
			var delay_string: = flag.trim_prefix("delay_")
			if delay_string.is_valid_float():
				bubble_delay = delay_string.to_float()

	if not should_play_line:
		await advance_cutscene(instant)
		return

	var new_bubble: = true
	if active_speech_bubble != null and is_instance_valid(active_speech_bubble):
		if bubble_delay <= 0.0 and next_bubble_nobody == previous_bubble_nobody:
			new_bubble = false
		else:
			await disappear_speech_bubble(instant)

	if bubble_delay > 0.0:
		cutscene_delay_active = true
		await Game.timeout(bubble_delay)
		cutscene_delay_active = false

	if new_bubble:
		if next_bubble_nobody:
			active_speech_bubble = sprite.spawn_speech_bubble()
			reset_speech_bubble()
		else:
			active_speech_bubble = player.sprite.spawn_speech_bubble()
			set_speech_bubble_sprite()

		if next_bubble_nobody:
			await active_speech_bubble.appear(&"appear_nobody")
		else:
			var frame: = Globals.CHARACTER_ORDER.find(player.id) + 2
			await active_speech_bubble.appear(&"appear_character", frame)

	previous_bubble_nobody = next_bubble_nobody
	next_bubble_nobody = not next_bubble_nobody

	var delay: float = 0.02
	if "fast" in line_flags:
		delay = 0.01

	var cutscene_string: = active_cutscene.get_string_at_path([str_index], {trans = player.is_trans()})
	var cutscene_control_string: = active_cutscene.get_string_at_path([str_index], {control = true, trans = player.is_trans()})
	active_speech_bubble.type_text(cutscene_string, cutscene_control_string, "cutoff" not in line_flags, delay)

	if "cutoff" in line_flags:
		active_speech_bubble.text_playback.finished.connect(advance_cutscene.bind(true), ConnectFlags.CONNECT_ONE_SHOT)

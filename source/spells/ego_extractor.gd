extends TileModifierSpell

var e = Enemies #made shorter to improve some match extressions in readibility
var modded_enemies_data = {}
var current_name_letter: String = ""
var current_name_index: int = 0
var current_rng_target_indexes: Array[int] = []

var final_use_effect_counter = 0
var final_use_effect_method_name = ""

func _ready() -> void:
	modded_enemies_data = Automaton.get_ego_extractor_compatibility()

func _reset_current_values() -> void:
	current_name_letter = ""
	current_name_index = 0
	current_rng_target_indexes = []
	final_use_effect_counter = 0
	final_use_effect_method_name = ""


func has_special_tile_tooltip() -> bool:
	return true

func get_tooltip_context():
	if current_name_letter == " ":
		return {face = current_name_letter, hole = true}
	return {face = current_name_letter, hole = false}

func update_banner_label():
	super.update_banner_label()
	main.spell_banner.label.set_fit_content(false)
	# Very weird fix for a rendering issue: Banner text would float up sometimes
	await player_spell_slot.get_tree().process_frame
	main.spell_banner.label.set_fit_content(true)

func _use():
	_reset_current_values()
	var proper_name : String = get_proper_name_value(get_enemy_name(),Game.enemy.id)
	if proper_name.length() > tile_board.get_tiles().size():
		proper_name = proper_name.substr(0,tile_board.get_tiles().size())
	
	
	var selected_tiles: Array[Tile] = []
	
	for selection in range(proper_name.length()):
		current_name_letter = proper_name[selection]
		current_name_index = selection
		
		update_banner_label()
		var tile = await get_selection(selected_tiles)
		
		if tile == null:
			_end_use()
			return
		selected_tiles.append(tile)
		tile.animation.play("pressed")
	
	var unique_interactions = get_unique_interactions_dict(Game.enemy.id)
	
	var rng_target_tiles: Array[int] = []
	var rng_needed_ammount = 0
	if unique_interactions.keys().has("rng_tile_percent"):
		var safe_to_use_float = clamp(unique_interactions.rng_tile_percent,0.0,1.0)
		rng_needed_ammount = int(floor(proper_name.length() * safe_to_use_float))
	elif unique_interactions.keys().has("rng_tile_amount"):
		rng_needed_ammount = unique_interactions.rng_tile_amount
	while rng_target_tiles.size() < rng_needed_ammount:
		var index = rng.spell.randi_range(0,proper_name.length()-1)
		if not (index in rng_target_tiles):
			rng_target_tiles.append(index)
	
	current_rng_target_indexes = rng_target_tiles
	
	
	for name_letter_index in range(proper_name.length()):
		current_name_letter = proper_name[name_letter_index]
		current_name_index = name_letter_index
		apply_to_tile(selected_tiles[name_letter_index], selected_tiles[name_letter_index], false, false)
		await Game.timeout(0.08)
	
	if final_use_effect_method_name != "":
		call(final_use_effect_method_name)
	
	if player.is_using_spell():
		_post_use()


func get_enemy_name() -> String:
	if Game.enemy.id == Enemies.DECLAWED:
		if Game.enemy.new_name != "":
			return Game.enemy.new_name
	return Game.enemy.get_unit_name()

# Usually returns the first word in the name, as shown with the item description
func get_proper_name_value(full_name:String,enemy_id:String) -> String:
	if enemy_id in modded_enemies_data.keys():
		var possible_override = get_unique_interactions_dict(enemy_id).get("name_override")
		if possible_override != null:
			return possible_override.to_lower()
	
	full_name = full_name.to_lower()
	match enemy_id:
		Enemies.ANTI_SEX_WORKER:
			full_name = full_name.remove_chars("-")
		Enemies.PROTO_COP:
			full_name = full_name.replace("-"," ")
			return full_name
		Enemies.NEW_COP:
			return full_name
	return full_name if not full_name.contains(" ") else full_name.substr(0,full_name.find(" "))

func get_unique_interactions_dict(enemy_id:String) -> Dictionary:
	var return_dict = { 
		#"status" = TileStatus.DEFAULT,
		#"special" = func(),
		#"special_args" = {},
		#"rng_status" TileStatus.DEFAULT,
		#"rng_face_value" = "",
		#"rng_tile_amount" = 1
		#"rng_tile_percent" = 0.5
		"special_triggers_on_rng" = false,
		#"tile_overlay_anim" = "none"
		"can_full_run_on_preview" = true
		}
	
	if enemy_id in Enemies.list(true):
		return_dict.merge(_unique_static_interactions(enemy_id),true)
		return_dict.merge(_unique_rng_interactions(enemy_id),true)
	if enemy_id in modded_enemies_data.keys():
		return_dict.merge(modded_enemies_data[enemy_id],true)
	
	if return_dict.keys().has("rng_tile_amount") or return_dict.keys().has("rng_tile_percent"):
		return_dict.can_full_run_on_preview = false # Hard set to not mess with RNG
	
	return return_dict

func get_modded_enemy_data_list() -> void:
	pass

func apply_to_tile(_tile: Tile, _real_tile: Tile, _is_preview: bool, _is_preview_update: bool) -> void:
	var values = get_apply_values()
	var face_to_set = null
	var status_to_set = values.interactions.get("status",TileStatus.DEFAULT)
		
	if current_rng_target_indexes.has(current_name_index):
		if (not _is_preview) or values.interactions.can_full_run_on_preview:
			face_to_set = values.interactions.get("rng_face_value")
			status_to_set = values.interactions.get("rng_status",status_to_set)
		
	if face_to_set is String:
		_tile.set_face(face_to_set)
	else: # No special face was given to it
		_tile.set_face(values.enemy_name[current_name_index])
		
	if (
		status_to_set != TileStatus.DEFAULT and (
			not _tile.has_status(TileStatus.CRIT) or
			EffectRegistry.get_data(status_to_set).harmful
			)
		):
			_tile.add_status(status_to_set)
		
	if can_run_special_interaction(current_name_index, values.interactions, current_rng_target_indexes, _is_preview):
		var method_to_call : Callable = values.interactions.special
		if method_to_call.get_argument_count() == 3 and values.interactions.keys().has("special_args"):
			method_to_call.call(_tile,_is_preview,values.interactions.special_args)
		elif method_to_call.get_argument_count() == 2:
			method_to_call.call(_tile,_is_preview)
		elif method_to_call.get_argument_count() == 1:
			method_to_call.call(_tile)
	
	
	if values.enemy_name[current_name_index] == " ":
		_tile.apply_hole(false)
		if not _is_preview:
			AudioManager.play_sound(Sounds.SPELLS.GUNSHOT)
			Game.screenshake(8, 0.32)
	
	if _is_preview:
		return
	
	if values.interactions.keys().has("tile_overlay_anim"):
		_tile.tile_overlay_anim_player.play(values.interactions.tile_overlay_anim)
	_tile.add_poofcloud(_tile.get_color())
	_tile.animation.play("shake")
	AudioManager.play_sound(Sounds.TILE.GUNK,randf_range(0.2,0.6))
	AudioManager.play_sound(Sounds.UI.SLIDER)

func get_apply_values() -> Dictionary:
	return {
		"enemy_name" = get_proper_name_value(get_enemy_name(),Game.enemy.id),
		"interactions" = get_unique_interactions_dict(Game.enemy.id)
	}

func _unique_static_interactions(enemy_id:String) -> Dictionary:
	var return_dict = {}
	match enemy_id:
		
		e.FAT_CAT,e.ANTI_SEX_WORKER,e.SEX_TRAITOR,e.LIQUID_HUMAN,e.RUBBER_ANIMAL,e.PINK_RUBBER_ANIMAL:
			return_dict["status"] = TileStatus.BLEED
		e.PROTO_COP:
			return_dict["status"] = TileStatus.BLEED
			return_dict["tile_overlay_anim"] = "oxidize_bleed"
		e.NOPPY, e.SOPPY, e.SNOWBALL:
			return_dict["status"] = TileStatus.ASH
		e.PEOPLE, e.DECEDENT:
			return_dict["status"] = TileStatus.POISON
		e.PURRGEOISIE, e.HERARRA, e.JUVENILE, e.NEW_COP, e.SHERIFF:
			return_dict["status"] = TileStatus.BRUISE
		e.FREEZER:
			return_dict["status"] = TileStatus.FROZEN
		e.DEW_JUBILIST, e.DEW_JUBAJALIST:
			return_dict["status"] = TileStatus.ACID
		e.PSEUD:
			return_dict["status"] = TileStatus.POOP
		e.MILKWORM:
			return_dict["status"] = TileStatus.GUNK
		
		e.XRAFSTAR:
			if Game.enemy.next_move == "pollute":
				return_dict["status"] = TileStatus.POISON
			else:
				return_dict["status"] = TileStatus.POOP
		e.SOCIAL_CLIMBERS:
			if Game.enemy.next_move == "handoff":
				return_dict["status"] = TileStatus.ASH
			else:
				return_dict["status"] = TileStatus.BLEED
		
		
		e.STOKER:
			return_dict["special"] = _replace_or_remove_status
			return_dict["special_args"] = { "status_to_remove" = TileStatus.COAL }
		e.PADDLERS:
			return_dict["status"] = TileStatus.GAY
			return_dict["special"] = _special_paddlers
		e.FOREIGN_BODY:
			return_dict["status"] = TileStatus.FROZEN
			return_dict["special"] = _special_foreign_body
		e.UFO:
			return_dict["special"] = _special_ufo
		e.UMAMI,e.SALT:
			return_dict["special"] = _link_tiles
		e.VAMPIRE:
			return_dict["special"] = _special_vampire
			return_dict["special_args"] = { "status_to_remove" = TileStatus.BLEED }
		e.PARASITE:
			return_dict["special"] = _special_vampire
			return_dict["special_args"] = {
				"status_to_remove" = TileStatus.ETERNAL,
				"status_to_replace" = TileStatus.CURSED
			}
		e.BAMMON:
			return_dict["status"] = TileStatus.CRIT
			return_dict["special"] = _special_bammon
		
	return return_dict

func _unique_rng_interactions(enemy_id:String) -> Dictionary:
	var return_dict = {}
	
	match enemy_id:
		e.BROKER:
			return_dict["rng_status"] = TileStatus.MONEY
			return_dict["rng_face_value"] = "*"
			return_dict["rng_tile_amount"] = 3
		e.BOOKWORM:
			return_dict["rng_status"] = TileStatus.SPICY
			return_dict["rng_tile_percent"] = 0.5
		e.SOCIAL_CLIMBERS:
			return_dict["special"] = _special_social_climbers
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_amount"] = 2
			return_dict["rng_status"] = TileStatus.BLEED if Game.enemy.next_move == "handoff" else TileStatus.ASH
		e.FREEZER,e.RUBBER_ANIMAL:
			return_dict["rng_face_value"] = "*"
			return_dict["rng_tile_amount"] = 2
		e.STRAWMAN, e.HOUSEBROKEN:
			return_dict["special"] = _place_bomb
			return_dict["special_args"] = { "bomb_turn_ammount" = 1 }
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_amount"] = 1
		e.GREEB:
			return_dict["rng_status"] = TileStatus.ASH
			return_dict["rng_tile_percent"] = 0.5
		e.BRUTALIST:
			return_dict["special"] = _special_brutalist
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_amount"] = 2
		e.JUVENILE:
			return_dict["rng_status"] = TileStatus.BLEED
			return_dict["rng_tile_percent"] = 0.5
		e.RECEIVER, e.PROLE_SERVICE:
			return_dict["special"] = _special_prole_service
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_percent"] = 0.5
		e.PARADIGM:
			return_dict["special"] = _place_bomb
			return_dict["special_args"] = { "bomb_turn_ammount" = 2 }
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_amount"] = 2
		e.COPYCAT:
			return_dict["special"] = _special_copycat
			return_dict["special_args"] = { "bomb_turn_ammount" = 2, "wildcard_ammount" = 2 }
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_amount"] = 1
		e.PINK_RUBBER_ANIMAL:
			return_dict["special"] = _special_pink_rubber_animal
			return_dict["special_triggers_on_rng"] = true
			return_dict["rng_tile_amount"] = 2
	
	return return_dict

func can_run_special_interaction(at_index: int, interaction_dict: Dictionary, rng_target_tiles: Array[int], _is_preview: bool) -> bool:
	if not interaction_dict.keys().has("special"):
		return false
	if interaction_dict["can_full_run_on_preview"] == false and _is_preview:
		return false
	if (
			(interaction_dict.special_triggers_on_rng and rng_target_tiles.has(at_index)) or
			not interaction_dict.special_triggers_on_rng
		):
			return true
	return false

func _get_turn_ammount() -> int:
	var all_attacks_used = Game.enemy.times_performed_move.values()
	var num_turns = 0
	for attack in all_attacks_used:
		num_turns += attack
	return num_turns

#===================================================================
#                     SPEICAL INTERACTIONS


func _replace_or_remove_status(tile:Tile, _is_preview:bool, args:Dictionary = {}) -> bool:
	if not args.keys().has("status_to_remove"):
		return false
	if tile.has_status(args.status_to_remove):
		tile.remove_status(args.status_to_remove)
		if args.keys().has("status_to_replace"):
			tile.add_status(args.status_to_replace)
		return true
	return false


func _place_bomb(tile:Tile, _is_preview:bool, args:Dictionary = {}) -> void:
	var turn_ammount = args.get("bomb_turn_ammount",3)
	tile.add_status(TileStatus.BOMB, turn_ammount)

func _link_tiles(tile:Tile, _is_preview:bool) -> void:
	var num_turn = _get_turn_ammount()
	var possible_chains = [
		Globals.LinkColor.GRAY,
		Globals.LinkColor.SILVER,
		Globals.LinkColor.RUSTY
	]
	tile.add_status(TileStatus.LINKED, possible_chains[wrap(num_turn,0,possible_chains.size()-1)] )
	if not _is_preview:
		AudioManager.play_sound(Sounds.TILE.LINKED)

func _heal_player_at_end_of_use() -> void:
	player.heal(final_use_effect_counter)

func _place_suit_wildcard(tile:Tile, _is_preview: bool, args:Dictionary = {}) -> void:
	if _is_preview:
		return
	var suits = ["♥", "♠", "♦", "♣"]
	var chosen_face = suits[wrap(_get_turn_ammount(),0,suits.size()-1)]
	var final_face = chosen_face
	if args.keys().has("wildcard_ammount"):
		while final_face.length() < args.wildcard_ammount:
			final_face += chosen_face
	
	tile.set_face(final_face)

func _special_paddlers(tile:Tile, _is_preview:bool) -> void:
	var num_row = null
	if not _is_preview:
		num_row = tile.get_coord().y
	else:
		var real_tile = Tile.get_focused_tile()
		if real_tile != null:
			num_row = real_tile.get_coord().y
	
	if num_row == null:
		num_row = 0
	
	var is_using_strong_attack = false if _get_turn_ammount() % 2 == 0 else true
	var even_row_type = TileType.DAMAGE if is_using_strong_attack else TileType.DEFENSE
	var odd_row_type = TileType.DEFENSE if is_using_strong_attack else TileType.DAMAGE
	if num_row % 2 == 0:
		tile.set_type(even_row_type)
	else:
		tile.set_type(odd_row_type)

func _special_social_climbers(tile:Tile, _is_preview:bool) -> void:
	if _is_preview:
		return
	_place_suit_wildcard(tile,_is_preview)
	
func _special_foreign_body(tile:Tile, _is_preview:bool) -> void:
	tile.remove_face_statuses()
	if _is_preview:
		tile.set_slashed([tile.face, "?"])
	else:
		tile.apply_slashed(rng.spell)

func _special_ufo(tile:Tile) -> void:
	if tile.is_type(TileType.DAMAGE):
		tile.set_type(TileType.DEFENSE)
	elif tile.is_type(TileType.DEFENSE):
		tile.set_type(TileType.DAMAGE)

func _special_brutalist(tile:Tile) -> void:
	if tile.is_type(TileType.DAMAGE):
		tile.set_type(TileType.DEFENSE)
	elif tile.is_type(TileType.DEFENSE) and not tile.has_status(TileStatus.CRIT):
		tile.add_status(TileStatus.ENHANCED)

func _special_prole_service(tile:Tile, _is_preview:bool) -> void:
	if _is_preview:
		return
	tile.set_face(Letters.get_keypad_number(tile.face, rng.spell))

func _special_pink_rubber_animal(tile:Tile, _is_preview:bool) -> void:
	if _is_preview:
		return
	var unique_tile_number = tile.get_coord().x + (tile.get_coord().y * tile_board.num_columns) 
	var current_face = tile.face
	if unique_tile_number % 2 == 0:
		tile.set_face("%s*" % current_face)
	else:
		tile.set_face("*%s" % current_face)

func _special_copycat(tile:Tile, _is_preview:bool, args:Dictionary = {}) -> void:
	if _is_preview:
		return
	_place_suit_wildcard(tile,_is_preview,args)
	_place_bomb(tile,_is_preview,args)

func _special_vampire(tile:Tile, _is_preview:bool, args:Dictionary = {}) -> void:
	if _replace_or_remove_status(tile,_is_preview,args) and not _is_preview:
		final_use_effect_counter += 1
		final_use_effect_method_name = "_heal_player_at_end_of_use"

func _special_bammon(tile:Tile, _is_preview:bool) -> void:
	var base_face = tile.faces[0]
	if base_face == "b":
		tile.set_face(["b","m"])
		return
	if _is_preview:
		tile.set_face([base_face, "?"])
		return
	tile.apply_shimmering(rng.spell,true)

extends Mod
class_name Automaton

"""
                                  TODO LIST:
===============================================================================

	- Add compatibility things:
		- Modded enemy preferences
		- Modded Ego Extractor interactions 

"""


# General purpose strings meant for use in any file which might need it.
const STRINGS = {
	MOD_ID = "automaton_character",
	CHARACTER_ID = "automaton",
	RESEARCH_NOTES_BASE_ID = "important_notes",
	RESEARCH_NOTES_DEBUG_ID = "debug_important_notes",
	RESEARCH_NOTES_RED_LETTER_ID = "personal_notes",
	RESEARCH_NOTES_RED_LETTER_DEBUG_ID = "debug_personal_notes",
	EGO_EXTRACTOR_ID = "ego_extractor",
	KABALAH_CACTUS_ID = "kabalah_cactus",
	WINRATE_ID = "winrate",
	
	GUARANTEED_PUZZLE_POOL_KEY = "special_puzzle_pool",
	
	
	MOOD_STRING_GROUP = "status/automaton_mood",
	MOOD_STRING_GROUP_ITEMS = {
		NAME = "name",
		DESCRIPTION = "description",
		ITEM_TOOLTIP_TITLE_NORMAL = "changing_mood",
		ITEM_TOOLTIP_TITLE_MAX = "max_mood",
		HOVER_TUTORIAL = "hover_tutorial"
	},
	CACTUS_FAILED_STRING_GROUP = "automaton_failed_cactus",
	
	
	SPEECH_BUBBLE_FILEPATHS = {
		MAIN = "res://mods/automaton_character/arte/automaton_speech_bubble.png",
		TAIL = "res://mods/automaton_character/arte/automaton_speech_bubble_tail.png"
	},
	
	INTENT_FOLDER_PATH = "res://mods/automaton_character/arte/intents/",
	INTENT_SPRITE_NAMES = {
		NOBODY_INSTINCT   = "nbdy_instinct.png",
		NOBODY_INSIGHT    = "nbdy_insight.png",
		NOBODY_ATTACHMENT = "nbdy_attachment.png",
		NOBODY_REPRESSION = "nbdy_repression.png"
	},
	INTENT_STRING_GROUP = "automaton_nodoby_mood",
	INTENT_STRING_GROUP_ITEMS = {
		NOBODY_INSTINCT   = "instinct",
		NOBODY_INSIGHT    = "insight",
		NOBODY_ATTACHMENT = "attachment",
		NOBODY_REPRESSION = "repression"
	},
	
	ACHIEVEMENT_SAVE_KEY = "automaton_achievements",
	ACHIEVEMENTS = {
		BEIGE_CLEAR = "kabalah_cactus_achievement",
		CERULEAN_CLEAR = "ego_extractor_achievement",
		RED_CLEAR = "automaton_max_difficulty"
	},
	
	PASSED_MOOD_BAR_HOVER_TUTORIAL = "passed_mood_bar_hover_tutorial",
	
	
	MOD_OPTIONS = {
		NOBODY_INTENTS = "Alt. Nobody Intents",
		DEBUG_WORD_CATEGORIZER = "Debug Char. Spell",
		UNLOCK_EVERYTHING = "Unlockable Spells",
		JOKE_ITEMS = "Joke Items"
	}
}

# Pseudo-global enum for word categories / work type mechanic. This reffers primarily to
# the categories used by Automaton's character item. It is called "work types" as it is
# pulling directly from Lobotomy Corporation.
enum WORK_TYPES {
	INSTINCT,
	INSIGHT,
	ATTACHMENT,
	REPRESSION,
	SHIMMER
}

# Colors associated with each respective WORK_TYPE enum value. Used for the modulate on use
# overlay effect on enemies and other misc parts like the word categorization interface.
const WORK_TYPE_COLORS = {
	Automaton.WORK_TYPES.INSTINCT:   Color("#E80B32"),
	Automaton.WORK_TYPES.INSIGHT:    Color("#DBBD65"),
	Automaton.WORK_TYPES.ATTACHMENT: Color("#85408B"),
	Automaton.WORK_TYPES.REPRESSION: Color("#27E3CC"),
	Automaton.WORK_TYPES.SHIMMER:    Color("#EC9CCB")
}

# Enum used to make enemy work_type preferences more readable in /misc/work_preferences.gd
enum WORK_PREFERENCES {
	REALLY_LIKES,
	LIKES,
	DISLIKES,
	REALLY_DISLIKES
}

# Refference to an important file used by /word_work_type_tool/work_type_program_core.gd 
# and the character's item. Contains a big dictonary directing all word-to-work-type associations.
const WORD_WORK_CATEGORY_FILE_PATH = "res://mods/automaton_character/word_categories/categories.json"


# An array witch items which should not be given to Automaton as her guaranteed puzzle gift.
# These exclusions are mainly to avoid items which do not have the capacity of changing faces in the board.
# Unused as of now. Will be implemented once custom spell pools are implemented
const DIRECT_PUZZLE_EXCLUSIONS = [
	Globals.SPELLS.CIGARETTE_BUTT, 
	Globals.SPELLS.TWELVE_GAUGE_CLAY, 
	Globals.SPELLS.TWO_POINT_LEADING, 
	Globals.SPELLS.FINGERNAIL, 
	Globals.SPELLS.BUG_SPRAY, 
	Globals.SPELLS.PRAXICE, 
	Globals.SPELLS.FAKE_ID, 
	Globals.SPELLS.FUEL_RATION, 
	Globals.SPELLS.FINGERPRINTS, 
	Globals.SPELLS.RED_TAPE, 
] 

# Other assorted variables saved in this file for ease of editing
const MISC = {
	SPEECH_BUBBLE_TEXT_COLOR = Color("#FFDE4F"),
}

# Global refference for the word categories. Can be reset through set_global_word_categories_from_file()
static var WORD_CATEGORIES: Dictionary = {}

# Used by mood_bar.tscn to define if a clarifying tooltip should be shown
static var PASSED_MOOD_BAR_HOVER_TUTORIAL = false

# Dictionary which holds the boolean unlock values for the custom achievements introduced by the mod
static var CUSTOM_ACHIEVEMENTS: Dictionary[String,bool] = {
	STRINGS.ACHIEVEMENTS.BEIGE_CLEAR: false,
	STRINGS.ACHIEVEMENTS.CERULEAN_CLEAR: false,
	STRINGS.ACHIEVEMENTS.RED_CLEAR: false
}

# Option values
var alt_nobody_intents: bool = false
static var debug_enabled: bool = false
enum UNLOCK_SETTING {
	ALWAYS_ENABLED,
	READ_FROM_FILE,
	DISABLED,
}
var handling_unlocks: UNLOCK_SETTING = UNLOCK_SETTING.READ_FROM_FILE
var joke_items: bool = false


# Filepath to the popup thrown when the mod can't detect the framework being installed
const FRAMEWORK_ERROR_POPUP_PATH = "res://mods/automaton_character/misc/error_popup.tscn"

static func set_global_word_categories_from_file(file_path: String = WORD_WORK_CATEGORY_FILE_PATH) -> void:
	WORD_CATEGORIES.clear()
	var json_string = FileAccess.get_file_as_string(file_path)
	var saved_list = JSON.parse_string(json_string)
	assert(saved_list is Dictionary, "Data inside the allocated json is not a dictionary.")
	for entry in saved_list.keys():
		saved_list[entry] = int(saved_list[entry])
	WORD_CATEGORIES = saved_list


# Functions bellow use integration tools from the framework done by Xanderath/Emarald64. 
func _ready() -> void:
	if not ModLoader.has_mod("framework"):
		_create_missing_framework_popup()
		return
	
	var normal_item_id = "%s:%s" % [STRINGS.MOD_ID, STRINGS.RESEARCH_NOTES_BASE_ID]
	var debug_item_id =  "%s:%s" % [STRINGS.MOD_ID, STRINGS.RESEARCH_NOTES_DEBUG_ID]
	
	var red_letter_id =       "%s:%s" % [STRINGS.MOD_ID, STRINGS.RESEARCH_NOTES_RED_LETTER_ID]
	var debug_red_letter_id = "%s:%s" % [STRINGS.MOD_ID, STRINGS.RESEARCH_NOTES_RED_LETTER_DEBUG_ID]
	
	CharacterLoader.add_character(
		STRINGS.CHARACTER_ID,
		normal_item_id,
		preload("res://mods/automaton_character/arte/character_select_icons.png")
	)
	CharacterLoader.custom_spell_upgrades[normal_item_id] = red_letter_id
	CharacterLoader.custom_spell_upgrades[debug_item_id]  = debug_red_letter_id
	
	# Xander's framework currently does not implement a previous custom speechbubble system
	# A version of it is implemented locally in nobody_automaton.gd
	# 
	#var speech_bubble_path_array = [
	#	STRINGS.SPEECH_BUBBLE_FILEPATHS.MAIN,
	#	STRINGS.SPEECH_BUBBLE_FILEPATHS.TAIL
	#]
	#CharacterLoader.speech_bubbles[STRINGS.CHARACTER_ID] = speech_bubble_path_array
	
	set_global_word_categories_from_file()
	_refresh_nobody_intent_icons()
	
	
	ModSettings.add_menu("Automaton",generate_mod_settings_page)


func _create_missing_framework_popup() -> void:
	var scene = preload(FRAMEWORK_ERROR_POPUP_PATH)
	var warning_popup = scene.instantiate()
	
	await Game.main_menu.ready
	await Game.main_menu.cutscene.screen_wipe.screen_covered # Waits for opening credits to play
	Game.add_child(warning_popup)
	warning_popup.popup_centered_clamped()
	warning_popup.grab_focus()

# ==============================================================================
#                           SPELLS & REGISTRIES


func register_callbacks(helper: CallbackHelper) -> void :
	helper.add_callback(
		Callbacks.REGISTER_SPELLS.MOD_INIT,
		_register_spells,
		Callbacks.BASE_PRIORITY.FIRST
	)
	
	helper.add_callback(
		Callbacks.MODIFY_SPELL_POOL.EARLY,
		_modify_spells_on_unlocks_and_options,
		Callbacks.BASE_PRIORITY.FIRST
	)

func _register_spells():
	SpellRegistry.register(self, get_spell_ids())
	SpellRegistry.register_categories(self, [get_special_puzzle_spell_category_key()])
	SpellRegistry.add_spells_to_categories(get_spell_category_map())
	SpellRegistry.add_spells_to_pool(get_spell_weigths())

func _modify_spells_on_unlocks_and_options(pool) -> void:
	var conditionals: Dictionary[String,bool] = {
		STRINGS.KABALAH_CACTUS_ID: CUSTOM_ACHIEVEMENTS[STRINGS.ACHIEVEMENTS.BEIGE_CLEAR],
		STRINGS.EGO_EXTRACTOR_ID: CUSTOM_ACHIEVEMENTS[STRINGS.ACHIEVEMENTS.CERULEAN_CLEAR],
	}
	
	# Replaces the keys based on the option selection
	match handling_unlocks:
		UNLOCK_SETTING.ALWAYS_ENABLED:
			for key in conditionals.keys():
				conditionals[key] = true
		UNLOCK_SETTING.DISABLED:
			for key in conditionals.keys():
				conditionals[key] = false
	
	# Pushes joke item if that option is enabled
	conditionals.set(STRINGS.WINRATE_ID, joke_items)
	
	var weights = get_spell_weigths()
	
	for conditional_key in conditionals.keys():
		var true_key = get_standardized_spell_key(conditional_key)
		if conditionals[conditional_key]: # Item should be added
			pool[true_key] = weights[true_key]
		else:
			pool[true_key] = 0.0

func _add_puzzle_pool_compatibility(pool_categories) -> void:
	print(pool_categories)


func get_spell_ids() -> Array:
	return [
		get_standardized_spell_key(STRINGS.RESEARCH_NOTES_BASE_ID),
		get_standardized_spell_key(STRINGS.RESEARCH_NOTES_RED_LETTER_ID),
		get_standardized_spell_key(STRINGS.KABALAH_CACTUS_ID),
		get_standardized_spell_key(STRINGS.EGO_EXTRACTOR_ID),
		
		# Debug versions
		get_standardized_spell_key(STRINGS.RESEARCH_NOTES_DEBUG_ID),
		get_standardized_spell_key(STRINGS.RESEARCH_NOTES_RED_LETTER_DEBUG_ID),
		
		# Joke items
		get_standardized_spell_key(STRINGS.WINRATE_ID)
	]

func get_spell_weigths() -> Dictionary[String,float]:
	return {
		get_standardized_spell_key(STRINGS.EGO_EXTRACTOR_ID)  : 0.5,
		get_standardized_spell_key(STRINGS.KABALAH_CACTUS_ID) : 1.0,
		get_standardized_spell_key(STRINGS.WINRATE_ID) : 10.0
	}

func get_spell_category_map() -> Dictionary[String,Array]:
	return {
		Globals.SPELL_CATEGORY.SUPPORT: [
			get_standardized_spell_key(STRINGS.EGO_EXTRACTOR_ID)
		],
		get_special_puzzle_spell_category_key(): get_custom_puzzle_pool()
	}

static func get_standardized_spell_key(root_string: String) -> String:
	return "%s:%s" % [STRINGS.MOD_ID, root_string] 

static func get_special_puzzle_spell_category_key() -> String:
	return "%s:%s" % [STRINGS.MOD_ID, STRINGS.GUARANTEED_PUZZLE_POOL_KEY]

func get_custom_puzzle_pool() -> Array:
	var pool = SpellRegistry.get_spells_in_category(Globals.SPELL_CATEGORY.SUPPORT)
	for spell in pool:
		if DIRECT_PUZZLE_EXCLUSIONS.has(spell):
			pool.erase(spell)
	
	return pool



# ==============================================================================
#                           CUSTOM ACHIEVEMENTS


# Called by nobody_automaton.gd upon being defeated. Mainly serves to show the unlock popus
# and to introduce the unlockable items to the poll
static func handle_custom_achievemnts_on_run_clear(difficulty: int) -> void:
	
	if not CUSTOM_ACHIEVEMENTS[STRINGS.ACHIEVEMENTS.BEIGE_CLEAR]:
		_push_achievement_as_unlocked(STRINGS.ACHIEVEMENTS.BEIGE_CLEAR)
	
	if not CUSTOM_ACHIEVEMENTS[STRINGS.ACHIEVEMENTS.CERULEAN_CLEAR] and difficulty >= 4: # Cirulean difficulty
		_push_achievement_as_unlocked(STRINGS.ACHIEVEMENTS.CERULEAN_CLEAR)
	
	if not CUSTOM_ACHIEVEMENTS[STRINGS.ACHIEVEMENTS.RED_CLEAR] and difficulty >= 9: # Red difficulty
		_push_achievement_as_unlocked(STRINGS.ACHIEVEMENTS.RED_CLEAR)

static func _push_achievement_as_unlocked(achievement_key: String) -> void:
	AchievementManager.queue_unlock_popup(achievement_key)
	CUSTOM_ACHIEVEMENTS[achievement_key] = true

func load_save_data(data: Dictionary) -> void:
	PASSED_MOOD_BAR_HOVER_TUTORIAL = data.get(STRINGS.PASSED_MOOD_BAR_HOVER_TUTORIAL,false)
	var loaded_achievements = data.get(STRINGS.ACHIEVEMENT_SAVE_KEY,{})
	_load_custom_achievements(loaded_achievements)

func get_save_data() -> Dictionary:
	return {
		STRINGS.ACHIEVEMENT_SAVE_KEY: CUSTOM_ACHIEVEMENTS,
		STRINGS.PASSED_MOOD_BAR_HOVER_TUTORIAL: PASSED_MOOD_BAR_HOVER_TUTORIAL
	}

static func _load_custom_achievements(from_dict: Dictionary) -> void:
	if from_dict.is_empty():
		return
	
	for key in CUSTOM_ACHIEVEMENTS.keys():
		if from_dict.keys().has(key):
			CUSTOM_ACHIEVEMENTS[key] = from_dict[key]

# ==============================================================================
#                                MOD OPTIONS
# General code structure taken from Xanderath/Emarald64's "Foggy glasses" framework mod example.

func generate_mod_settings_page() -> Control:
	var base_settings: Control = load("res://mods/framework/mod_options.tscn").instantiate()
	base_settings.options = [
		{name=STRINGS.MOD_OPTIONS.NOBODY_INTENTS,type=Variant.Type.TYPE_BOOL},
		{name=STRINGS.MOD_OPTIONS.DEBUG_WORD_CATEGORIZER,type=Variant.Type.TYPE_BOOL},
		
		{name=STRINGS.MOD_OPTIONS.UNLOCK_EVERYTHING,type=Variant.Type.TYPE_STRING,
			options=["Force Enable","Only if unlocked","Disabled"]
		},
		{name=STRINGS.MOD_OPTIONS.JOKE_ITEMS,type=Variant.Type.TYPE_BOOL}
	]
	
	base_settings.option_changed.connect(_on_options_updated)
	base_settings.get_setting_method = get_option_value
	
	base_settings.add_theme_constant_override("separation",0)
	
	base_settings.set_layout()
	return base_settings
	

func _on_options_updated(option:String, value) -> void:
	match option:
		STRINGS.MOD_OPTIONS.NOBODY_INTENTS:
			alt_nobody_intents = value
			_refresh_nobody_intent_icons()
		STRINGS.MOD_OPTIONS.DEBUG_WORD_CATEGORIZER:
			debug_enabled = value
		STRINGS.MOD_OPTIONS.UNLOCK_EVERYTHING:
			handling_unlocks = value
		STRINGS.MOD_OPTIONS.JOKE_ITEMS:
			joke_items = value

func get_option_value(option:String):
	match option:
		STRINGS.MOD_OPTIONS.NOBODY_INTENTS:
			return alt_nobody_intents
		STRINGS.MOD_OPTIONS.DEBUG_WORD_CATEGORIZER:
			return debug_enabled
		STRINGS.MOD_OPTIONS.UNLOCK_EVERYTHING:
			return handling_unlocks
		STRINGS.MOD_OPTIONS.JOKE_ITEMS:
			return joke_items
	

func load_options_save_data(data: Dictionary) -> void :
	alt_nobody_intents = data.get(STRINGS.MOD_OPTIONS.NOBODY_INTENTS,false)
	debug_enabled = data.get(STRINGS.MOD_OPTIONS.DEBUG_WORD_CATEGORIZER,false)
	handling_unlocks = data.get(STRINGS.MOD_OPTIONS.UNLOCK_EVERYTHING,UNLOCK_SETTING.READ_FROM_FILE)
	joke_items = data.get(STRINGS.MOD_OPTIONS.JOKE_ITEMS,false)

func get_options_save_data() -> Dictionary:
	return {
		STRINGS.MOD_OPTIONS.NOBODY_INTENTS: alt_nobody_intents,
		STRINGS.MOD_OPTIONS.DEBUG_WORD_CATEGORIZER: debug_enabled,
		STRINGS.MOD_OPTIONS.UNLOCK_EVERYTHING: handling_unlocks,
		STRINGS.MOD_OPTIONS.JOKE_ITEMS: joke_items,
	}

func _refresh_nobody_intent_icons() -> void:
	for intent in STRINGS.INTENT_STRING_GROUP_ITEMS.keys():
		var intent_string_path = "%s_%s" % [STRINGS.INTENT_STRING_GROUP,STRINGS.INTENT_STRING_GROUP_ITEMS[intent]]
		var sprite_name = STRINGS.INTENT_SPRITE_NAMES[intent]
		if alt_nobody_intents:
			sprite_name = "old_%s" % sprite_name
		var sprite_path = "%s%s" % [STRINGS.INTENT_FOLDER_PATH,sprite_name]
		CustomIntent.custom_intent_icons[intent_string_path] = load(sprite_path)



# ==============================================================================
#                              MOD COMPATIBILITY

static func get_important_notes_compatibility() -> Dictionary:
	var raw_dict: Dictionary = _get_merged_returns_as_dict("get_automaton_impotant_notes_additions")
	
	var look_up_table = raw_dict.keys()
	
	for key in look_up_table:
		var values: Array = raw_dict[key]
		var is_value_valid = true
		if values.size() != 4: # Preference size does not match what it should be
			is_value_valid = false
			printerr("Preference array should have 4 items, but it had %s." % [key,values.size()]
			)
		else:
			# Checks if there are any values outside the supposed ones from the enum in work_preferences.gd
			if (values.count(0) + values.count(1) + values.count(2) + values.count(3)) != 4:
				is_value_valid = false
				printerr("Array should only have numbers between 0 and 3.")
		
		if not is_value_valid:
			raw_dict.erase(key)
	
	return raw_dict

static func get_ego_extractor_compatibility() -> Dictionary:
	var raw_array: Array = _get_merged_returns_as_array("get_automaton_ego_extractor_additions")
	var processed_dict: Dictionary[String,Dictionary] = {}
	for entry:AutomatonExtractorData in raw_array:
		processed_dict[entry.enemy_id] = entry.get_as_compiled_dict()
	
	return processed_dict

static func _get_merged_returns_as_array(method_name: String) -> Array:
	var return_array: Array = []
	
	for mod in ModLoader.mod_scenes:
		if mod.has_method(method_name):
			var value = mod.call(method_name)
			if value is Array:
				return_array.append_array(value)
			else:
				return_array.append(value)
	
	return return_array

static func _get_merged_returns_as_dict(method_name: String) -> Dictionary:
	var return_dict: Dictionary = {}
	
	for mod in ModLoader.mod_scenes:
		if mod.has_method(method_name):
			var value = mod.call(method_name)
			if value is Dictionary:
				return_dict.merge(value)
	
	return return_dict

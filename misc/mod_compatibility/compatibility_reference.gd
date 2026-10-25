extends Mod

# This is a reference on what to add to make other mods compatible with this mod.

# These consts are not required, but it is best for organization.
# Feel free to implement them however you would like!

const AUTOMATON_CUSTOM_PUZZLE_ADDITIONS = [ # Pass all of the spell IDs you want to add.
	Globals.SPELLS.DAMAGED_GOODS
]
const AUTOMATON_IMPORTANT_NOTES_ADDITIONS = {
	# Pass all new enemy IDs as the keys and an int array with 4 items, each varrying from 0 to 3, as the values
	# They represent the Body, Science, Fun and Violence word categories, in that order.
	# Use the enum in work_preferences.gd for reference on which preference level each number refers to. 
	"nonexistent_enemy": [3,3,3,3]
}

func register_callbacks(helper: CallbackHelper) -> void:
	# This is part of the normal mod.dg Mod class. You only need to add the following line at
	# some point to that function on your file:
	
	helper.add_callback(
		Callbacks.REGISTER_SPELLS.MOD_SECONDARY,_set_automaton_custom_puzzle_additions,Callbacks.BASE_PRIORITY.FIRST)

func _set_automaton_custom_puzzle_additions() -> void:
	if ModLoader.has_mod("automaton_character"):
		SpellRegistry.add_spells_to_category("automaton_character:special_puzzle_pool",AUTOMATON_CUSTOM_PUZZLE_ADDITIONS)


# The following two functions do not run on their own. They are called by
# important_notes.gd and  ego_extractor.gd when those spells load in (as in: when you
# get the spell in game.)

func get_automaton_impotant_notes_additions() -> Dictionary:
	# Items added to this pool should be items within the Puzzle/Support pool which allow
	# the player to alter tile faces.
	return AUTOMATON_IMPORTANT_NOTES_ADDITIONS

func get_automaton_ego_extractor_additions() -> Array:
	var additions = []
	
	# You do not need to add all of your enemies into this one, but you may do so if you want.
	
	# As a general guideline on what each of these do:
	#    new() is just meant to pass the enemy ID and a default status every converted tile;
	#    add_rng_params() is meant for setting X (int) tiles or X% (float) of tiles to be given specific status or faces;
	#    add_special_params() lets you pass a function to be run for every tile or tiles triggered on rng;
	#    add_extra_params() lets you change (complete override of what the spell will write).
	# Check for extra info about this class in ego_extractor_enemy_data.gd.
	
	
	var elmer_params = AutomatonExtractorData.new(Enemies.ELMER,Tile.TileStatus.CURSED)
	elmer_params.add_rng_params(2,1,Tile.TileStatus.CRIT,false)
	elmer_params.add_special_params(elmer_special, {"example_param" = "example"})
	elmer_params.add_extra_params("elmer")
	
	additions.append(elmer_params)
	
	return additions



# Example of a full ego extractor "special" function.
# Remove args if you do not intend to pass any extra parameters to the function.
@warning_ignore("unused_parameter")
func elmer_special(tile:Tile,_is_preview:bool,args:Dictionary = {}) -> void:
	if tile.type == Tile.TileType.DAMAGE:
		tile.set_face("dam")
	else:
		tile.set_face("def")

extends Player

func _init():
	id = Automaton.STRINGS.CHARACTER_ID
	
	starting_spells = [(
		Automaton.get_standardized_spell_key(Automaton.STRINGS.RESEARCH_NOTES_BASE_ID)
		if not Automaton.debug_enabled else
		Automaton.get_standardized_spell_key(Automaton.STRINGS.RESEARCH_NOTES_DEBUG_ID)
		)]

func get_gender():
	if is_trans():
		return Gender.NONBINARY
	else:
		return Gender.FEMALE

func get_crit_chance() -> Dictionary:
	var crit_chance = Globals.CRIT_CHANCE[CHARACTERS.CHILD].duplicate() # No crits
	crit_chance.merge(Globals.CRIT_CHANCE[CHARACTERS.LEXICOGRAPHER])
	return crit_chance

func get_first_spell_select_guaranteed_category() -> String:
	return Automaton.get_special_puzzle_spell_category_key()

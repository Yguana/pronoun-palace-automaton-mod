extends "res://mods/automaton_character/source/spells/important_notes.gd"

func _get_mood_value_change_from_word_length(length: int) -> float:
	return length/0.7


func _get_mood_affected_base_multipliers(fomula_value: int) -> Dictionary:
	var multipliers = super._get_mood_affected_base_multipliers(fomula_value)
	for mult_key in multipliers.keys():
		if multipliers[mult_key] < 0.5:
			multipliers[mult_key] = 0.5
	return multipliers

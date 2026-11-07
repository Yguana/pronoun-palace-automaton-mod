extends "res://mods/automaton_character/source/spells/important_notes.gd"

func get_bonus_reset_value(for_positive_bonus: bool) -> int:
	if for_positive_bonus:
		return pos_mood_revert_bonus + mood_bonus_resets_on_this_fight + 1
	else:
		return neg_mood_revert_bonus + (mood_bonus_resets_on_this_fight * 2)

func get_base_mult_extreme_step() -> float:
	return 0.3

func _get_mood_affected_base_multipliers(fomula_value: int) -> Dictionary:
	var multipliers = super._get_mood_affected_base_multipliers(fomula_value)
	for mult_key in multipliers.keys():
		if multipliers[mult_key] < 0.5:
			multipliers[mult_key] = 0.5
	return multipliers

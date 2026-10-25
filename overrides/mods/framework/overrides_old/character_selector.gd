extends "res://mods/framework/overrides_old/character_selector.gd"

# This script exists solely to fix a small issue in the current code of the framework made by xander to
# allow modded items to load their title properly in the select. The function bellow, aside a single
# line alteration, was taken from the framework file this file inherits from.

func update_character() -> void :
	var id = selected_character
	var character_difficulty = get_character_difficulty(id)
	var is_trans = Globals.is_character_trans(id, character_difficulty)

	prep_character_sprite(id, is_trans)

	var context = {trans = is_trans}
	if selected_is_unlocked:
		%TitleLabel.text = StringManager.get_string("character/%s/select_title" % id, context)
		%DescriptionLabel.text = StringManager.get_string("character/%s/description" % id, context)
		%SpellSprite.modulate = Color.WHITE
		%InfoSprite.modulate = Color.WHITE
	else:
		%TitleLabel.text = StringManager.get_string("menu/character_select/locked")
		%DescriptionLabel.text = StringManager.get_string("achievements/unlock_%s/unlock" % id, {locked = true})
		%SpellSprite.modulate = Color.BLACK
		%InfoSprite.modulate = Color.BLACK

	%NameLabel.text = char_string_or_locked("name", context)
	%SexLabel.text = char_string_or_locked("sex", context)
	%HeightLabel.text = char_string_or_locked("height", context)
	%WeightLabel.text = char_string_or_locked("weight", context)
	%OccupationLabel.text = char_string_or_locked("occupation", context)

	var spell_id:String
	if id in CharacterLoader.character_spells:
		spell_id=CharacterLoader.character_spells[id]
	else:
		spell_id = Globals.CHARACTER_SPELLS[id][0]
	var spell: = Spell._instantiate_spell(spell_id)
	if character_difficulty == 10:
		spell.set_curse(Globals.SPELL_CURSES.CURSED)

	%SpellSprite.link_spell(spell)
	%SpellName.text = string_or_locked("spell/spell_title", spell.get_title_context()) # Only line that changes
	%SpellDescription.text = char_string_or_locked("spell_description")

	%InfoTitle.text = char_string_or_locked("info_title")
	%InfoLabel.text = char_string_or_locked("info")

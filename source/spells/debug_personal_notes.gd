extends "res://mods/automaton_character/source/spells/personal_notes.gd"

const debug_word_categorizer = preload("res://mods/automaton_character/word_work_type_tool/word_type_ingame_debug.tscn")

func _ready() -> void:
	super._ready()
	await Game.main.player_action_started
	var categorizer = debug_word_categorizer.instantiate()
	var ui_layer = Game.main.get_node("GameUILayer")
	if ui_layer == null:
		return
	ui_layer.add_child(categorizer)

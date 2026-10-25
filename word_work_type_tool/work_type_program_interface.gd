@abstract class_name AutomatonCategorizerInterface extends Node

@export var categorization_pop_up: Control

var core: AutomatonCategorizerCore
var confirmed_auto_categorization = false

signal auto_categorization_button_pressed

func _init() -> void:
	core = AutomatonCategorizerCore.new(self)

func _ready() -> void:
	categorization_pop_up.hide()

@abstract func get_current_word() -> String
@abstract func _update_autocategory_pop_up(words_listed: Array) -> void
@abstract func _get_autocategorized_selections() -> Array


func process_selection_button(button_type) -> void:
	# Called on work_type_selection_button.gd
	# button_type is an int from 0 to 4
	pass_work_type_selection_to_core(get_current_word(),button_type)

func pass_work_type_selection_to_core(word: String, work_type: int) -> void:
	core.write_or_remove_word(word, work_type)

func _on_confirmed_categorization_pop_up() -> void:
	confirmed_auto_categorization = true
	auto_categorization_button_pressed.emit()

func _on_denied_categorization_pop_up() -> void:
	confirmed_auto_categorization = true
	auto_categorization_button_pressed.emit()

func user_confirm_auto_categorized_list(words_listed: Array) -> Array:
	if words_listed.is_empty():
		return []
		
	_update_autocategory_pop_up(words_listed)
	categorization_pop_up.show()
	await auto_categorization_button_pressed
	if not confirmed_auto_categorization:
		return []
	categorization_pop_up.hide()
	return _get_autocategorized_selections()
	
	

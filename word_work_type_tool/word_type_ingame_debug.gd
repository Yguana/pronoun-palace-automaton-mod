extends AutomatonCategorizerInterface

@onready var typed_word_line: LineEdit = %SelectedWord
@onready var autocategory_pop_up_item_list =  %AutoCategoryWordList
@onready var quick_selection_button = %QuickSelectButton

func _ready() -> void:
	super._ready()
	quick_selection_button.pressed.connect(_replace_current_for_word_builder_word)


func _replace_current_for_word_builder_word() -> void:
	if not Game.word_builder.get_words().words.is_empty():
		typed_word_line.text = Game.word_builder.get_words().words[0]

func get_current_word() -> String:
	return typed_word_line.text

func _update_autocategory_pop_up(words_listed: Array):
	autocategory_pop_up_item_list.clear()
	
	for found_word in words_listed:
		var index = autocategory_pop_up_item_list.add_item(found_word)
		autocategory_pop_up_item_list.set_item_tooltip_enabled(index,false)

func _get_autocategorized_selections() -> Array:
	if autocategory_pop_up_item_list.item_count < 1:
		return []
	
	var return_array = []
	for x in range(autocategory_pop_up_item_list.item_count):
		if autocategory_pop_up_item_list.is_selected(x):
			return_array.append(autocategory_pop_up_item_list.get_item_text(x))
	return return_array


func pass_work_type_selection_to_core(word: String, work_type: int) -> void:
	if core.write_or_remove_word(word, work_type):
		if autocategory_pop_up_item_list.visible:
			await core.word_categories_updated
		core.save_category_list_to_file()
		Automaton.set_global_word_categories_from_file()
		Game.main.game_state_updated.emit()
		typed_word_line.clear()
		

extends AutomatonCategorizerInterface

@onready var main_word_label = %SelectedWord
@onready var word_glossary = %WordGlossary
@onready var page_skipper_label = %PageSkipperCount
@onready var page_skipper_button_forwards = %ForwardButton
@onready var page_skipper_button_backwards = %BackwardsButton
@onready var page_skipper_slider = %PageSlider

@onready var search_bar = %SearchBar
@onready var confirm_search_button = %ConfirmSearch

@onready var auto_categorizing_toggle= %AutoCategoryButton
@onready var skip_class_button = %SkipClassificationButton

@onready var autocategory_pop_up_item_list =  %AutoCategoryWordList

const max_words_per_page = 40

var current_word = ""
var current_word_index = 0
var glossary_page_index = 0
var max_glossary_page_index = glossary_page_index


func _ready() -> void:
	categorization_pop_up.hide()
	_set_max_glossary_page_index() 
	_set_glossary_page_to(0)
	
	page_skipper_button_forwards.pressed.connect(_move_step_in_word_glossary_page.bind(true))
	page_skipper_button_backwards.pressed.connect(_move_step_in_word_glossary_page.bind(false))
	word_glossary.item_clicked.connect(_skip_to_specific_word)
	page_skipper_slider.drag_ended.connect(_on_page_slider_moved)
	confirm_search_button.pressed.connect(_on_search_requested)
	skip_class_button.pressed.connect(_skip_to_next_word)
	core.print_list_statistics()

func get_current_word() -> String:
	return current_word

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
	var word_glossary_page_index = current_word_index - (max_words_per_page * glossary_page_index)
	core.write_or_remove_word(word, work_type)
	if work_type < 4:
		word_glossary.set_item_custom_bg_color(word_glossary_page_index,Automaton.WORK_TYPE_COLORS[work_type])
	else:
		word_glossary.set_item_custom_bg_color(word_glossary_page_index,Color.TRANSPARENT)
	_skip_to_next_word()
	

func _skip_to_next_word() -> void:
	var next_word_index = current_word_index+1
	if next_word_index >= _get_ending_index_on_page():
		_move_step_in_word_glossary_page(true)
		return
	_set_current_word(next_word_index) 

@warning_ignore("unused_parameter")
func _skip_to_specific_word(word_index_in_page: int, vector: Vector2, mouse_button: int) -> void:
	if mouse_button == 1 : # Left click
		word_glossary.deselect_all()
		var true_word_index = word_index_in_page + (max_words_per_page * glossary_page_index)
		_set_current_word(true_word_index)

func _set_current_word(word_index_in_list: int) -> void:
	current_word_index = word_index_in_list
	current_word = core.word_list[current_word_index]
	main_word_label.text = current_word
	main_word_label.remove_theme_color_override("font_color")
	if current_word in core.current_category_list.keys():
		core.set_auto_categorizing(false)
		auto_categorizing_toggle.button_pressed = core.auto_categorizing_normal_variants
		main_word_label.add_theme_color_override(
			"font_color",
			Automaton.WORK_TYPE_COLORS[core.current_category_list[current_word]]
			)
	else:
		main_word_label.add_theme_color_override("font_color",Color.WHITE)
		core.set_auto_categorizing(true)
		auto_categorizing_toggle.button_pressed = core.auto_categorizing_normal_variants

func _move_step_in_word_glossary_page(going_forward: bool) -> void:
	var addition = 1 if going_forward else -1
	var next_page = glossary_page_index + addition
	if _set_glossary_page_to(next_page):
		_set_current_word(_get_starting_index_on_page())
	core.save_category_list_to_file()

func _set_glossary_page_to(page_index: int) -> bool:
	if page_index < 0 or page_index > max_glossary_page_index:
		return false # page wasn't legal to be set
	glossary_page_index = page_index
	_refresh_glossary_page()
	_update_glossary_label()
	return true

func _refresh_glossary_page() -> void:
	word_glossary.clear()
	for x in range (_get_starting_index_on_page(),_get_ending_index_on_page()):
		var new_item = word_glossary.add_item(core.word_list[x])
		word_glossary.set_item_tooltip_enabled(new_item,false)
		if core.word_list[x] in core.current_category_list.keys():
			var classification = int(core.current_category_list[core.word_list[x]])
			word_glossary.set_item_custom_bg_color(new_item,Automaton.WORK_TYPE_COLORS[classification])
		
	_set_current_word(_get_starting_index_on_page())

func _update_glossary_label() -> void:
	page_skipper_label.text = "%s/%s" % [glossary_page_index +1, max_glossary_page_index+ 1]

func _on_page_slider_moved(value_changed:bool) -> void:
	if not value_changed:
		return
	var slide_percent = page_skipper_slider.value / 100
	var aprox_page = int(max_glossary_page_index * slide_percent)
	_set_glossary_page_to(aprox_page)
	

func _set_max_glossary_page_index() -> void:
	var base_number = core.get_full_word_list_size() / max_words_per_page
	var extra_page = 1 if core.get_full_word_list_size() % max_words_per_page != 0 else 0
	max_glossary_page_index = base_number + extra_page - 1


func _get_starting_index_on_page() -> int:
	var starting_page_index = (max_words_per_page * glossary_page_index)
	return clamp(starting_page_index, 0, core.get_full_word_list_size())
	

func _get_ending_index_on_page() -> int:
	var starting_page_index = _get_starting_index_on_page()
	var ending_page_index = starting_page_index + max_words_per_page
	return clamp(ending_page_index, starting_page_index, core.get_full_word_list_size())

func _get_index_page_from_single_word_list_index(index: int) -> int:
	return int(index / max_words_per_page)

func _on_save_button_pressed() -> void:
	core.save_category_list_to_file()


func _on_load_button_pressed() -> void:
	core.load_category_list_from_file()


func _on_go_to_last_change_pressed() -> void:
	if core.current_category_list.is_empty():
		return
	var last_word = core.current_category_list.keys()[-1]
	_on_search_requested(last_word)

func _on_search_requested(research_text: String = search_bar.text) -> void:
	var possible_word_index = core.get_index_of_word_on_word_list(research_text)
	if possible_word_index != -1: # returned text is a valid word:
		var page_location = _get_index_page_from_single_word_list_index(possible_word_index)
		_set_glossary_page_to(page_location)
		_set_current_word(possible_word_index)
		return
	if research_text.is_valid_int():
		_set_glossary_page_to(int(research_text) -1)


func _on_auto_category_button_toggled(toggled_on: bool) -> void:
	core.set_auto_categorizing(toggled_on)

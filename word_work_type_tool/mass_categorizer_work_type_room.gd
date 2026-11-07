extends Node2D

# This does not extend AutomatonCategorizerInterface as the way it interacts
# with the compiled list is significantly different.

@onready var include_textbox = %IncludeCategoriesTextEdit
@onready var exclude_textbox = %ExcludeCategoriesTextEdit

@onready var search_button = %Search

func _ready() -> void:
	_disable_keybinds()
	
	search_button.button_up.connect(_perform_category_search)

func _disable_keybinds() -> void:
	var keybind=InputEventKey.new()
	keybind.physical_keycode=KEY_Z
	InputMap.action_erase_event("ui_accept",keybind)
	keybind.physical_keycode=KEY_F
	InputMap.action_erase_event("toggle_fullscreen",keybind)

func _perform_category_search() -> void:
	var include_categories = include_textbox.text.split("\n")
	var exclude_categories = exclude_textbox.text.split("\n")
	
	



@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_text_newline"):
		_add_new_line_if_applicable()

func _add_new_line_if_applicable() -> void:
	var focused_textbox: TextEdit = null
	
	if include_textbox.has_focus():
		focused_textbox = include_textbox
	elif exclude_textbox.has_focus():
		focused_textbox = exclude_textbox
	
	if focused_textbox != null:
		focused_textbox.text += "\n"
		focused_textbox.set_caret_line(-1)

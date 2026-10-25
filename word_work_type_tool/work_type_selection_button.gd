extends Button

@export_enum("Instinct","Insight","Attachment","Repression","None") var button_type : int

@export var main_interface: AutomatonCategorizerInterface

func _pressed() -> void:
	main_interface.process_selection_button(button_type)

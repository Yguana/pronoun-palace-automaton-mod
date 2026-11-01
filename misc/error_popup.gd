extends Window

func _ready() -> void:
	close_requested.connect(func(): queue_free())

func _on_button_button_up() -> void:
	close_requested.emit()

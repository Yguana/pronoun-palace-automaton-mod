extends Control


func _ready() -> void:
	mouse_entered.connect( func(): focus_entered.emit())
	mouse_exited.connect( func(): focus_exited.emit())

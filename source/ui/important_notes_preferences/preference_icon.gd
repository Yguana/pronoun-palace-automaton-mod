extends Control

@export_enum("Instinct","Insight","Attachment","Repression") var work_color

func _ready() -> void:
	modulate = Automaton.WORK_TYPE_COLORS[work_color]

func set_sprite(indexes: Array) -> void:
	%Sprite.frame = indexes[work_color]

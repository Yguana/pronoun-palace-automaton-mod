class_name AutomatonMultipliersSubTooltip extends SubTooltip

@onready var title_label = %Title
@onready var fake_intent_containers = %FakeIntentContainers
@onready var fake_intent_container_material: ShaderMaterial = fake_intent_containers.material
@onready var fake_damage_label = %FakeAttackLabel
@onready var fake_defense_label = %FakeDefenseLabel


func _get_title_label(internal_string_identifier: String) -> String:
	var group: StringManager.StringGroup = StringManager.get_string_group(Automaton.STRINGS.MOOD_STRING_GROUP)
	return group.get_string(internal_string_identifier)

func _toggle_monochrome_shader(to_on: bool) -> void:
	fake_intent_container_material.set_shader_parameter("set_to_monochrome",to_on)

func set_new_multiplier_labels(damage_mult_value: float, defense_mult_value: float, on_max_mood: bool = false) -> void:
	var title_itentifier
	if on_max_mood:
		title_itentifier = Automaton.STRINGS.MOOD_STRING_GROUP_ITEMS.ITEM_TOOLTIP_TITLE_MAX
		_toggle_monochrome_shader(true)
	else:
		title_itentifier = Automaton.STRINGS.MOOD_STRING_GROUP_ITEMS.ITEM_TOOLTIP_TITLE_NORMAL
		_toggle_monochrome_shader(false)
	
	title_label.text = _get_title_label(title_itentifier)
	fake_damage_label.text = str(damage_mult_value)
	fake_defense_label.text = str(defense_mult_value)

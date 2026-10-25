class_name AutomatonExtractorData extends RefCounted

enum RNG_TYPE {
	NONE,
	WORD_PERCENT,
	TILE_AMOUNT
}

var enemy_id: String = "" # Unit ID of the matching enemy this data should refference
var enemy_name_override: String = ""
var status: String = Globals.TileStatus.DEFAULT


var special: Callable
var special_args = {}


var rng_type: int = RNG_TYPE.NONE
var rng_number = 0.0
var rng_status: String = Globals.TileStatus.DEFAULT
var special_triggers_on_rng = false
var rng_face_value = ""

var tile_overlay_anim = "none"
var can_full_run_on_preview = true

func _init(_enemy_id: String, status_conversion: String = Globals.TileStatus.DEFAULT) -> void:
	enemy_id = _enemy_id
	status = status_conversion

func add_rng_params(
	behave_as: int, # Look at RNG_TYPE for refference
	number_for_behaviour: float,
	_rng_status: String = Globals.TileStatus.DEFAULT,
	_special_triggers_on_rng: bool = false,
	_rng_face_value: String = ""
	) -> void:
	if behave_as == RNG_TYPE.NONE:
		return
	
	rng_type = behave_as
	rng_number = number_for_behaviour
	rng_status = _rng_status
	special_triggers_on_rng = _special_triggers_on_rng
	rng_face_value = _rng_face_value

func add_special_params(
	main_special: Callable, # This should be a function whose first argument is a tile
	params: Dictionary = {}
) -> void:
	if main_special.get_argument_count() < 0:
		return
	
	special = main_special
	
	if main_special.get_argument_count() < 1:
		return
	
	if not params.is_empty():
		special_args = params

func add_extra_params(name_override: String = "", _tile_overlay_anim: String = "none") -> void:
	enemy_name_override = name_override
	tile_overlay_anim = _tile_overlay_anim

func get_as_compiled_dict() -> Dictionary:
	var return_dict = { "enemy_id": enemy_id }
	
	if enemy_name_override != "":
		return_dict["name_override"] = enemy_name_override
	
	if status != Globals.TileStatus.DEFAULT:
		return_dict["status"] = status
	
	if special.is_valid() and special.get_argument_count() > 0:
		return_dict["special"] = special
	if not special_args.is_empty():
		return_dict["special_args"] = special_args
	
	if rng_type == RNG_TYPE.NONE:
		return_dict["can_full_run_on_preview"] = true
	else:
		return_dict["can_full_run_on_preview"] = false
		
		if rng_type == RNG_TYPE.WORD_PERCENT:
			return_dict["rng_tile_percent"] = rng_number
		elif rng_type == RNG_TYPE.TILE_AMOUNT:
			return_dict["rng_tile_amount"] = int(rng_number)
		
		if special_triggers_on_rng:
			return_dict["special_triggers_on_rng"] = true
		if rng_status != Globals.TileStatus.DEFAULT:
			return_dict["rng_status"] = rng_status
		if rng_face_value != "":
			return_dict["rng_face_value"] = rng_face_value
	
	if not can_full_run_on_preview:
		return_dict["can_full_run_on_preview"] = false
	if tile_overlay_anim != "none":
		return_dict["tile_overlay_anim"] = tile_overlay_anim
	
	return return_dict

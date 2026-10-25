extends Node
class_name AutomatonCategorizerCore

const PREFIX_LIST = [
	"un",
	"im",
	"in",
	"en",
	"re",
	"pre",
	"dis",
	"over",
	"under",
	"mis",
	"inter"
	]

const SUFFIX_LIST = [
	"s",
	"d",
	"es",
	"en",
	"ly",
	"ify",
	"ity",
	"ry",
	"ary",
	"ic",
	"ics",
	"ries",
	"lity",
	"ties",
	"lities",
	"ful",
	"able",
	"ables",
	"less",
	"ness",
	"lessness",
	"fuless",
	"ment",
	"fully",
	"lyable",
	"lyables",
	"ual",
	"ually",
	"uallies",
	"uality",
	"ualities",
	"ally",
	"allies",
	"alities",
	"ties",
	"y",
	"sy",
	"er",
	"ers",
	"ser",
	"sers",
	"es",
	"ses",
	"ed",
	"sed",
	"ves",
	"or",
	"ors",
	"sor",
	"sors",
	"st",
	"sts",
	"ist",
	"ists",
	"ism",
	"ing",
	"ings",
	"sing",
	"sings",
	"ion",
	"ions",
	"sion",
	"sions",
	"ible",
	"ibles",
	"ibility",
	"ibilities",
	"man",
	"mans"
]
const Y_SPECIFIC_SUFFIX_LIST = [
	"ie",
	"ies",
	"ied",
	"ier",
	"iers",
	"ior",
	"iors",
	"iless",
	"iness",
	"tate",
	"tates",
	"tated",
	"tion"
]

var normal_file_path: String = Automaton.WORD_WORK_CATEGORY_FILE_PATH

var interface_node: AutomatonCategorizerInterface = null
var word_list:PackedStringArray = WordUtility.dictionary.words.words
var current_category_list = {}
var auto_categorizing_normal_variants = true

signal word_categories_updated

func _init(_interface_node:AutomatonCategorizerInterface) -> void:
	interface_node = _interface_node
	load_category_list_from_file()
	_disable_z_keybind()

# Removes the keybind which blocks the z key from being typed. 
# Figured out entirely by Xanderath/Emarald64 for his co-op mod
func _disable_z_keybind() -> void:
	var keybind=InputEventKey.new()
	keybind.physical_keycode=KEY_Z
	InputMap.action_erase_event("ui_accept",keybind)



# Can return bool in case the interface node wants to confirm the word was added
func write_or_remove_word(word:String, work_type: int) -> bool:
	if not word_list.has(word):
		return false
	if work_type < 4: # Anything other than "None" was selected.
		_assign_word_work_category(word, work_type)
	else:
		if current_category_list.keys().has(word):
			current_category_list.erase(word)
			word_categories_updated.emit()
	return true

func _assign_word_work_category(word: String, work_type: int) -> void:
	current_category_list[word] = work_type
	if auto_categorizing_normal_variants:
		var full_list = _get_normal_word_variants(word)
		var confirmed_list = await interface_node.user_confirm_auto_categorized_list(full_list)
		if confirmed_list.is_empty():
			word_categories_updated.emit()
			return
		for extra_word in confirmed_list:
			current_category_list[extra_word] = work_type
		word_categories_updated.emit()
	else:
		word_categories_updated.emit()

func save_category_list_to_file(file_path:String = normal_file_path) -> void:
	var data_to_save = JSON.stringify(current_category_list,"",false)
	var new_file = FileAccess.open(file_path, FileAccess.WRITE)
	new_file.store_line(data_to_save)
	new_file.close()

func load_category_list_from_file(file_path:String = normal_file_path) -> void:
	current_category_list.clear()
	var json_string = FileAccess.get_file_as_string(file_path)
	var saved_list = JSON.parse_string(json_string)
	assert(saved_list is Dictionary, "Data inside the allocated json is not a dictionary.")
	for entry in saved_list.keys():
		saved_list[entry] = int(saved_list[entry])
	current_category_list.assign(saved_list)
	#print_list_statistics()

func get_index_of_word_on_word_list(word: String) -> int:
	return word_list.find(word)

func get_full_word_list_size() -> int:
	return word_list.size()

func set_auto_categorizing(new_value: bool) -> void:
	auto_categorizing_normal_variants = new_value

func _get_normal_word_variants(base_word: String) -> Array:
	
	
	var full_array = []
	
	var reduced_core = base_word.substr(0,base_word.length()-1)
	var expanded_core = base_word + base_word[-1]
	
	for suffix in SUFFIX_LIST:
		full_array.append( "%s%s" % [base_word, suffix] )
		full_array.append( "%s%s" % [reduced_core, suffix] )
		full_array.append( "%s%s" % [expanded_core, suffix] )
	
	
	if base_word[-1] == "y":
		full_array.remove_at(full_array.find("%s%s" % [reduced_core, "y"]))
		for y_suffix in Y_SPECIFIC_SUFFIX_LIST:
			full_array.append( "%s%s" % [base_word, y_suffix] )
			full_array.append( "%s%s" % [expanded_core, y_suffix] )
			full_array.append( "%s%s" % [reduced_core, y_suffix] )
	
	# Lowering the base for the exponent considerably
	full_array = _get_real_words_from_hypotetical_list(full_array)
	
	for suffixed_word_index in range(full_array.size()-1):
		for prefix_index in range(PREFIX_LIST.size()-1):
			var suffixed_word = full_array[suffixed_word_index]
			var prefix = PREFIX_LIST[prefix_index]
			full_array.append( "%s%s" % [prefix, suffixed_word] )
	
	for prefix in PREFIX_LIST:
		full_array.append( "%s%s" % [prefix, base_word] )
	
	
	full_array = _get_real_words_from_hypotetical_list(full_array)
	var no_repeat_array = []
	for word in full_array:
		if not word in no_repeat_array:
			no_repeat_array.append(word)
	
	no_repeat_array.sort()
	
	return no_repeat_array

func _get_real_words_from_hypotetical_list(hypotetical_list: Array) -> Array:
	var return_array = []
	for hypotetical_word in hypotetical_list:
		if hypotetical_word in word_list:
			return_array.append(hypotetical_word)
	
	return return_array

func mass_classify_single_list(list: Array, classification: Automaton.WORK_TYPES) -> void:
	for word in list:
		current_category_list[word] = classification

func _classify_slurs():
	#_mass_classify_single_list(WordUtility.dictionary.word_flags[6].words,Automaton.WORK_TYPES.INSTINCT)
	mass_classify_single_list(WordUtility.dictionary.word_flags[4].words, Automaton.WORK_TYPES.REPRESSION)

# TODO: add a script to automatically classify all the plurals of -er words to -ers

func print_list_statistics() -> void:
	var category_word_counts = [0,0,0,0]
	for word in current_category_list.keys():
		category_word_counts[current_category_list[word]] += 1
	var result_string = """
	Instinct words:   %s
	insight words:    %s
	Attachment words: %s
	Repression words: %s
	""" % [category_word_counts[0],category_word_counts[1],category_word_counts[2],category_word_counts[3]]
	print(result_string)

extends Spell

signal finished_word_algorithm

var current_thread : Thread = null
var is_running_thread: bool = false

func _use():
	var tiles = []
	var found_word = false
	var attempt_limit = 50
	
	var dictionary = WordUtility.dictionary.words
	var all_tiles = tile_board.get_tiles()
	var typeless_all_types: Array = []
	
	for tile in all_tiles:
		typeless_all_types.append(tile)
	
	var word_size = int( all_tiles.size() / 1.5 )
	
	if not main.spell_banner.is_active():
		main.spell_banner.slide_in(self)
		await main.spell_banner.anim.animation_stopped
	
	while word_size > 0:
		var specific_length_words = dictionary.get_words_by_length(word_size,word_size)
		
		for x in range(attempt_limit):
			var word: String = rng.spell.pick_random(specific_length_words)
			var possible_tiles: Array = []
			current_thread = Thread.new()
			current_thread.start(_can_write_word_with_word_builder.bind(possible_tiles,word,typeless_all_types))
			is_running_thread = true
			await finished_word_algorithm
			is_running_thread = false
			found_word = not possible_tiles.is_empty()
			if found_word:
				tiles = possible_tiles
				break
		
		if found_word:
			break
		else:
			word_size -= 1
	
	await Game.timeout(0.12)
	var letter_interval = 0.06
	main.spell_banner.slide_out()
	if found_word:
		for tile in tiles:
			word_builder.try_add_tile(tile)
			AudioManager.play_sound(Sounds.UI.TILE_CLICK)
			await Game.timeout(letter_interval)
			letter_interval += 0.01
		await tile_board.wait_for_idle_tiles()
	
	_post_use(found_word)


# Quite a bit of the code in this file refrains from using typed arrays because working
# with multithreads makes you learn really fast that some parts of godot don't liked 
# typed non-GDScript things
func _can_write_word_with_word_builder(output: Array, word: String, given_tiles: Array):
	var tile_faces: Dictionary[int,String] = {}
	var longest_face_size = 0
	
	for tile_index in range(given_tiles.size()):
		var tile = given_tiles[tile_index]
		if not tile.is_shimmering() and not tile.face.contains("/"): 
			tile_faces[tile_index] = tile.faces[0]
			if tile.faces[0].length() > longest_face_size:
				longest_face_size = tile.faces[0].length()
	
	var replica_word = ""
	var used_tiles: Array = []
	var impossible_to_continue = false
	var word_matches = false
	
	var chunk_length = longest_face_size
	
	while not impossible_to_continue and not word_matches and chunk_length > 0:
		var full_word_fragment_size = replica_word.length() + chunk_length
		var found_valid_chunck = false
		for face_index in range(tile_faces.size()):
			var face = tile_faces[face_index]
			var tile = given_tiles[face_index]
			if not given_tiles.has(tile):
				continue
			if used_tiles.has(tile):
				continue
			
			var face_length = face.length()
			var substring = word.substr(0,min(word.length(),full_word_fragment_size))
			var summed_to_replica_word = replica_word + face
			if (
				face_length == chunk_length and
				substring == summed_to_replica_word
			):
				found_valid_chunck = true
				replica_word += face
				used_tiles.append(tile)
				break
		
		if not found_valid_chunck: # All faces with size equal to the current face size search don't match progression
			if chunk_length == 0:
				impossible_to_continue = true
				break
			chunk_length -= 1
		else:
			chunk_length = longest_face_size
		if replica_word == word:
			word_matches = true
			break
	
	var final_output = used_tiles if word_matches else []
	output.append_array(final_output)

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	if is_running_thread:
		if not current_thread.is_alive():
			current_thread.wait_to_finish()
			finished_word_algorithm.emit()

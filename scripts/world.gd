# world.gd
extends Node3D

class_name GameWorld

const DIALOGUE_PATH: String = "res://dialogue.json"
const CHARACTER_IMAGE_PATH: String = "res://assets/characters/{0}/{1}.png"
const DIALOGUE_UI_SCENE: PackedScene = preload("res://ui/DialogueUI.tscn")

@onready var spawnsets_root: Node = $spawnsets
@onready var camera: Camera3D = null

var full_dialogue_data: Dictionary = {}
var current_act_dialogue_nodes: Dictionary = {}
var active_characters: Dictionary = {} # Stores references to character root nodes (e.g., sindre Node3D)
var dialogue_start_points: Dictionary = {} # Maps character_id to {act_index, initial_dialogue_id}
var current_act_initial_poses: Dictionary = {} # NEW: To store initial poses for the current act

@onready var dialogue_ui: Control = $DialogueUI

var current_text_task = null

var current_act_index: int = 0
var current_dialogue_id: String = ""
var is_dialogue_active: bool = false

func init_ui():
	dialogue_ui = DIALOGUE_UI_SCENE.instantiate()

	get_tree().root.add_child.call_deferred(dialogue_ui)
	await dialogue_ui.tree_entered

	print("DialogueUI instantiated and _ready() should have completed.")

	dialogue_ui.hide()

	if dialogue_ui.has_signal("finished"):
		dialogue_ui.connect("finished", Callable(self, "_on_dialogue_ui_dialogue_progressed"))
	else:
		push_error("DialogueUI node not found or missing 'finished' signal.")

	if dialogue_ui.has_signal("choice_selected"):
		dialogue_ui.connect("choice_selected", Callable(self, "_on_dialogue_ui_choice_selected"))
	else:
		push_error("DialogueUI node not found or missing 'choice_selected' signal. (dialogue_ui is null: %s)" % (dialogue_ui == null))


func _ready():
	init_ui()
	load_full_dialogue()
	# The initial character loading needs to happen AFTER full_dialogue_data is loaded
	# because we now depend on initial_poses from that data.
	# We will call _load_characters_from_spawnsets() specifically for act 0 here,
	# and then again when acts change.
	
	# Load the first act's initial poses and characters
	if !full_dialogue_data.is_empty() and full_dialogue_data["acts"].size() > 0:
		set_current_act(0) # This will load initial poses and characters for act 0
	else:
		push_error("No acts found in dialogue data, cannot initialize game world.")
		
	set_process(true)


# NEW FUNCTION: Centralized act setting
func set_current_act(act_index: int):
	if act_index < 0 or act_index >= full_dialogue_data["acts"].size():
		push_error("Invalid act index provided to set_current_act: ", act_index)
		return

	current_act_index = act_index
	var act_data = full_dialogue_data["acts"][current_act_index]

	# Update current_act_initial_poses
	current_act_initial_poses = act_data.get("initial_poses", {})
	print("GameWorld: Loaded initial poses for Act %d: %s" % [current_act_index, current_act_initial_poses])

	# Now load characters based on the scene hierarchy for this act and apply initial poses
	_load_characters_from_spawnsets() # This function will now use current_act_initial_poses

	# Also load the dialogue nodes for the current act
	load_act_dialogue(current_act_index)


func _load_characters_from_spawnsets():
	if spawnsets_root == null:
		push_error("GameWorld: 'spawnsets' Node not found as a direct child of MainScene. Check scene tree.")
		return

	active_characters.clear() # Clear previously active characters
	print("GameWorld: Scanning for characters under 'spawnsets' in current act...")

	# Instead of iterating through all acts under spawnsets, we'll focus on the current act node
	# based on current_act_index or a specific act name convention
	# Assuming your spawnsets are named act0, act1, etc., or you have a way to identify the current act's container.
	# For simplicity, let's just make ALL characters under spawnsets visible with their initial pose
	# and then filter by current_act_index for dialogue.
	# A more advanced system might hide characters not in the current act.
	
	# For now, let's iterate ALL acts and load characters,
	# but only apply the initial pose if it's defined in current_act_initial_poses.
	# This ensures characters that appear later in the game are still registered.
	
	for act_node in spawnsets_root.get_children():
		# This part remains similar for registration but the initial pose application changes
		if act_node is Node and act_node.name.begins_with("act"):
			for char_node in act_node.get_children():
				if char_node is Node:
					var sprite_node = char_node.get_node_or_null("Sprite3D")
					if sprite_node:
						active_characters[char_node.name] = char_node
						print("    GameWorld: Found character in scene tree: %s at %s" % [char_node.name, char_node.get_path()])
						char_node.visible = true # Make the root node visible
						
						# --- MODIFIED CODE START ---
						# Apply initial pose if defined for this character in the current act
						var character_name = char_node.name
						if current_act_initial_poses.has(character_name):
							var initial_pose = current_act_initial_poses[character_name]
							set_character_texture(sprite_node, character_name, initial_pose)
							print("      Character '%s' initial pose set to '%s'." % [character_name, initial_pose])
						else:
							# If no initial pose is defined for this act, just ensure sprite is visible without specific texture
							# or set a hardcoded fallback 'default' if it's always expected.
							# For now, we'll just ensure it's visible but might not have a texture if not specified.
							sprite_node.visible = true
							print("      Character '%s' root node visible: %s, Sprite3D visible: %s (no initial pose in current act data)." % [character_name, char_node.visible, sprite_node.visible])
						# --- MODIFIED CODE END ---

					else:
						push_warning("    GameWorld: Node '%s' at path '%s' under '%s' does not have a 'Sprite3D' child. It will not be registered as a dialogue character for texture/pose changes." % [char_node.name, char_node.get_path(), act_node.name])
				else:
					push_warning("    GameWorld: Non-Node child found under '%s': %s. Skipping." % [act_node.name, char_node])
		else:
			push_warning("  GameWorld: Non-act node found under 'spawnsets': %s at %s. Skipping." % [act_node.name, act_node.get_path()])

	if active_characters.is_empty():
		push_warning("GameWorld: No characters with 'Sprite3D' children found under 'spawnsets' in the scene tree. Dialogue textures will likely fail.")
	else:
		print("GameWorld: Dynamically registered characters: ", active_characters.keys())


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if is_dialogue_active:
			pass
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if not is_dialogue_active:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func load_full_dialogue():
	var file = FileAccess.open(DIALOGUE_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open dialogue file at: " + DIALOGUE_PATH)
		return

	var json_result = JSON.parse_string(file.get_as_text())
	if json_result == null:
		push_error("Invalid JSON in dialogue file.")
		return

	if not json_result.has("acts") or not json_result["acts"] is Array:
		push_error("Dialogue JSON must contain an 'acts' array at the root.")
		return

	full_dialogue_data = json_result
	print("Successfully loaded full dialogue data with ", full_dialogue_data["acts"].size(), " acts.")

	dialogue_start_points.clear()
	for i in range(full_dialogue_data["acts"].size()):
		var act_data = full_dialogue_data["acts"][i]
		if act_data.has("dialogue") and act_data["dialogue"] is Array and !act_data["dialogue"].is_empty():
			var first_entry = act_data["dialogue"][0]
			var character_id = first_entry.get("character", "")
			var initial_dialogue_id = first_entry.get("id", "")

			if !character_id.is_empty() and character_id != "Player" and !initial_dialogue_id.is_empty():
				if dialogue_start_points.has(character_id):
					push_warning("Dialogue start point for character '%s' already registered. Overwriting with Act %d." % [character_id, i])
				dialogue_start_points[character_id] = {
					"act_index": i,
					"initial_dialogue_id": initial_dialogue_id
				}
				print("Registered start point for character '%s': Act %d, Dialogue ID '%s'" % [character_id, i, initial_dialogue_id])
			elif character_id == "Player":
				push_warning("Skipping start point for 'Player' character in Act %d, as dialogue should be initiated by NPC interaction." % i)
			else:
				push_warning("Act %d first dialogue entry missing 'character' or 'id'. Cannot register automatic start point." % i)
		else:
			push_warning("Act %d has no dialogue entries. Cannot register automatic start point." % i)


func load_act_dialogue(act_index: int):
	if full_dialogue_data.is_empty() || !full_dialogue_data.has("acts") || !full_dialogue_data["acts"] is Array:
		push_error("Full dialogue data is not loaded or malformed. Cannot load act dialogue.")
		current_act_dialogue_nodes.clear()
		return

	if act_index < 0 or act_index >= full_dialogue_data["acts"].size():
		push_error("Invalid act index provided: ", act_index, ". Cannot load act dialogue.")
		current_act_dialogue_nodes.clear()
		return

	var act_data = full_dialogue_data["acts"][act_index]
	var act_id = act_data.get("act_id", "Act_" + str(act_index))

	if not act_data.has("dialogue") or not act_data["dialogue"] is Array:
		push_error("Act '%s' is missing the 'dialogue' array or it's not an Array. Actual type: %s. Cannot load act dialogue." % [act_id, typeof(act_data.get("dialogue", null))])
		current_act_dialogue_nodes.clear()
		return

	current_act_dialogue_nodes.clear()
	var raw_dialogue_array = act_data["dialogue"]
	for entry in raw_dialogue_array:
		if entry.has("id"):
			current_act_dialogue_nodes[entry["id"]] = entry
		else:
			push_error("Dialogue entry missing 'id' in act '%s': %s. This entry will be skipped." % [act_id, entry])


func _on_character_interacted(character_id: String):
	if is_dialogue_active:
		print("Dialogue is already active. Ignoring new interaction with '%s'." % character_id)
		return

	if dialogue_start_points.has(character_id):
		var start_info = dialogue_start_points[character_id]
		is_dialogue_active = true
		start_act(start_info.act_index, start_info.initial_dialogue_id)
	else:
		push_warning("No dialogue registered to start for character: %s. Is this character in the JSON's first dialogue entry for an act?" % character_id)


func get_current_act_id() -> String:
	if full_dialogue_data.is_empty() or !full_dialogue_data.has("acts") or !full_dialogue_data["acts"] is Array || current_act_index < 0 || current_act_index >= full_dialogue_data["acts"].size():
		return "Invalid Act"
	var act_data = full_dialogue_data["acts"][current_act_index]
	return act_data.get("act_id", "Act_" + str(current_act_index))


func start_act(act_index: int, initial_dialogue_id: String):
	if full_dialogue_data.is_empty() || !full_dialogue_data.has("acts") || !full_dialogue_data["acts"] is Array || act_index < 0 || act_index >= full_dialogue_data["acts"].size():
		push_error("Cannot start act: Invalid act index ", act_index)
		is_dialogue_active = false
		if dialogue_ui:
			dialogue_ui.hide_dialogue()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	set_current_act(act_index) # Use the new function to set act and load initial poses
	current_dialogue_id = initial_dialogue_id

	is_dialogue_active = true
	if dialogue_ui:
		dialogue_ui.show_dialogue()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		push_error("DialogueUI is not initialized!")
		is_dialogue_active = false

	display_current_dialogue_line()


func set_character_texture(sprite_node: Sprite3D, character: String, pose: String):
	var lowercase_character = character.to_lower()
	var lowercase_pose = pose.to_lower()
	var texture_path = CHARACTER_IMAGE_PATH.format([lowercase_character, lowercase_pose])

	print("GameWorld: Attempting to load texture for '%s' pose '%s' from: %s" % [character, pose, texture_path]) # LOGGING TEXTURE PATH ATTEMPT

	var texture = load(texture_path)
	if texture == null:
		push_error("Failed to load texture: %s for character '%s' pose '%s'. Make sure the file exists, is a valid image (e.g., .png), and path/case match. Check the 'res://assets/characters/{char_folder}/{pose_name}.png' structure." % [texture_path, character, pose])
		sprite_node.texture = null
		sprite_node.visible = false # Hide sprite if texture fails to load
		return

	sprite_node.texture = texture
	sprite_node.visible = true
	sprite_node.billboard = BaseMaterial3D.BILLBOARD_DISABLED # Ensure this is disabled for Y-axis rotation
	print("GameWorld: Successfully loaded and set texture for '%s' pose '%s'. Sprite3D visible: %s, Texture assigned: %s" % [character, pose, sprite_node.visible, (sprite_node.texture != null)])


func set_character_pose(character: String, pose: String):
	if not active_characters.has(character):
		push_error("Cannot set pose: Character '%s' not found in active_characters list (was not loaded from scene tree). Is the name correct in JSON and scene tree and located under 'spawnsets/actX'?" % [character])
		return

	var character_node_parent = active_characters[character]
	var sprite_node = character_node_parent.get_node_or_null("Sprite3D")

	if sprite_node == null:
		push_error("Sprite3D node not found for character: %s. Expected it as a child of '%s' (node path: %s). Please ensure the Sprite3D is named 'Sprite3D'." % [character, character_node_parent.get_name(), character_node_parent.get_path()])
		return

	set_character_texture(sprite_node, character, pose)


func _on_dialogue_ui_dialogue_progressed():
	print("Dialogue progressed signal received. Current dialogue ID: ", current_dialogue_id)

	var current_entry = current_act_dialogue_nodes.get(current_dialogue_id)
	if current_entry == null:
		push_error("Current dialogue ID '%s' not found in current act. Ending dialogue." % current_dialogue_id)
		end_dialogue()
		return

	if current_entry.has("next_id"):
		current_dialogue_id = current_entry["next_id"]
		display_current_dialogue_line()
	elif current_entry.get("trigger_next_act", false):
		print("Trigger 'trigger_next_act' found on current line. Advancing act...")
		advance_to_next_act()
	else:
		print("End of current dialogue branch for ID: ", current_dialogue_id, ". Ending dialogue.")
		end_dialogue()


func _on_dialogue_ui_choice_selected(next_id: String):
	print("Choice selected, jumping to ID: ", next_id)
	current_dialogue_id = next_id
	display_current_dialogue_line()
	

func display_current_dialogue_line():
	print("GameWorld: Entering display_current_dialogue_line for ID: ", current_dialogue_id) # NEW

	if current_act_dialogue_nodes.is_empty() or dialogue_ui == null:
		push_error("Dialogue data for current act is empty or DialogueUI not set. Cannot display line.")
		end_dialogue()
		return

	var current_entry = current_act_dialogue_nodes.get(current_dialogue_id)

	if current_entry == null:
		push_error("Dialogue entry for ID '%s' not found in current act. Ending dialogue." % current_dialogue_id)
		end_dialogue()
		return

	print("GameWorld: Found dialogue entry: ", current_entry) # NEW

	var entry_type = current_entry.get("type", "dialogue")
	print("GameWorld: Entry type: ", entry_type) # NEW

	if entry_type == "dialogue":
		var character = current_entry.get("character", "")
		var text = current_entry.get("text", "...")
		var pose = current_entry.get("pose", "default")

		print("GameWorld: Displaying dialogue for char: '%s', text: '%s', pose: '%s'" % [character, text, pose]) # NEW

		if !character.is_empty():
			if character != "Player":
				set_character_pose(character, pose)
				var char_node_parent = active_characters.get(character)
				var sprite_node = char_node_parent.get_node_or_null("Sprite3D") if char_node_parent else null
				var pose_texture = sprite_node.texture if sprite_node else null
				dialogue_ui.display_dialogue_line(character, text, pose_texture)
			else:
				dialogue_ui.display_dialogue_line("Player", text, null)
		else:
			dialogue_ui.display_dialogue_line("", text, null)
	elif entry_type == "choice":
		var options = current_entry.get("options", [])
		print("GameWorld: Displaying choices with options: ", options) # NEW
		if options.is_empty():
			push_error("Choice entry '%s' has no options defined. Ending dialogue." % current_dialogue_id)
			end_dialogue()
			return
		dialogue_ui.display_choices(options)
	else:
		push_error("Unknown dialogue entry type: %s for ID: %s. Ending dialogue." % [entry_type, current_dialogue_id])
		end_dialogue()




func end_dialogue():
	print("Dialogue session completed.")
	if dialogue_ui:
		dialogue_ui.hide_dialogue()
	is_dialogue_active = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func advance_to_next_act():
	var next_act_index = current_act_index + 1

	if next_act_index < full_dialogue_data["acts"].size():
		print("Advancing to act index: ", next_act_index)
		# Use the new set_current_act to properly load characters and dialogue for the next act
		set_current_act(next_act_index)

		var next_act_data = full_dialogue_data["acts"][next_act_index]
		var initial_id_for_next_act = ""
		if next_act_data.has("dialogue") and next_act_data["dialogue"] is Array and !next_act_data["dialogue"].is_empty():
			initial_id_for_next_act = next_act_data["dialogue"][0].get("id", "")
			if initial_id_for_next_act.is_empty():
				push_warning("First entry in Act %s has no ID. Defaulting to empty string for initial ID. This act might not start correctly." % next_act_index)

		if initial_id_for_next_act.is_empty():
			push_error("Next act (%d) has no valid starting dialogue ID. Cannot advance." % next_act_index)
			end_dialogue()
		else:
			# Start dialogue with the initial ID of the new act
			start_act(next_act_index, initial_id_for_next_act)
	else:
		print("No more acts. End of game.")
		if dialogue_ui:
			dialogue_ui.display_dialogue_line("Game Over", "The End", null)
			await get_tree().create_timer(2.0).timeout
			dialogue_ui.hide_dialogue()
		is_dialogue_active = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta):
	if camera == null || !is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return

	for character_name in active_characters:
		var character_node_parent = active_characters[character_name]
		if character_node_parent and is_instance_valid(character_node_parent) and character_node_parent.visible:
			var sprite_node = character_node_parent.get_node_or_null("Sprite3D")
			if sprite_node != null and is_instance_valid(sprite_node) and sprite_node.visible:
				apply_y_axis_billboard(sprite_node)


func apply_y_axis_billboard(sprite: Sprite3D):
	if camera == null or !is_instance_valid(sprite) or !is_instance_valid(camera):
		return

	var sprite_pos = sprite.global_position
	var camera_pos = camera.global_position

	var direction = Vector2(camera_pos.x - sprite_pos.x, camera_pos.z - sprite_pos.z)
	var angle = atan2(direction.y, direction.x) + PI + (PI/2)

	sprite.rotation.y = -angle

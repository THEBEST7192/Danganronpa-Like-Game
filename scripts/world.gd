# world.gd
extends Node3D

class_name GameWorld

const DIALOGUE_PATH: String = "res://dialogue.json"
const CHARACTER_IMAGE_PATH: String = "res://assets/characters/{0}/{1}.png"
const DIALOGUE_UI_SCENE: PackedScene = preload("res://ui/DialogueUI.tscn")

@onready var spawnsets_root: Node = $spawnsets
@onready var dialogue_ui: Control
@onready var player_node: CharacterBody3D = null # Reference to the player node
@onready var camera: Camera3D = null # Reference to the player's camera

var full_dialogue_data: Dictionary = {}
var current_act_dialogue_nodes: Dictionary = {}
var active_characters: Dictionary = {} # Stores references to character root nodes (e.g., sindre Node3D)
var dialogue_start_points: Dictionary = {} # Maps character_id to {act_index, initial_dialogue_id}
var current_act_initial_poses: Dictionary = {} # NEW: To store initial poses for the current act

var current_text_task = null

var current_act_index: int = 0
var current_dialogue_id: String = ""
var is_dialogue_active: bool = false
var original_camera_transform: Transform3D # To store player camera's original transform
var character_in_dialogue: Node3D = null # The character currently being talked to


func init_ui():
	dialogue_ui = DIALOGUE_UI_SCENE.instantiate()

	get_tree().root.add_child.call_deferred(dialogue_ui)
	await dialogue_ui.tree_entered

	print("DialogueUI instantiated and _ready() should have completed.")

	dialogue_ui.hide()

	# Connect to the NEW 'line_finished' signal for linear progression
	if dialogue_ui.has_signal("line_finished"):
		dialogue_ui.connect("line_finished", Callable(self, "_on_dialogue_line_finished"))
	else:
		push_error("DialogueUI node not found or missing 'line_finished' signal. Check DialogueUI.gd.")

	if dialogue_ui.has_signal("choice_selected"):
		dialogue_ui.connect("choice_selected", Callable(self, "_on_dialogue_ui_choice_selected"))
	else:
		push_error("DialogueUI node not found or missing 'choice_selected' signal. (dialogue_ui is null: %s)" % (dialogue_ui == null))


func _ready():
	init_ui()
	load_full_dialogue()

	player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		camera = player_node.get_node_or_null("Camera3D")
		if camera:
			original_camera_transform = camera.global_transform
		else:
			push_error("GameWorld: Player node found but no 'Camera3D' child. Make sure your player scene has a Camera3D node.")
	else:
		push_error("GameWorld: Player node not found. Ensure your player is in a group named 'player'.")

	if !full_dialogue_data.is_empty() and full_dialogue_data["acts"].size() > 0:
		set_current_act(0)
	else:
		push_error("No acts found in dialogue data, cannot initialize game world.")

	set_process(true)


func set_current_act(act_index: int):
	if act_index < 0 or act_index >= full_dialogue_data["acts"].size():
		push_error("Invalid act index provided to set_current_act: ", act_index)
		return

	current_act_index = act_index
	var act_data = full_dialogue_data["acts"][current_act_index]

	current_act_initial_poses = act_data.get("initial_poses", {})
	print("GameWorld: Loaded initial poses for Act %d: %s" % [current_act_index, current_act_initial_poses])

	_load_characters_from_spawnsets()

	load_act_dialogue(current_act_index)


func _load_characters_from_spawnsets():
	if spawnsets_root == null:
		push_error("GameWorld: 'spawnsets' Node not found as a direct child of MainScene. Check scene tree.")
		return

	active_characters.clear()
	print("GameWorld: Scanning for characters under 'spawnsets' in current act...")

	for act_node in spawnsets_root.get_children():
		if act_node is Node and act_node.name.begins_with("act"):
			for char_node in act_node.get_children():
				if char_node is Node:
					var sprite_node = char_node.get_node_or_null("Sprite3D")
					if sprite_node:
						active_characters[char_node.name] = char_node
						print("    GameWorld: Found character in scene tree: %s at %s" % [char_node.name, char_node.get_path()])
						char_node.visible = true

						var character_name = char_node.name
						if current_act_initial_poses.has(character_name):
							var initial_pose = current_act_initial_poses[character_name]
							set_character_texture(sprite_node, character_name, initial_pose)
							print("      Character '%s' initial pose set to '%s'." % [character_name, initial_pose])
						else:
							sprite_node.visible = true
							print("      Character '%s' root node visible: %s, Sprite3D visible: %s (no initial pose in current act data)." % [character_name, char_node.visible, sprite_node.visible])

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
	pass # All input handling moved to player.gd for clarity, and to prevent conflicts with dialogue system.


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
		character_in_dialogue = active_characters.get(character_id)
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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	set_current_act(act_index)
	current_dialogue_id = initial_dialogue_id

	is_dialogue_active = true
	if dialogue_ui:
		dialogue_ui.show_dialogue()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		push_error("DialogueUI is not initialized!")
		is_dialogue_active = false

	if player_node:
		# Player must have set_physics_process method for this to work
		if player_node.has_method("set_physics_process"):
			player_node.set_physics_process(false)
		if player_node.has_method("set_velocity"):
			player_node.velocity = Vector3.ZERO
		if player_node.has_node("AnimationPlayer"):
			player_node.get_node("AnimationPlayer").play("idle")

	if camera:
		original_camera_transform = camera.global_transform

	display_current_dialogue_line()


func set_character_texture(sprite_node: Sprite3D, character: String, pose: String):
	var lowercase_character = character.to_lower()
	var lowercase_pose = pose.to_lower()
	var texture_path = CHARACTER_IMAGE_PATH.format([lowercase_character, lowercase_pose])

	print("GameWorld: Attempting to load texture for '%s' pose '%s' from: %s" % [character, pose, texture_path])

	var texture = load(texture_path)
	if texture == null:
		push_error("Failed to load texture: %s for character '%s' pose '%s'. Make sure the file exists, is a valid image (e.g., .png), and path/case match. Check the 'res://assets/characters/{char_folder}/{pose_name}.png' structure." % [texture_path, character, pose])
		sprite_node.texture = null
		sprite_node.visible = false
		return

	sprite_node.texture = texture
	sprite_node.visible = true
	sprite_node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
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


func _on_dialogue_line_finished():
	print("Dialogue line finished signal received. Current dialogue ID: ", current_dialogue_id)

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
	print("GameWorld: Entering display_current_dialogue_line for ID: ", current_dialogue_id)

	if current_act_dialogue_nodes.is_empty() or dialogue_ui == null:
		push_error("Dialogue data for current act is empty or DialogueUI not set. Cannot display line.")
		end_dialogue()
		return

	var current_entry = current_act_dialogue_nodes.get(current_dialogue_id)

	if current_entry == null:
		push_error("Dialogue entry for ID '%s' not found in current act. Ending dialogue." % current_dialogue_id)
		end_dialogue()
		return

	print("GameWorld: Found dialogue entry: ", current_entry)

	var entry_type = current_entry.get("type", "dialogue")
	print("GameWorld: Entry type: ", entry_type)

	if entry_type == "dialogue":
		var character = current_entry.get("character", "")
		var text = current_entry.get("text", "...")
		var pose = current_entry.get("pose", "default")

		print("GameWorld: Displaying dialogue for char: '%s', text: '%s', pose: '%s'" % [character, text, pose])

		if !character.is_empty():
			if character != "Player":
				set_character_pose(character, pose)
				var char_node_parent = active_characters.get(character)
				character_in_dialogue = char_node_parent
				var sprite_node = char_node_parent.get_node_or_null("Sprite3D") if char_node_parent else null
				var pose_texture = sprite_node.texture if sprite_node else null
				dialogue_ui.display_dialogue_line(character, text, pose_texture)
			else:
				character_in_dialogue = player_node
				dialogue_ui.display_dialogue_line("Player", text, null)
		else:
			character_in_dialogue = null
			dialogue_ui.display_dialogue_line("", text, null)

		if character_in_dialogue:
			_set_camera_focus_on_character(character_in_dialogue)

	elif entry_type == "choice":
		var options = current_entry.get("options", [])
		print("GameWorld: Displaying choices with options: ", options)
		if options.is_empty():
			push_error("Choice entry '%s' has no options defined. Ending dialogue." % current_dialogue_id)
			end_dialogue()
			return
		dialogue_ui.display_choices(options)
		if character_in_dialogue:
			_set_camera_focus_on_character(character_in_dialogue)
		else:
			_set_camera_focus_on_character(player_node)

	else:
		push_error("Unknown dialogue entry type: %s for ID: %s. Ending dialogue." % [entry_type, current_dialogue_id])
		end_dialogue()


func _set_camera_focus_on_character(target_character: Node3D):
	if camera == null or !is_instance_valid(camera) or target_character == null or !is_instance_valid(target_character):
		push_warning("GameWorld: Cannot focus camera, camera or target character is null/invalid.")
		return

	var char_global_pos = target_character.global_position

	# 1. Define the point on the character to look at (e.g., face/upper chest)
	var look_at_point = char_global_pos + Vector3(0, 1.2, 0) # Adjust Y (1.2m) to match your character's face height

	# 2. Define a relative offset from the character for the camera's position.
	# These values are in the character's LOCAL space.
	# X: right/left of character's center
	# Y: height above character's base
	# Z: distance in front/behind character (negative Z means in front of character's forward)
	var camera_local_offset = Vector3(0.5, 0.5, -2.0) # Adjust these values!

	# 3. Transform the local offset into a global position relative to the character.
	# This ensures the camera is always positioned correctly relative to the character's orientation.
	var target_camera_pos = target_character.global_transform.origin + \
							target_character.global_transform.basis.x * camera_local_offset.x + \
							target_character.global_transform.basis.y * camera_local_offset.y + \
							target_character.global_transform.basis.z * camera_local_offset.z

	# Ensure the target camera position is above the ground, if it somehow calculates below.
	target_camera_pos.y = max(target_camera_pos.y, char_global_pos.y + 0.5) # Keep camera at least 0.5m above character's base

	# Smoothly move camera
	var tween = get_tree().create_tween()
	tween.tween_property(camera, "global_position", target_camera_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(camera, "look_at").bind(look_at_point, Vector3.UP))
	# Optionally, you can also tween the camera's rotation directly if `look_at` is too abrupt,
	# but `look_at` in a callback after position tween is usually fine for dialogue.

	# Make the player character look at the NPC as well
	if player_node and is_instance_valid(player_node):
		var player_look_target = char_global_pos
		player_look_target.y = player_node.global_position.y # Keep player's Y-level
		player_node.look_at(player_look_target, Vector3.UP, true) # Look at the character, without tilting

func end_dialogue():
	print("Dialogue session completed.")
	if dialogue_ui:
		dialogue_ui.hide_dialogue()
	is_dialogue_active = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if player_node:
		if player_node.has_method("set_physics_process"):
			player_node.set_physics_process(true)
		if player_node.has_method("camera_reset_rotation"):
			player_node.camera_reset_rotation() # This method handles camera reset within player script

	# Tween camera back to original position (relative to player)
	if camera:
		var tween = get_tree().create_tween()
		tween.tween_property(camera, "global_transform", original_camera_transform, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	character_in_dialogue = null


func advance_to_next_act():
	var next_act_index = current_act_index + 1

	if next_act_index < full_dialogue_data["acts"].size():
		print("Advancing to act index: ", next_act_index)
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

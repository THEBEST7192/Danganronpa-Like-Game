extends Node3D

const CHARACTER_IMAGE_PATH: String = "res://assets/characters/{0}/{1}.png"

@onready var spawnsets: Node = $spawnsets

var dialogue_data: Array = []
var active_characters: Dictionary = {}

# Reference to the camera for billboard calculations
var camera: Camera3D = null

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Load initial act
	load_dialogue()
	spawn_characters()
	
	# Start the process function to handle custom billboard rotation
	set_process(true)
	
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
func load_dialogue():
	var file = FileAccess.open("res://dialogue.json", FileAccess.READ)
	if not file:
		push_error("Failed to open dialogue file")
		return

	var json_result = JSON.parse_string(file.get_as_text())
	if json_result == null:
		push_error("Invalid JSON in dialogue file")
		return

	dialogue_data = json_result
	print("Successfully loaded ", dialogue_data.size(), " dialogue entries")

# Function to spawn characters based on dialogue data
func spawn_characters():
	# Make sure spawnsets is valid
	if spawnsets == null:
		push_error("Cannot spawn characters: spawnsets is null")
		return
	
	print("Spawning characters at: " + str(spawnsets.get_path()))
	
	# Track which characters have already been spawned
	var spawned_characters := {}
	
	for entry in dialogue_data:
		if not entry.has("character"):
			continue
			
		var character = entry["character"]
		var pose = entry.get("pose", "default")
		
		if spawned_characters.has(character):
			continue
			
		spawned_characters[character] = true
		
		# Find the character's spawn node in the current act
		var character_node = null
		
		# Look through all act folders
		for act_node in spawnsets.get_children():
			var potential_node = act_node.get_node_or_null(character)
			if potential_node != null:
				character_node = potential_node
				break
		
		if character_node == null:
			push_error("Missing character spawn location: %s" % [character])
			continue
		
		print("Spawning character: %s at %s" % [character, character_node.get_path()])
		
		# Get the Sprite3D node
		var sprite_node = character_node.get_node_or_null("Sprite3D")
		if sprite_node == null:
			push_error("Sprite3D node not found for character: %s" % [character])
			continue
		
		# Load and apply the texture
		set_character_texture(sprite_node, character, pose)
		
		# Store reference to the character node
		active_characters[character] = character_node

# Function to set character texture based on character name and pose
func set_character_texture(sprite_node: Sprite3D, character: String, pose: String):
	# Format the path to the character's texture
	var texture_path = CHARACTER_IMAGE_PATH.format([character, pose])
	
	# Load the texture
	var texture = load(texture_path)
	if texture == null:
		push_error("Failed to load texture: %s" % [texture_path])
		return
	
	# Apply the texture to the sprite
	sprite_node.texture = texture
	
	# Make sure the sprite is visible
	sprite_node.visible = true
	
	# Disable built-in billboard and use our custom Z-axis rotation instead
	sprite_node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	
	print("Applied texture %s to character %s" % [pose, character])

# Function to update character pose
func set_character_pose(character: String, pose: String):
	if not active_characters.has(character):
		push_error("Character not found: %s" % [character])
		return
		
	var character_node = active_characters[character]
	var sprite_node = character_node.get_node_or_null("Sprite3D")
	
	if sprite_node == null:
		push_error("Sprite3D node not found for character: %s" % [character])
		return
		
	set_character_texture(sprite_node, character, pose)

# Process function to handle custom Y-axis-only billboard rotation
func _process(_delta):
	# Get the camera if we don't have it yet
	if camera == null:
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return
	
	# Update all active character sprites to face the camera (Y-axis rotation only)
	for character_name in active_characters:
		var character_node = active_characters[character_name]
		var sprite_node = character_node.get_node_or_null("Sprite3D")
		if sprite_node != null:
			# Apply custom Y-axis billboard rotation
			apply_y_axis_billboard(sprite_node)

# Function to apply Y-axis-only billboard rotation to a sprite
# This makes the sprite rotate only horizontally to face the camera
#
# The rotation works by calculating the angle between the sprite and camera
# in the XZ plane (horizontal plane), then applying that rotation around the Y axis.
# 
# Note: We add PI/2 (90 degrees) to the calculated angle to correct the sprite orientation.
# This is necessary because in Godot:
# - The default forward direction is -Z (when rotation is 0)
# - Sprites by default face +Z
# - We need to rotate them by 90 degrees to make them face the camera correctly
func apply_y_axis_billboard(sprite: Sprite3D):
	# Skip if camera is not available
	if camera == null:
		return
	
	# Get the direction from sprite to camera (in global space)
	var sprite_pos = sprite.global_position
	var camera_pos = camera.global_position
	
	# We only care about the horizontal direction (X and Z components)
	var direction = Vector2(camera_pos.x - sprite_pos.x, camera_pos.z - sprite_pos.z)
	
	# Calculate the angle in the XZ plane
	# Note: atan2 takes (y, x) parameters, and for our horizontal rotation
	# we want the sprite to face the camera, so we use Z as Y and X as X
	# We add PI to make the sprite face the camera directly
	# We also add PI/2 (90 degrees) to correct the sprite orientation
	var angle = atan2(direction.y, direction.x) + PI + (PI/2)
	
	# Create a rotation that only affects the Y axis (vertical axis in Godot)
	# This preserves the sprite's up direction while making it face the camera horizontally
	sprite.rotation.y = -angle

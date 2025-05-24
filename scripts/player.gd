# player.gd
extends CharacterBody3D

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var speed = 5
var jump_speed = 5
var mouse_sensitivity = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var interaction_raycast: RayCast3D = $Camera3D/InteractionRaycast
@onready var game_world: GameWorld # This is correct, as long as world.gd has class_name GameWorld

var camera_initial_rotation: Vector3

func _ready():
	game_world = get_tree().get_root().get_children()[0] as GameWorld

	if game_world == null:
		push_error("Player: Could not find 'GameWorld' script on the main scene root node. Check Project Settings -> Application -> Run -> Main Scene and ensure 'world.gd' has 'class_name GameWorld' and is attached to that scene's root.")

	if interaction_raycast:
		interaction_raycast.target_position = Vector3(0, 0, -2)
		interaction_raycast.collision_mask = 1 << 1 # Layer 2 (for characters)
	else:
		print("Player: Missing InteractionRaycast node")

	camera_initial_rotation = camera.rotation

func _input(event):
	# If dialogue is active, only process the 'ui_accept' for dialogue progression
	if game_world.is_dialogue_active:
		if event.is_action_pressed("ui_accept"):
			# Pass the event to the dialogue UI to handle progression
			# We don't want player.gd to consume it if dialogue is active.
			# The DialogueUI's _input will catch this if it's visible.
			pass # Let the event propagate to DialogueUI's _input
		# Consume all other input events if dialogue is active, to prevent player movement/camera rotation
		if event is InputEventMouseMotion:
			get_viewport().set_input_as_handled() # Prevent mouse motion from rotating player/camera
		if event is InputEventKey and (event.physical_keycode == KEY_W or event.physical_keycode == KEY_A or \
										event.physical_keycode == KEY_S or event.physical_keycode == KEY_D or \
										event.physical_keycode == KEY_SPACE):
			get_viewport().set_input_as_handled() # Prevent movement keys from propagating
		return # Stop further processing in player script if dialogue is active

	# Handle mouse motion (only if dialogue is NOT active)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -deg_to_rad(70), deg_to_rad(70))

	# Interaction Input (only if dialogue is NOT active)
	if Input.is_action_just_pressed("interact"):
		print("Interact key pressed!")
		if interaction_raycast.is_colliding():
			var collider = interaction_raycast.get_collider()
			print("Raycast hit: ", collider.name, " type: ", collider.get_class())

			if collider and game_world:
				var character_root_node = collider.get_parent()
				if character_root_node:
					game_world._on_character_interacted(character_root_node.name)
				else:
					print("Hit Area3D, but parent character node not found.")
			else:
				print("Hit non-interactable object or game_world reference missing.")

	# Mouse mode toggle (always allow releasing mouse, but don't re-capture if dialogue is active)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta):
	# Apply gravity regardless of dialogue state
	velocity.y += -gravity * delta

	# Only allow horizontal movement and jumping if dialogue is NOT active
	if !game_world.is_dialogue_active:
		var input = Input.get_vector("left", "right", "forward", "back")
		var movement_dir = transform.basis * Vector3(input.x, 0, input.y)
		if movement_dir.length() != 0:
			$AnimationPlayer.play("walk")
		else:
			$AnimationPlayer.play("idle")
		velocity.x = movement_dir.x * speed
		velocity.z = movement_dir.z * speed

		if is_on_floor() and Input.is_action_just_pressed("jump"):
			velocity.y = jump_speed
	else:
		# If dialogue is active, zero out horizontal velocity
		velocity.x = 0
		velocity.z = 0
		$AnimationPlayer.play("idle") # Ensure character is idle during dialogue

	# Always call move_and_slide to apply gravity and handle collisions
	move_and_slide()


func camera_reset_rotation():
	# This function will be called by GameWorld to reset camera to player's view
	camera.rotation = camera_initial_rotation

extends CharacterBody3D

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var speed = 5
var jump_speed = 5
var mouse_sensitivity = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var interaction_raycast: RayCast3D = $Camera3D/InteractionRaycast
@onready var game_world: GameWorld # This is correct, as long as world.gd has class_name GameWorld

func _ready():
	# Get a reference to the main scene's root, which should be your MainScene node
	# This is generally the most robust way to get the main scene's root script.
	game_world = get_tree().get_root().get_children()[0] as GameWorld

	if game_world == null:
		push_error("Player: Could not find 'GameWorld' script on the main scene root node. Check Project Settings -> Application -> Run -> Main Scene and ensure 'world.gd' has 'class_name GameWorld' and is attached to that scene's root.")
		# As a fallback or for debugging, if game_world is still null, it means
		# either the first child isn't your main scene, or MainScene doesn't
		# have world.gd with class_name GameWorld attached.
		# You can try:
		# game_world = get_node("/root/MainScene") as GameWorld # If MainScene is explicitly loaded as a global child
		# OR:
		# game_world = get_parent() as GameWorld # If player is a direct child of MainScene

	if interaction_raycast:
		interaction_raycast.target_position = Vector3(0, 0, -2)
		interaction_raycast.collision_mask = 1 << 1 # Layer 2 (for characters)
	else:
		print("Player: Missing InteractionRaycast node")
		

func _input(event):
	# Handle mouse motion first
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -deg_to_rad(70), deg_to_rad(70))

	# Interaction Input
	if Input.is_action_just_pressed("interact"):
		print("Interact key pressed!")
		if interaction_raycast.is_colliding():
			var collider = interaction_raycast.get_collider()
			print("Raycast hit: ", collider.name, " type: ", collider.get_class()) # <<< THIS IS KEY FOR DEBUGGING

			if collider and game_world:
				var character_root_node = collider.get_parent() # Assuming collider is a child of the character's root node
				if character_root_node:
					game_world._on_character_interacted(character_root_node.name)
				else:
					print("Hit Area3D, but parent character node not found.") # <<< This could indicate a problem
			else:
				print("Hit non-interactable object or game_world reference missing.") # <<< This too

	# Continue existing input handling for mouse capture/release
	if event.is_action_pressed("ui_cancel"):
		if game_world and game_world.is_dialogue_active:
			pass
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# This seems to be the part where you capture mouse for gameplay
	if not (game_world and game_world.is_dialogue_active):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	velocity.y += -gravity * delta
	var input = Input.get_vector("left", "right", "forward", "back")
	var movement_dir = transform.basis * Vector3(input.x, 0, input.y)
	if movement_dir.length() != 0:
		$AnimationPlayer.play("walk")
	else:
		$AnimationPlayer.play("idle")
	velocity.x = movement_dir.x * speed
	velocity.z = movement_dir.z * speed

	move_and_slide()
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_speed

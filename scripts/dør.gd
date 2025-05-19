extends Node3D

@export var rotation_duration := 0.5
@onready var door_node: Node3D = $SelveDøren
@onready var door_collision: CollisionShape3D = $SelveDøren/StaticBody3D/CollisionShape3D
@onready var proximity_area: Area3D = $ProximityArea
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var is_open = false
var player_in_range = false
var closed_yaw := 0.0
var player_node: Node3D = null

func _ready():
	closed_yaw = door_node.rotation_degrees.y

	if audio_player.stream == null:
		audio_player.stream = load("res://assets/sfx/DoorSFX.mp3")

	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)

func _process(_delta):
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle_door()

func toggle_door():
	if not player_node:
		return

	is_open = !is_open

	var door_global_pos = door_node.global_transform.origin
	var player_pos = player_node.global_transform.origin
	var to_player = (player_pos - door_global_pos).normalized()

	var door_forward = -door_node.global_transform.basis.z.normalized()
	var dot = door_forward.dot(to_player)

	var swing_direction = 1 if dot < 0 else -1
	var open_yaw = closed_yaw + (90 * swing_direction)
	var target_yaw = open_yaw if is_open else closed_yaw

	audio_player.play()

	var tween = create_tween()
	tween.tween_property(door_node, "rotation_degrees:y", target_yaw, rotation_duration)

""" # Logic to toggle if you can trough door after it is opened
	if is_open:
		await tween.finished
		door_collision.disabled = true
	else:
		door_collision.disabled = false
"""

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		player_node = body

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		player_node = null

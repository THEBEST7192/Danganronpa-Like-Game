extends Control

signal finished
signal text_completed

@onready var name_label = $Panel/NameLabel
@onready var text_label = $Panel/RichTextLabel
@onready var portrait = $Panel/TextureRect
@onready var continue_indicator = $Panel/ContinueIndicator
@onready var audio_player = $AudioStreamPlayer

var text_speed = 0.05 # seconds per character
var punctuation_delay = 0.2 # extra delay for punctuation

func set_character_name(char_name: String):  # Changed parameter name from 'name' to 'char_name'
	name_label.text = char_name

func set_character_portrait(texture: Texture2D):
	portrait.texture = texture

func type_text(text: String):
	text_label.visible_ratio = 0
	text_label.text = text
	
	await _type_text_task(text)
	text_completed.emit()

func _type_text_task(text: String):
	text_label.visible_characters = 0
	var total_chars = text.length()
	
	for i in range(total_chars + 1):
		if !is_instance_valid(text_label):
			break
			
		text_label.visible_characters = i
		
		# Play sound for non-space characters
		if i < total_chars && text[i] != " ":
			play_text_sound(text[i])
		
		# Variable speed for punctuation
		var delay = text_speed
		if i < total_chars && text[i] in [".", "!", "?", ","]:
			delay += punctuation_delay
			
		await get_tree().create_timer(delay).timeout

func play_text_sound(character: String):
	# Customize based on character type
	var pitch = 1.0
	if character in ["a", "e", "i", "o", "u"]:
		pitch = 1.2
	elif character in [".", "!", "?"]:
		pitch = 0.8
	
	audio_player.pitch_scale = pitch
	audio_player.play()

func wait_for_continue():
	continue_indicator.show()
	await get_tree().create_timer(0.5).timeout # Initial delay
	
	# Blink animation
	while true:
		continue_indicator.modulate.a = 1.0
		await get_tree().create_timer(0.5).timeout
		continue_indicator.modulate.a = 0.3
		await get_tree().create_timer(0.5).timeout
		
		if Input.is_action_just_pressed("ui_accept"):
			break
	
	continue_indicator.hide()
	finished.emit()

func _input(event):
	if event.is_action_pressed("ui_accept") && text_label.visible_ratio < 1:
		# Skip typing animation
		text_label.visible_characters = -1
		text_completed.emit()

func _ready():
	visible = false

func show_dialogue():
	show()

func hide_dialogue():
	hide()

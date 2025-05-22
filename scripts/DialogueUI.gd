extends Control

signal finished # Emitted when text typing is done AND continue is clicked
signal text_completed # Emitted when text typing is done (used for skipping)
signal choice_selected(next_id: String) # NEW: Emitted when a player choice is made

@onready var name_label = $Panel/NameLabel
@onready var text_label = $Panel/RichTextLabel
@onready var portrait = $Panel/TextureRect
@onready var continue_indicator = $Panel/ContinueIndicator
@onready var audio_player = $AudioStreamPlayer
@onready var choice_container = $Panel/ChoiceContainer # Updated to match your actual scene structure
@onready var choice_buttons = [] # To hold references to the actual buttons

var text_speed = 0.05 # seconds per character
var punctuation_delay = 0.2 # extra delay for punctuation

func _ready():
	visible = false
	# Ensure we have references to all UI elements
	if !name_label or !text_label or !portrait or !continue_indicator or !choice_container:
		push_error("DialogueUI: Missing UI elements - check if all nodes are properly referenced")
		return
		
	# Populate choice_buttons array
	for i in range(1, 4):
		var btn = choice_container.get_node_or_null("ChoiceButton" + str(i))
		if btn:
			choice_buttons.append(btn)
			# Connect to a handler, pass index
			btn.pressed.connect(_on_choice_button_pressed.bind(i - 1))
			print("Finished "+ str(i) +" button")
		else:
			push_warning("Missing ChoiceButton" + str(i) + " in DialogueUI.tscn")
	
	# Initially hide choices
	if choice_container:
		choice_container.visible = false

func set_character_name(char_name: String):
	if name_label:
		name_label.text = char_name

func set_character_portrait(texture: Texture2D):
	if portrait:
		portrait.texture = texture

# Main function to display a dialogue line (character + text)
func display_dialogue_line(char_name: String, text: String, portrait_texture: Texture2D):
	print("DialogueUI: display_dialogue_line called - char: '%s', text length: %d" % [char_name, text.length()]) # NEW
	show_dialogue()
	hide_choices()
	set_character_name(char_name)
	set_character_portrait(portrait_texture)

	# Start the typing sequence and wait for it to complete
	await type_text(text)
	text_completed.emit()

	# Wait for player to continue
	await wait_for_continue()
	finished.emit()

# Function to display choices
func display_choices(options: Array):
	print("DialogueUI: display_choices called with %d options." % options.size()) # NEW
	show_dialogue()

	if name_label:
		name_label.text = "" # Clear name label for choices

	if text_label:
		text_label.text = "" # Clear text label for choices

	if portrait:
		portrait.texture = null # Clear portrait for choices

	if continue_indicator:
		continue_indicator.visible = false # Hide continue indicator

	show_choices() # Make choice container visible

	# Set up each button
	for i in range(choice_buttons.size()):
		var button = choice_buttons[i]
		if i < options.size():
			button.text = options[i]["text"]
			button.set_meta("next_id", options[i]["next_id"]) # Store the next_id as metadata
			button.visible = true
			print("DialogueUI: Setting choice button %d text to '%s'" % [i, options[i]["text"]]) # NEW
		else:
			button.visible = false # Hide unused buttons
	show_dialogue()
	
	if name_label:
		name_label.text = "" # Clear name label for choices
	
	if text_label:
		text_label.text = "" # Clear text label for choices
	
	if portrait:
		portrait.texture = null # Clear portrait for choices
	
	if continue_indicator:
		continue_indicator.visible = false # Hide continue indicator

	show_choices() # Make choice container visible

	# Set up each button
	for i in range(choice_buttons.size()):
		var button = choice_buttons[i]
		if i < options.size():
			button.text = options[i]["text"]
			button.set_meta("next_id", options[i]["next_id"]) # Store the next_id as metadata
			button.visible = true
		else:
			button.visible = false # Hide unused buttons

func _on_choice_button_pressed(index: int):
	if index < 0 or index >= choice_buttons.size():
		push_error("Invalid choice button index: " + str(index))
		return
		
	var button = choice_buttons[index]
	var next_id = button.get_meta("next_id", "")
	if not next_id.is_empty():
		choice_selected.emit(next_id) # Emit the new signal with the target ID
		hide_choices() # Hide choices after one is selected
		# Do not hide dialogue here, let the main script manage it after the jump.

func type_text(text: String):
	print("DialogueUI: Starting type_text for: '%s'" % text) # NEW
	if !text_label:
		push_error("Text label is null in DialogueUI.type_text")
		return

	text_label.visible_ratio = 0
	text_label.text = text # Ensure text is actually set here

	text_label.visible_characters = 0
	var total_chars = text.length()

	# Use a loop with an await for each character
	for i in range(total_chars + 1):
		# If the text is skipped (visible_characters = -1), break the loop
		if text_label.visible_characters == -1:
			break
		# Check if the node is still valid (e.g., if scene is closing)
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

		# Await the timer for the typing speed
		await get_tree().create_timer(delay).timeout
	
	text_label.visible_characters = -1 # Ensure full text is shown if loop finishes

func play_text_sound(character: String):
	if !audio_player:
		return
		
	# Customize based on character type
	var pitch = 1.0
	if character in ["a", "e", "i", "o", "u"]:
		pitch = 1.2
	elif character in [".", "!", "?"]:
		pitch = 0.8

	audio_player.pitch_scale = pitch
	audio_player.play()

func wait_for_continue():
	if !continue_indicator:
		push_error("Continue indicator is null in DialogueUI.wait_for_continue")
		await get_tree().create_timer(0.5).timeout
		return
		
	continue_indicator.visible = true
	
	# Only wait for input if not already skipped
	if text_label and text_label.visible_ratio == 1:
		await get_tree().create_timer(0.5).timeout # Initial delay

		# Blink animation and wait for input
		while continue_indicator and is_instance_valid(continue_indicator):
			continue_indicator.modulate.a = 1.0
			await get_tree().create_timer(0.5).timeout
			
			if !is_instance_valid(continue_indicator):
				break
				
			continue_indicator.modulate.a = 0.3
			await get_tree().create_timer(0.5).timeout

			if Input.is_action_just_pressed("ui_accept"):
				break

	if continue_indicator and is_instance_valid(continue_indicator):
		continue_indicator.visible = false

func _input(event):
	# Skip typing animation
	if event.is_action_pressed("ui_accept") && text_label && text_label.visible_ratio < 1:
		text_label.visible_characters = -1 # Show full text instantly
		text_completed.emit() # Signal that text is now fully visible

# Custom functions for visibility
func show_dialogue():
	print("DialogueUI: Showing dialogue UI.")
	visible = true

func hide_dialogue():
	visible = false
	
	# Ensure all dialogue elements are reset/hidden when UI is hidden
	if name_label:
		name_label.text = ""
	
	if text_label:
		text_label.text = ""
	
	if portrait:
		portrait.texture = null
	
	if continue_indicator:
		continue_indicator.visible = false
	
	hide_choices()

func show_choices():
	if choice_container:
		choice_container.visible = true

func hide_choices():
	if choice_container:
		choice_container.visible = false
		
	for button in choice_buttons:
		if button:
			button.visible = false

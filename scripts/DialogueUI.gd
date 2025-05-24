# DialogueUI.gd
extends Control

signal line_finished # Emitted when a text line is fully displayed AND player presses continue
signal text_completed # Emitted when text typing is done (used for skipping)
signal choice_selected(next_id: String) # Emitted when a player choice is made

@onready var name_label = $Panel/NameLabel
@onready var text_label = $Panel/RichTextLabel
@onready var portrait = $Panel/TextureRect
@onready var continue_indicator = $Panel/ContinueIndicator
@onready var audio_player = $AudioStreamPlayer
@onready var choice_container = $Panel/ChoiceContainer
@onready var choice_buttons = [] # To hold references to the actual buttons

var text_speed = 0.05 # seconds per character
var punctuation_delay = 0.2 # extra delay for punctuation

var _waiting_for_continue_input: bool = false # Flag to manage input state for linear dialogue progression
var _current_selected_choice_index: int = -1 # NEW: Index of the currently highlighted choice button

const SELECTED_COLOR: Color = Color(0.7, 0.7, 0.7) # Slightly darker for selection
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0) # Normal color (white)

func _ready():
	visible = false
	if !name_label or !text_label or !portrait or !continue_indicator or !choice_container:
		push_error("DialogueUI: Missing UI elements - check if all nodes are properly referenced")
		return

	for i in range(1, 4):
		var btn = choice_container.get_node_or_null("ChoiceButton" + str(i))
		if btn:
			choice_buttons.append(btn)
			btn.pressed.connect(_on_choice_button_pressed.bind(i - 1))
		else:
			push_warning("Missing ChoiceButton" + str(i) + " in DialogueUI.tscn")

	if choice_container:
		choice_container.visible = false

func set_character_name(char_name: String):
	if name_label:
		name_label.text = char_name

func set_character_portrait(texture: Texture2D):
	if portrait:
		portrait.texture = texture

func display_dialogue_line(char_name: String, text: String, portrait_texture: Texture2D):
	print("DialogueUI: display_dialogue_line called - char: '%s', text length: %d" % [char_name, text.length()])
	show_dialogue()
	hide_choices()
	set_character_name(char_name)
	set_character_portrait(portrait_texture)

	_waiting_for_continue_input = false # Reset flag for linear progression

	await type_text(text)
	text_completed.emit() # Signal that typing is done

	_waiting_for_continue_input = true # Now we are explicitly waiting for input
	await wait_for_continue()
	_waiting_for_continue_input = false # Reset flag after input received

	line_finished.emit() # Signal that this specific line is done and ready for next


func display_choices(options: Array):
	print("DialogueUI: display_choices called with %d options." % options.size())
	show_dialogue()

	if name_label:
		name_label.text = ""
	if text_label:
		text_label.text = ""
	if portrait:
		portrait.texture = null
	if continue_indicator:
		continue_indicator.visible = false

	hide_choices() # Hide the blinking indicator when choices are shown
	show_choices()

	_current_selected_choice_index = -1 # Reset selection
	var first_visible_choice_set = false

	for i in range(choice_buttons.size()):
		var button = choice_buttons[i]
		if i < options.size():
			button.text = options[i]["text"]
			button.set_meta("next_id", options[i]["next_id"])
			button.visible = true
			if not first_visible_choice_set:
				_current_selected_choice_index = i # Select the first available option
				first_visible_choice_set = true
		else:
			button.visible = false
		button.modulate = NORMAL_COLOR # Ensure buttons are reset to normal color

	_update_choice_selection_visual() # Apply visual selection after setting up

func _on_choice_button_pressed(index: int):
	if index < 0 or index >= choice_buttons.size():
		push_error("Invalid choice button index: " + str(index))
		return

	var button = choice_buttons[index]
	var next_id = button.get_meta("next_id", "")
	if not next_id.is_empty():
		choice_selected.emit(next_id)
		hide_choices()
		_current_selected_choice_index = -1 # Reset selection state

func type_text(text: String):
	print("DialogueUI: Starting type_text for: '%s'" % text)
	if !text_label:
		push_error("Text label is null in DialogueUI.type_text")
		return

	text_label.visible_ratio = 0
	text_label.text = text

	text_label.visible_characters = 0
	var total_chars = text.length()

	# This loop must be interruptible if _input instantly reveals text
	for i in range(total_chars + 1):
		if text_label.visible_characters == -1: # Allows skipping by setting -1 in _input
			break
		if !is_instance_valid(text_label):
			break

		text_label.visible_characters = i

		if i < total_chars && text[i] != " ":
			play_text_sound(text[i])

		var delay = text_speed
		if i < total_chars && text[i] in [".", "!", "?", ","]:
			delay += punctuation_delay

		await get_tree().create_timer(delay).timeout

	text_label.visible_characters = -1 # Ensure full text is shown if loop finishes

func play_text_sound(character: String):
	if !audio_player:
		return

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
		await get_tree().create_timer(0.5).timeout # Small delay to avoid immediate error
		return

	continue_indicator.visible = true

	# Flashing the indicator while waiting for input
	var flash_tween = create_tween().set_loops() # Loop indefinitely until input
	flash_tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.5)
	flash_tween.tween_property(continue_indicator, "modulate:a", 0.3, 0.5)

	# NEW: Await the CustomAwaiter.
	var awaiter = CustomAwaiter.new()
	awaiter.name = "DialogueAwaiter_" + str(Time.get_ticks_msec())
	add_child(awaiter)
	await awaiter.wait_for_input() # Wait for the input event

	flash_tween.kill() # Stop the flashing tween
	if continue_indicator and is_instance_valid(continue_indicator):
		continue_indicator.visible = false
		continue_indicator.modulate.a = 1.0 # Reset opacity

	if awaiter and is_instance_valid(awaiter):
		awaiter.queue_free() # Clean up the awaiter

func _input(event):
	# If the dialogue UI is visible, we handle "ui_accept" here.
	if visible:
		if choice_container.visible: # NEW: Handle input specifically for choices
			if event.is_action_pressed("ui_down"):
				_move_choice_selection(1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_up"):
				_move_choice_selection(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept"):
				if _current_selected_choice_index != -1 && choice_buttons[_current_selected_choice_index].visible:
					# Simulate button press for the selected choice
					_on_choice_button_pressed(_current_selected_choice_index)
					get_viewport().set_input_as_handled()
		else: # Handle input for linear dialogue progression (text typing/waiting for continue)
			if event.is_action_pressed("ui_accept"):
				if text_label && text_label.visible_ratio < 1:
					# Case 1: Text is still typing, so skip to full text
					text_label.visible_characters = -1
					text_completed.emit()
					get_viewport().set_input_as_handled() # Consume this input, don't advance line yet
				elif _waiting_for_continue_input:
					# Case 2: Text is fully displayed, and we are waiting for a continue signal
					for child in get_children():
						if child is CustomAwaiter:
							child.release() # Release the awaiter
							break # Found and released, exit loop
					get_viewport().set_input_as_handled() # Consume this input
				else:
					pass # No active dialogue state to process ui_accept (e.g., just appeared, no text typed yet)

		# Consume mouse motion and movement keys if dialogue is active (prevents player movement/camera rotation)
		if event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		if event is InputEventKey and (event.physical_keycode == KEY_W or event.physical_keycode == KEY_A or \
										event.physical_keycode == KEY_S or event.physical_keycode == KEY_D or \
										event.physical_keycode == KEY_SPACE):
			get_viewport().set_input_as_handled()

# NEW: Helper functions for choice navigation
func _move_choice_selection(direction: int):
	var visible_choices = []
	for i in range(choice_buttons.size()):
		if choice_buttons[i].visible:
			visible_choices.append(i)

	if visible_choices.is_empty():
		return

	var current_visible_index = visible_choices.find(_current_selected_choice_index)
	if current_visible_index == -1: # If nothing is selected or current selected is not visible
		_current_selected_choice_index = visible_choices[0] # Select the first visible one
	else:
		current_visible_index = (current_visible_index + direction + visible_choices.size()) % visible_choices.size()
		_current_selected_choice_index = visible_choices[current_visible_index]

	_update_choice_selection_visual()

func _update_choice_selection_visual():
	for i in range(choice_buttons.size()):
		var button = choice_buttons[i]
		if button.visible:
			if i == _current_selected_choice_index:
				button.modulate = SELECTED_COLOR
			else:
				button.modulate = NORMAL_COLOR


# --- Helper functions for UI visibility ---
func show_dialogue():
	print("DialogueUI: Showing dialogue UI.")
	visible = true

func hide_dialogue():
	visible = false

	if name_label:
		name_label.text = ""
	if text_label:
		text_label.text = ""
	if portrait:
		portrait.texture = null
	if continue_indicator:
		continue_indicator.visible = false

	hide_choices()
	_current_selected_choice_index = -1 # Ensure selection is reset when hidden

func show_choices():
	if choice_container:
		choice_container.visible = true

func hide_choices():
	if choice_container:
		choice_container.visible = false

	for button in choice_buttons:
		if button:
			button.visible = false
			button.modulate = NORMAL_COLOR # Reset color when hidden


# A custom class to act as an awaitable for input.
class CustomAwaiter extends Node:
	signal released_input

	func wait_for_input():
		await released_input

	func release():
		released_input.emit()

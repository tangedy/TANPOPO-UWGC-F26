extends Node

const CURSOR := preload("res://Assets/images/drift_cursor.png")
## Tip of the arrow, in texture pixels.
const CURSOR_HOTSPOT := Vector2(16, 9)


func _ready() -> void:
	ensure()


static func ensure() -> void:
	# CursorShape is not exposed to scripts, so each shape is set by its enum value.
	for shape in 17:
		Input.set_custom_mouse_cursor(CURSOR, shape, CURSOR_HOTSPOT)
	_bind("left", [KEY_A, KEY_LEFT])
	_bind("right", [KEY_D, KEY_RIGHT])
	_bind("down", [KEY_S, KEY_DOWN])
	_bind("chase", [KEY_E])


static func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).size() > 0:
		return
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

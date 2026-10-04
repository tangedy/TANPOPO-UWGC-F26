extends Node

const CURSOR := preload("res://Assets/images/drift_cursor.png")
## Tip of the arrow, in texture pixels of the source image.
const CURSOR_HOTSPOT := Vector2(16, 9)
const CURSOR_SCALE := 0.6

static var _scaled: Texture2D


func _ready() -> void:
	ensure()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


static func ensure() -> void:
	if _scaled == null:
		var image := CURSOR.get_image()
		var size := image.get_size()
		image.resize(
			maxi(1, int(round(size.x * CURSOR_SCALE))),
			maxi(1, int(round(size.y * CURSOR_SCALE))),
			Image.INTERPOLATE_LANCZOS
		)
		_scaled = ImageTexture.create_from_image(image)
	# CursorShape is not exposed to scripts, so each shape is set by its enum value.
	var hotspot := CURSOR_HOTSPOT * CURSOR_SCALE
	for shape in 17:
		Input.set_custom_mouse_cursor(_scaled, shape, hotspot)
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

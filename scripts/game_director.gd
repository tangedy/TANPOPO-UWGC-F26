extends Node

const LEVELS: Array[PackedScene] = [
	preload("res://scenes/level_1.tscn"),
	preload("res://scenes/level_2.tscn"),
	preload("res://scenes/level_3.tscn"),
]
const TITLE_SCENE := "res://scenes/title.tscn"
const LOGO := preload("res://Assets/images/tanpopo_test.png")
const LOGO_WAVE := preload("res://drift.gdshader")
const LOGO_SCALE := 0.5
## Texture pixel where the T's ink starts, so the lines meet the letter rather than the empty margin.
const LOGO_INK_LEFT := 103.0
const CREDIT_LINES: Array[Dictionary] = [
	{"text": "Daniel", "size": 40, "gap": 14.0, "name": true},
	{"text": "Official Soundtrack + SFX", "size": 26, "gap": 6.0},
	{"text": "Programming", "size": 26, "gap": 6.0},
	{"text": "Environmental Art", "size": 26, "gap": 6.0},
	{"text": "Cutscene Coloring/Shading", "size": 26, "gap": 48.0},
	{"text": "Edy", "size": 40, "gap": 14.0, "name": true},
	{"text": "Character Sprites", "size": 26, "gap": 6.0},
	{"text": "Cutscene Animations", "size": 26, "gap": 6.0},
	{"text": "Programming", "size": 26, "gap": 48.0},
	{"text": "Matthew", "size": 40, "gap": 14.0, "name": true},
	{"text": "Programming", "size": 26, "gap": 6.0},
	{"text": "Level Design", "size": 26, "gap": 6.0},
	{"text": "Mechanic Implementation", "size": 26, "gap": 6.0},
	{"text": "Game Physics", "size": 26, "gap": 64.0},
	{"text": "Thank you so much for playing!", "size": 34, "gap": 0.0},
]
const InputSetup = preload("res://scripts/input_setup.gd")
const MEMORY_FRAME := preload("res://shaders/memory_frame.gdshader")
const POOF_SFX := preload("res://Assets/sfx/freesound_community-poof-of-smoke-87381.mp3")

## How long the black between stages takes to arrive and clear.
const FADE_OUT_TIME := 1.9
const FADE_IN_TIME := 1.6
## Extra black after the fade-out, before the memories flash, and after they finish, before the next stage fades in.
const MEMORY_PAUSE_BEFORE := 0.9
const MEMORY_PAUSE_AFTER := 1.2
## Day cliff reveal, then the fade back to the title after the credits clear.
const ENDING_FADE_IN := 3.4
const ENDING_FADE_OUT := 2.8
const CREDITS_ROLL_SPEED := 42.0

## The three memories collected this stage. Placeholder art for now; swap per stage later.
const STAGE_MEMORIES: Array[Texture2D] = [
	preload("res://Assets/images/memories/testmemor.png"),
	preload("res://Assets/images/memories/testmemor.png"),
	preload("res://Assets/images/memories/testmemor.png"),
]

@onready var world: Node = $World
@onready var fade: ColorRect = $UI/Fade
@onready var line_box: Control = $UI/LineBox

var _fade_tween: Tween
var _credits_tween: Tween
var _poof: AudioStreamPlayer
var _current_room: Node
var _level := 0
var _play_token := 0
var _debug_buttons: Array[Button] = []


func _ready() -> void:
	InputSetup.ensure()
	_poof = AudioStreamPlayer.new()
	_poof.name = "MemoryPoof"
	_poof.stream = POOF_SFX
	_poof.volume_db = 6.0
	add_child(_poof)
	fade.color = Color.BLACK
	var from_black := get_tree().has_meta("fade_from_black")
	if from_black:
		get_tree().remove_meta("fade_from_black")
	fade.modulate.a = 1.0 if from_black else 0.0
	line_box.visible = false
	_build_level_debug()
	_play_level(from_black)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_L:
		return
	_debug_select((_level + 1) % LEVELS.size())
	get_viewport().set_input_as_handled()


func present_line() -> void:
	await _fade_to(1.0, 1.2)
	if not is_inside_tree():
		return
	line_box.visible = true
	await get_tree().create_timer(2.8).timeout
	if not is_inside_tree():
		return
	line_box.visible = false


## Over the black fade between stages, flash the memories one by one, blurred and
## framed by an inky organic border.
func _flash_memories(token: int) -> void:
	if STAGE_MEMORIES.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "MemoryFlash"
	layer.layer = 11
	add_child(layer)
	# Inset equally on every side so the picture stays centered and a little inside the window.
	var vp := get_viewport().get_visible_rect().size
	var inset := minf(vp.x, vp.y) * 0.06
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = inset
	rect.offset_top = inset
	rect.offset_right = -inset
	rect.offset_bottom = -inset
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	var mat := ShaderMaterial.new()
	mat.shader = MEMORY_FRAME
	mat.set_shader_parameter("blur_amount", 18.0)
	mat.set_shader_parameter("rect_size", Vector2(vp.x - inset * 2.0, vp.y - inset * 2.0))
	rect.material = mat
	layer.add_child(rect)
	for i in STAGE_MEMORIES.size():
		if token != _play_token or not is_inside_tree():
			break
		rect.texture = STAGE_MEMORIES[i]
		# Vary the border noise so each memory frame looks a little different.
		mat.set_shader_parameter("seed", float(i) * 7.3)
		rect.modulate.a = 0.0
		if _poof:
			_poof.play()
		# Fade this memory in, hold, then fade it fully out to black before the next.
		var tween := create_tween()
		tween.tween_property(rect, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.75)
		tween.tween_property(rect, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_interval(0.25)
		await tween.finished
	if is_instance_valid(layer):
		layer.queue_free()


func _play_level(from_black: bool) -> void:
	var token := _play_token
	# Tell the next room to bring its music/ambience up from silence as it loads.
	if from_black:
		get_tree().set_meta("drift_fade_audio_in", FADE_IN_TIME)
	var scene := _swap(LEVELS[_level])
	_current_room = scene
	_refresh_level_debug()
	if from_black:
		await _fade_to(0.0, FADE_IN_TIME)
	if token != _play_token or not is_instance_valid(scene):
		return
	scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


func _on_level_returned() -> void:
	_advance.call_deferred(_play_token)


func _advance(token: int) -> void:
	if token != _play_token:
		return
	if is_instance_valid(_current_room) and _current_room.has_method("fade_audio_out"):
		_current_room.fade_audio_out(FADE_OUT_TIME)
	await _fade_to(1.0, FADE_OUT_TIME)
	if token != _play_token or not is_inside_tree():
		return
	await get_tree().create_timer(MEMORY_PAUSE_BEFORE).timeout
	if token != _play_token or not is_inside_tree():
		return
	await _flash_memories(token)
	if token != _play_token or not is_inside_tree():
		return
	await get_tree().create_timer(MEMORY_PAUSE_AFTER).timeout
	if token != _play_token or not is_inside_tree():
		return
	_level += 1
	if _level >= LEVELS.size():
		await present_line()
		if token != _play_token or not is_inside_tree():
			return
		await _play_ending(token)
		return
	await _play_level(true)


## After the last stage: day cliff, camera held on the opening frame, credits rising
## from behind the rock, then a fade out to the title.
func _play_ending(token: int) -> void:
	var debug := $UI.get_node_or_null("LevelDebug")
	if debug:
		debug.visible = false
	get_tree().set_meta("drift_hold_start", true)
	get_tree().set_meta("drift_fade_audio_in", ENDING_FADE_IN)
	var scene := _swap(LEVELS[0])
	_current_room = scene
	if is_instance_valid(scene):
		scene.set("time_of_day", 0)
	if token != _play_token or not is_inside_tree():
		return
	var credits := _build_credits(scene)
	if not await _fade_unless(0.0, ENDING_FADE_IN, token):
		return
	await get_tree().create_timer(0.7).timeout
	if token != _play_token or not is_inside_tree():
		return
	if not await _roll_credits(credits, token):
		return
	await get_tree().create_timer(0.8).timeout
	if token != _play_token or not is_inside_tree():
		return
	if is_instance_valid(scene) and scene.has_method("fade_audio_out"):
		scene.fade_audio_out(ENDING_FADE_OUT)
	if not await _fade_unless(1.0, ENDING_FADE_OUT, token):
		return
	get_tree().set_meta("fade_from_black", true)
	get_tree().change_scene_to_file(TITLE_SCENE)


func _build_credits(room: Node) -> Node2D:
	var platform := room.get_node("Platform") as Node2D
	var camera := room.get_node("Peppermint/Camera2D") as Camera2D
	var cliff := platform.get_node("Cliff") as Sprite2D
	var center := camera.get_screen_center_position()
	var half_view := get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	var cliff_scale := absf(cliff.global_scale.y)
	var cliff_top := cliff.global_position.y - cliff.texture.get_height() * cliff_scale * 0.5
	var root := Node2D.new()
	root.name = "Credits"
	# Behind the cliff (z 1) and the traveler, in front of the distant clouds.
	root.z_index = -6
	platform.add_child(root)
	var width := 880.0
	var logo_h := LOGO.get_height() * LOGO_SCALE
	var logo_w := LOGO.get_width() * LOGO_SCALE
	var logo_left := -logo_w * 0.5 + LOGO_INK_LEFT * LOGO_SCALE
	var logo := Sprite2D.new()
	logo.texture = LOGO
	logo.centered = true
	logo.scale = Vector2(LOGO_SCALE, LOGO_SCALE)
	logo.position = Vector2(0, logo_h * 0.5)
	var wave := ShaderMaterial.new()
	wave.shader = LOGO_WAVE
	wave.set_shader_parameter("wave_speed", 1.5)
	wave.set_shader_parameter("wave_freq", 10.0)
	wave.set_shader_parameter("wave_width", 0.2)
	logo.material = wave
	root.add_child(logo)
	var y := logo_h + 56.0
	for line: Dictionary in CREDIT_LINES:
		var label := Label.new()
		var size := int(line["size"])
		label.text = str(line["text"])
		label.position = Vector2(logo_left, y)
		label.size = Vector2(width, float(size) + 18.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", size)
		var is_name := bool(line.get("name", false))
		if is_name:
			label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78))
		else:
			label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.18, 0.2, 0.24, 0.55))
		label.add_theme_constant_override("outline_size", 10)
		root.add_child(label)
		y += float(size) + float(line["gap"])
	# First line starts under the grass lip, so the roll climbs out from behind the cliff.
	# Shifted right so the column sits in the open sky beside her.
	root.global_position = Vector2(center.x + 140.0, cliff_top + 36.0)
	root.set_meta("end_top", center.y - half_view.y - y - 36.0)
	return root


func _roll_credits(root: Node2D, token: int) -> bool:
	if not is_instance_valid(root):
		return false
	var end_top := float(root.get_meta("end_top"))
	var distance := root.global_position.y - end_top
	if distance < 1.0:
		return token == _play_token
	if _credits_tween and _credits_tween.is_valid():
		_credits_tween.kill()
	_credits_tween = create_tween()
	_credits_tween.tween_property(root, "global_position:y", end_top, distance / CREDITS_ROLL_SPEED).set_trans(Tween.TRANS_LINEAR)
	while _credits_tween.is_valid() and _credits_tween.is_running():
		if token != _play_token or not is_inside_tree():
			_credits_tween.kill()
			return false
		await get_tree().process_frame
	return token == _play_token and is_inside_tree()


func _fade_unless(target: float, duration: float, token: int) -> bool:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "modulate:a", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while _fade_tween.is_valid() and _fade_tween.is_running():
		if token != _play_token or not is_inside_tree():
			_fade_tween.kill()
			return false
		await get_tree().process_frame
	return token == _play_token and is_inside_tree()


func _build_level_debug() -> void:
	var bar := HBoxContainer.new()
	bar.name = "LevelDebug"
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -430.0
	bar.offset_top = 16.0
	bar.offset_right = -16.0
	bar.offset_bottom = 52.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(bar)
	var hint := Label.new()
	hint.text = "L"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	bar.add_child(hint)
	for i in LEVELS.size():
		var button := Button.new()
		button.text = str(i + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_debug_select.bind(i))
		bar.add_child(button)
		_debug_buttons.append(button)
	_refresh_level_debug()


func _debug_select(index: int) -> void:
	_play_token += 1
	_level = clampi(index, 0, LEVELS.size() - 1)
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _credits_tween and _credits_tween.is_valid():
		_credits_tween.kill()
	if get_tree().has_meta("drift_fade_audio_in"):
		get_tree().remove_meta("drift_fade_audio_in")
	if get_tree().has_meta("drift_hold_start"):
		get_tree().remove_meta("drift_hold_start")
	var debug := $UI.get_node_or_null("LevelDebug")
	if debug:
		debug.visible = true
	fade.modulate.a = 0.0
	line_box.visible = false
	var scene := _swap(LEVELS[_level])
	_current_room = scene
	_refresh_level_debug()
	if is_instance_valid(scene):
		scene.returned.connect(_on_level_returned, CONNECT_ONE_SHOT)


func _refresh_level_debug() -> void:
	for i in _debug_buttons.size():
		var button := _debug_buttons[i]
		button.modulate = Color(1, 1, 1, 1) if i == _level else Color(1, 1, 1, 0.55)


func _swap(packed: PackedScene) -> Node:
	var old: Array[Node] = []
	for child in world.get_children():
		old.append(child)
	for child in old:
		world.remove_child(child)
		child.queue_free()
	var node := packed.instantiate()
	world.add_child(node)
	return node


func _fade_to(target: float, duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "modulate:a", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _fade_tween.finished
